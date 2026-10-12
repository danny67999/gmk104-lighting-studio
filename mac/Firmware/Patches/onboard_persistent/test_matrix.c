#include "../onboard_runtime/runtime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint8_t profile[GMK_PROFILE_BUFFER_BYTES], frames[60 * GMK_FIXED_FRAME_BYTES];
static gmk_runtime runtime;
static void put32(uint8_t *p,uint32_t n) { unsigned i;for(i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i)); }
static int commit(const uint8_t *p,uint16_t n,void *u) { (void)p;(void)n;(void)u;assert(!"capability check must not commit");return 0; }
static void write_file(const char *path,const uint8_t *p,size_t n) { FILE *f=fopen(path,"wb");assert(f);assert(fwrite(p,1,n,f)==n);assert(fclose(f)==0); }
int main(int argc,char **argv) {
    uint16_t length;gmk_profile_view view;gmk_fixed_renderer r,fast;
    uint8_t response[32],request[32]={8,3,7,0},frame[312],sped[312];unsigned i,j,seen[104]={0};
    FILE *f=fopen("mac/Tests/Fixtures/onboard-profile-matrix-v1.3.bin","rb");assert(f);
    length=(uint16_t)fread(profile,1,sizeof(profile),f);assert(feof(f));fclose(f);
    assert(gmk_profile_validate(profile,length,&view));assert(gmk_fixed_init(&r,&view));
    assert(profile[344]==24 && GMK_PROFILE_MAX_EFFECT_ID==24);
    gmk_runtime_init(&runtime,NULL,0,commit,NULL);assert(gmk_runtime_dispatch(&runtime,request,response,1));
    assert(response[9]==7 && response[20]==24);
    assert(gmk_fixed_render(&r,0,frame));
    for(j=0;j<104;j++) {
        unsigned row=(profile[137+j*2]-1u)/2u;
        if(frame[j*3+1])assert(row==0);
    }
    for(i=0;i<60;i++) {
        assert(gmk_fixed_render(&r,i*100,frames+i*312));
        for(j=0;j<104;j++)if(frames[i*312+j*3+1])seen[j]=1;
    }
    for(j=0;j<104;j++)assert(seen[j]); /* Every mapped key, including the number pad and bottom row. */
    assert(gmk_fixed_render(&r,1300,frame));
    profile[346]=0;profile[347]=2;put32(profile+12,gmk_profile_crc32(profile+32,length-32));
    assert(gmk_profile_validate(profile,length,&view));assert(gmk_fixed_init(&fast,&view));
    assert(gmk_fixed_render(&fast,650,sped));assert(memcmp(frame,sped,312)==0);
    /* A restricted layer never spills outside its output mask. */
    profile[345]=1;memset(profile+358,0,26);profile[358+39/8]=(uint8_t)(1u<<(39%8));profile[371+39/8]=(uint8_t)(1u<<(39%8));
    put32(profile+12,gmk_profile_crc32(profile+32,length-32));assert(gmk_profile_validate(profile,length,&view));assert(gmk_fixed_init(&fast,&view));
    for(i=0;i<60;i++) { assert(gmk_fixed_render(&fast,i*100,frame));for(j=0;j<104;j++)if(j!=39)assert(!frame[j*3]&&!frame[j*3+1]&&!frame[j*3+2]); }
    if(argc==2 && !strcmp(argv[1],"--emit-fixtures")) {
        write_file("mac/Tests/Fixtures/onboard-capabilities-v1.3.bin",response,32);
        write_file("mac/Tests/Fixtures/matrix-native-frames-v1.6.bin",frames,sizeof(frames));
    }
    /* A straight column exposes the video reference's translated motion:
       white leading head, continuous fading tail, and a traveling dark gap. */
    f=fopen("mac/Tests/Fixtures/onboard-profile-matrix-v1.3.bin","rb");assert(f);
    length=(uint16_t)fread(profile,1,sizeof(profile),f);fclose(f);
    for(j=0;j<104;j++){profile[136+j*2]=8;profile[137+j*2]=(uint8_t)(1+2*(j%6));}
    put32(profile+12,gmk_profile_crc32(profile+32,length-32));
    assert(gmk_profile_validate(profile,length,&view));assert(gmk_fixed_init(&fast,&view));
    {unsigned first=1,last_head=0,have_head=0,drops=0,wraps=0,tails=0,whites=0;
      for(i=0;i<1600;i++) {
        unsigned head=0,brightest=0,lit=0;
        assert(gmk_fixed_render(&fast,i*10,frame));
        for(j=0;j<6;j++) {
          unsigned k;for(k=j+6;k<104;k+=6)assert(!memcmp(frame+j*3,frame+k*3,3));
          if(frame[j*3+1])lit++;
          if(frame[j*3+1]>brightest){brightest=frame[j*3+1];head=j;}
          if(frame[j*3] && frame[j*3+1]>=223)whites++;
        }
        if(lit && first){assert(head==0 && lit==1);first=0;}
        if(lit){
          if(have_head && head!=last_head){if(head==0){assert(last_head==5);wraps++;}else{assert(head==last_head+1);drops++;}}
          last_head=head;have_head=1;
        }
        if(i>=500) {
          unsigned transitions=0;
          assert(lit>=4 && lit<=5);
          for(j=0;j<6;j++)if((frame[j*3+1]!=0)!=(frame[((j+1)%6)*3+1]!=0))transitions++;
          assert(transitions==2); /* One continuous tail and one dark gap. */
          for(j=1;j<4;j++)assert(frame[((head+6-j+1)%6)*3+1]>=frame[((head+6-j)%6)*3+1]);
          tails++;
        }
      }
      assert(!first && drops>30 && wraps>=6 && tails==1100 && whites>200);
      printf("PASS: reference-style white heads descend and wrap (%u steps, %u wraps), with continuous fading tails and moving dark spaces\n",drops,wraps);
    }
    for(j=0;j<104;j++){profile[136+j*2]=(uint8_t)(8+2*(j/6));profile[137+j*2]=(uint8_t)(1+2*(j%6));}
    put32(profile+12,gmk_profile_crc32(profile+32,length-32));assert(gmk_profile_validate(profile,length,&view));assert(gmk_fixed_init(&fast,&view));
    {unsigned staggered=0,seen_column[18]={0};
      for(i=0;i<1600;i++) {
        assert(gmk_fixed_render(&fast,i*10,frame));
        for(j=0;j<17;j++){
          unsigned k,lit=0;for(k=0;k<6;k++)if(frame[(j*6+k)*3+1])lit++;
          if(lit && !seen_column[j]){assert(lit==1 && frame[j*18+1]>=223);seen_column[j]=1;}
        }
        for(j=1;j<5;j++)if((frame[j*3+1]!=0)!=(frame[(j+6)*3+1]!=0))staggered++;
      }
      for(j=0;j<17;j++)assert(seen_column[j]);assert(staggered>100);
      printf("PASS: every staggered column enters at the top; moving dark gaps differ across neighboring columns (%u samples)\n",staggered);
    }
    puts("PASS: native Matrix rain reaches every key without input, matches speed scaling, and respects per-layer output masks");
    return 0;
}
