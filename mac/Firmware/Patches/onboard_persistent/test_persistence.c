#include "flash_binding.h"
#include "../onboard_runtime/stored_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint8_t sectors[2][4096], baseline[2][4096];
static uint8_t scratch[GMK_PROFILE_BUFFER_BYTES];
static long budget = -1;
static unsigned writes, erases;
static int layout_ok = 1, fail_read;
unsigned gmk_test_brightness;
int gmk_test_wired = 1;
static int layout(void *context) { (void)context; return layout_ok; }
static int locate(uint32_t addr, uint16_t count, unsigned *slot, unsigned *offset) {
    *slot = addr >= GMK_FLASH_SLOT1 ? 1u : 0u;
    *offset = addr - (*slot ? GMK_FLASH_SLOT1 : GMK_FLASH_SLOT0);
    return *offset < 4096u && *offset + count <= 4096u;
}
static int raw_read(void *context, uint32_t addr, uint8_t *out, uint16_t count) {
    unsigned slot, offset; (void)context;
    if (fail_read || !locate(addr, count, &slot, &offset)) return -1;
    memcpy(out, sectors[slot] + offset, count); return 0;
}
static int change(void) {
    if (budget == 0) return 0;
    if (budget > 0) --budget;
    ++writes; return 1;
}
static int raw_erase(void *context, uint32_t addr) {
    unsigned slot, offset, i; (void)context;
    if (!locate(addr, 4096, &slot, &offset) || offset) return -1;
    ++erases;
    /* Worst-order interrupted erase: the reservation marker disappears
     * before the old payload, leaving a temporarily unowned inactive slot. */
    for (i = 0; i < 4096; ++i) {
        unsigned at = (i + GMK_FLASH_OWNER_OFFSET) & 4095u;
        if (!change()) return -1;
        sectors[slot][at] = 0xff;
    }
    return 0;
}
static int raw_program(void *context, uint32_t addr, const uint8_t *in, uint16_t count) {
    unsigned slot, offset, i; (void)context;
    if (!locate(addr,count,&slot,&offset) || !count || count > 256u ||
        offset / 256u != (offset + count - 1u) / 256u) return -1;
    for (i = 0; i < count; ++i) {
        if (!change()) return -1;
        assert((sectors[slot][offset+i] & in[i]) == in[i]);
        sectors[slot][offset+i] &= in[i];
    }
    return 0;
}
gmk_flash_driver gmk_test_driver = {0,layout,raw_read,raw_erase,raw_program};
void gmk_persistent_boot(void);
void gmk_persistent_init(void);
void gmk_persistent_dispatch(uint8_t packet[32], int is_get);
void gmk_persistent_render(uint8_t frame[312], uint32_t elapsed_ms);
void gmk_persistent_key_change(uint32_t index, uint32_t down);
void gmk_test_power_cycle(void);
extern volatile uint8_t gmk_profile_active;
static void put16(uint8_t *p, unsigned n) { p[0]=(uint8_t)n; p[1]=(uint8_t)(n>>8); }
static void put32(uint8_t *p, uint32_t n) {
    unsigned i; for(i=0;i<4;++i) p[i]=(uint8_t)(n>>(i*8));
}
static void exchange(uint8_t report[32]) { gmk_persistent_dispatch(report, report[0]==8); }
static uint8_t upload(const uint8_t *p, uint16_t length, int permanent) {
    uint8_t report[32]={7,3,7,1}; uint16_t at=0;
    put32(report+4,1); put16(report+8,length); put32(report+10,gmk_profile_crc32(p,length));
    exchange(report); assert(report[9]==0);
    while(at<length) {
        uint8_t count=(uint8_t)(length-at>21u?21u:length-at);
        memset(report,0,32); report[0]=7; report[1]=3; report[2]=7; report[3]=2;
        put32(report+4,1); put16(report+8,at); report[10]=count;
        memcpy(report+11,p+at,count); exchange(report); assert(report[9]==0); at+=count;
    }
    memset(report,0,32); report[0]=7; report[1]=3; report[2]=7; report[3]=3;
    put32(report+4,1); exchange(report); assert(report[9]==0);
    memset(report,0,32); report[0]=7; report[1]=3; report[2]=7; report[3]=permanent?4:7;
    put32(report+4,1); exchange(report); return report[9];
}
static void query(uint8_t p[32]) { memset(p,0,32); p[0]=8;p[1]=3;p[2]=7;exchange(p); }
int main(void) {
    uint8_t profile[GMK_PROFILE_BUFFER_BYTES], altered[GMK_PROFILE_BUFFER_BYTES], report[32], frame[312];
    uint16_t length; unsigned before, i; long cuts, limit;
    gmk_flash_binding binding; gmk_store_io io; gmk_store_active saved;
    FILE *f=fopen("mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin","rb");
    assert(f); length=(uint16_t)fread(profile,1,sizeof(profile),f); assert(feof(f)); fclose(f);
    memcpy(altered,profile,length); altered[10]=2;
    memset(sectors,0xff,sizeof(sectors));
    assert(gmk_flash_prepare(&binding,&gmk_test_driver,&io)); assert(writes==0);
    assert(gmk_store_commit(&io,profile,length,scratch,&saved)==GMK_STORE_OK);
    assert(gmk_store_commit(&io,altered,length,scratch,&saved)==GMK_STORE_OK);
    memcpy(baseline,sectors,sizeof(sectors));
    writes=0;
    assert(gmk_store_commit(&io,profile,length,scratch,&saved)==GMK_STORE_OK);
    limit=writes;
    for(cuts=0;cuts<=limit;++cuts) {
        memcpy(sectors,baseline,sizeof(sectors)); budget=cuts;
        assert(gmk_flash_prepare(&binding,&gmk_test_driver,&io));
        (void)gmk_store_commit(&io,profile,length,scratch,&saved);
        budget=-1; before=writes;
        assert(gmk_flash_prepare(&binding,&gmk_test_driver,&io));
        assert(gmk_store_scan(&io,scratch,&saved)==GMK_STORE_OK && saved.present);
        assert(memcmp(scratch,profile,length)==0 || memcmp(scratch,altered,length)==0);
        assert(writes==before); /* Reboot restore must never repair by writing. */
    }
    printf("PASS: guarded driver preserves a valid generation at all %ld interrupted erase/program boundaries\n",limit+1);
    memcpy(sectors,baseline,sizeof(sectors));
    sectors[0][GMK_FLASH_OWNER_OFFSET]=0; /* Foreign/corrupted marker. */
    assert(gmk_flash_prepare(&binding,&gmk_test_driver,&io) && !io.erase && !io.program);
    assert(gmk_store_scan(&io,scratch,&saved)==GMK_STORE_OK && saved.present && saved.slot==1);
    before=writes; gmk_test_power_cycle(); gmk_persistent_boot();
    assert(gmk_profile_active && writes==before); query(report); assert(report[9]==5);
    puts("PASS: unknown inactive-sector contents prevent erasure but preserve the other saved profile");
    layout_ok=0; gmk_test_power_cycle(); gmk_persistent_boot(); query(report);
    assert(report[9]==5 && !gmk_profile_active); layout_ok=1;
    memset(sectors,0xff,sizeof(sectors)); fail_read=1;
    assert(gmk_flash_prepare(&binding,&gmk_test_driver,&io)); assert(!io.erase && !io.program);
    fail_read=0;
    gmk_test_power_cycle(); gmk_persistent_boot(); query(report);
    assert(report[9]==7 && report[20]==17 && !gmk_profile_active);
    before=writes; assert(upload(profile,length,1)==0 && writes>before);
    gmk_persistent_render(frame,20); assert(gmk_profile_active);
    before=writes; gmk_test_power_cycle(); gmk_test_brightness=99;
    gmk_persistent_boot(); gmk_persistent_init(); query(report);
    assert(gmk_profile_active && report[9]==7 && writes==before);
    assert(gmk_test_brightness==profile[10]);
    for(i=0;i<length;i+=19) {
        uint8_t count=(uint8_t)(length-i>19?19:length-i);
        memset(report,0,32);report[0]=8;report[1]=3;report[2]=7;report[3]=5;
        put16(report+4,i);report[6]=count;exchange(report);
        assert(report[9]==0 && memcmp(report+13,profile+i,count)==0);
    }
    puts("PASS: full adapter saves sixteen layers, restores exact bytes and brightness after power removal without writes");
    /* Isolate the held effect and validate release through the real adapter. */
    memcpy(altered,profile,344+57u+profile[400]);
    length=(uint16_t)(344+57u+profile[400]); altered[6]=1; altered[20]=0; put16(altered+8,length);
    altered[344]=9; altered[345]=1; altered[348]=255; altered[349]=255;
    altered[351]=255; altered[352]=0; altered[353]=0;
    memset(altered+358,0,26); altered[358+39/8]=1u<<(39%8); altered[371+39/8]=1u<<(39%8);
    put32(altered+12,gmk_profile_crc32(altered+32,length-32));
    assert(upload(altered,length,1)==0);gmk_persistent_render(frame,20);
    gmk_persistent_key_change(39,255);gmk_persistent_render(frame,20);assert(frame[39*3]>0);
    gmk_persistent_key_change(39,0);gmk_persistent_render(frame,20);assert(frame[39*3]==0);
    before=writes; assert(upload(altered,length,0)==0 && writes==before);
    puts("PASS: key-hold press/release reaches the renderer through the full firmware adapter");
    return 0;
}
