#include "onboard_profile.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

void gmk_v07_init(void);
void gmk_v07_dispatch(uint8_t packet[32], int is_get);
void gmk_v07_key_down(uint32_t factory_scan_index);
void gmk_v07_render(uint8_t frame[312], uint32_t elapsed_ms);
extern volatile uint8_t gmk_v07_profile_active;

static void put16(uint8_t *p, uint16_t value) {
    p[0] = (uint8_t)value; p[1] = (uint8_t)(value >> 8);
}
static void put32(uint8_t *p, uint32_t value) {
    unsigned i;
    for (i = 0; i < 4; ++i) p[i] = (uint8_t)(value >> (8u * i));
}
static uint16_t get16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}
static void exchange(uint8_t report[32]) {
    int get = report[0] == 8;
    gmk_v07_dispatch(report, get);
    assert(report[1] == 3 && report[2] == 7);
    assert(memcmp(report + 4, "GMKU", 4) == 0);
    assert(report[8] == 1);
}
static void upload(const uint8_t *profile, uint16_t length, uint32_t session) {
    uint8_t report[32] = {0};
    uint32_t crc = gmk_profile_crc32(profile, length);
    uint16_t offset = 0;
    report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 1;
    put32(report + 4, session); put16(report + 8, length); put32(report + 10, crc);
    exchange(report);
    assert(report[9] == 0);
    while (offset < length) {
        unsigned count = length - offset > 21u ? 21u : length - offset;
        memset(report, 0, sizeof report);
        report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 2;
        put32(report + 4, session); put16(report + 8, offset);
        report[10] = (uint8_t)count;
        memcpy(report + 11, profile + offset, count);
        exchange(report);
        offset = (uint16_t)(offset + count);
        assert(report[9] == 0 && get16(report + 14) == offset);
    }
    memset(report, 0, sizeof report);
    report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 3;
    put32(report + 4, session);
    exchange(report);
    assert(report[9] == 0 && get16(report + 14) == length);
}
static uint16_t focused_w_profile(uint8_t *out, const uint8_t *all_effects) {
    const unsigned first_layer = 344u;
    uint16_t length = (uint16_t)(first_layer + 57u + all_effects[first_layer + 56u]);
    uint8_t *layer;
    memcpy(out, all_effects, length);
    out[6] = 1; out[20] = 0;
    put16(out + 8, length);
    /* Swap W's physical output LED (39) with far-right LED 103. The scan
     * event remains 39, so the renderer must apply this permutation once. */
    out[32 + 39] = 103;
    out[32 + 103] = 39;
    layer = out + first_layer;
    layer[0] = 0; layer[1] = 1; /* one enabled ripple layer, selected keys */
    put16(layer + 2, 256);
    layer[4] = 255; layer[5] = 255;
    layer[7] = 255; layer[8] = 0; layer[9] = 0;
    memset(layer + 14, 0, 26);
    layer[14 + 39 / 8] = (uint8_t)(1u << (39 % 8));
    layer[27 + 103 / 8] = (uint8_t)(1u << (103 % 8));
    put32(out + 12, gmk_profile_crc32(out + 32, length - 32));
    return length;
}
int main(void) {
    uint8_t profile[GMK_PROFILE_MAX_BYTES] = {0};
    uint8_t focused[GMK_PROFILE_MAX_BYTES] = {0};
    uint8_t built_in[344];
    uint8_t report[32] = {0};
    uint8_t frame[312] = {0};
    size_t length, i;
    uint16_t focused_length;
    unsigned colored = 0;
    gmk_profile_view view;
    FILE *input = fopen("mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin", "rb");
    assert(input);
    length = fread(profile, 1, sizeof profile, input);
    assert(!ferror(input) && feof(input));
    fclose(input);
    assert(length == 1514 && gmk_profile_validate(profile, length, &view));
    assert(view.sensor_flags == 3);

    gmk_v07_init();
    report[0] = 8; report[1] = 3; report[2] = 7; report[3] = 6;
    gmk_v07_dispatch(report, 1);
    assert(memcmp(report, "\x08\x03\x07\x06GMKD", 8) == 0 &&
           report[8] == 1 && report[9] == 0 && report[16] == 0x14 &&
           report[18] == 0x14 && report[20] == 0xc0 && report[23] == 0xd0);
    memset(report, 0, sizeof report);
    report[0] = 8; report[1] = 3; report[2] = 7; report[3] = 6;
    report[4] = 1; put16(report + 5, 4090); report[7] = 6;
    gmk_v07_dispatch(report, 1);
    assert(report[9] == 0 && report[10] == 1 && get16(report + 11) == 4090 &&
           report[13] == 6 && report[14] == 0xff && report[19] == 0xff);
    memset(report, 0, sizeof report);
    report[0] = 8; report[1] = 3; report[2] = 7; report[3] = 6;
    report[4] = 2; put16(report + 5, 4090); report[7] = 7;
    gmk_v07_dispatch(report, 1);
    assert(report[9] == 1); /* no cross-sector read */
    memset(report, 0, sizeof report);
    report[0] = 8; report[1] = 3; report[2] = 7; report[3] = 6;
    report[4] = 1; report[7] = 19;
    gmk_v07_dispatch(report, 1);
    assert(report[9] == 1); /* strictly bounded reply */
    memset(report, 0, sizeof report);
    report[0] = 8; report[1] = 3; report[2] = 7;
    exchange(report);
    assert(report[9] == 5 && get16(report + 14) == 0); /* RAM-only */
    upload(profile, (uint16_t)length, 0x10203040u);
    memset(report, 0, sizeof report);
    report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 7;
    put32(report + 4, 0x10203040u);
    exchange(report);
    assert(report[9] == 0 && gmk_v07_profile_active);

    memset(report, 0, sizeof report);
    report[0] = 8; report[1] = 3; report[2] = 7;
    exchange(report);
    assert(report[13] == 1 && get16(report + 14) == length);
    memset(report, 0, sizeof report);
    report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 1;
    put32(report + 4, 0x40506070u); put16(report + 8, 344);
    exchange(report);
    assert(report[9] == 6); /* Begin remains busy until render handoff */

    gmk_v07_render(frame, 20);
    for (i = 0; i < sizeof frame; ++i) colored += frame[i] != 0;
    assert(colored > 0);
    memset(report, 0, sizeof report);
    report[0] = 8; report[1] = 3; report[2] = 7;
    exchange(report);
    assert(report[13] == 0);

    memset(report, 0, sizeof report);
    report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 8;
    report[4] = 50; report[5] = 60; report[6] = 70; report[7] = 80;
    exchange(report);
    assert(report[9] == 0);
    memset(report, 0, sizeof report);
    report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 9;
    put16(report + 4, 6200);
    exchange(report);
    assert(report[9] == 0);

    focused_length = focused_w_profile(focused, profile);
    assert(gmk_profile_validate(focused, focused_length, &view));
    upload(focused, focused_length, 0x40506070u);
    memset(report, 0, sizeof report);
    report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 7;
    put32(report + 4, 0x40506070u);
    exchange(report);
    assert(report[9] == 0 && gmk_v07_profile_active);
    gmk_v07_render(frame, 20);
    for (i = 0; i < sizeof frame; ++i) assert(frame[i] == 0);
    gmk_v07_key_down(39); /* W: factory scan index, not remapped output */
    gmk_v07_render(frame, 20);
    assert(frame[103 * 3] > 0 && frame[39 * 3] == 0);

    /* The first image does not implement stock-effect delegation. Reject a
     * built-in profile without replacing the running Studio profile. */
    memcpy(built_in, profile, sizeof built_in);
    built_in[5] = 1; built_in[6] = 0; built_in[20] = 0;
    put16(built_in + 8, sizeof built_in);
    put32(built_in + 12, gmk_profile_crc32(built_in + 32, sizeof built_in - 32));
    assert(gmk_profile_validate(built_in, sizeof built_in, &view));
    upload(built_in, sizeof built_in, 0x50607080u);
    memset(report, 0, sizeof report);
    report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 7;
    put32(report + 4, 0x50607080u);
    exchange(report);
    assert(report[9] == 4 && gmk_v07_profile_active);
    memset(report, 0, sizeof report);
    report[0] = 8; report[1] = 3; report[2] = 7;
    exchange(report);
    assert(get16(report + 14) == focused_length);
    puts("PASS: RAM-only upload, activation, remapped W-to-LED103 ripple, scalar sensors and built-in fail-closed fallback");
    return 0;
}
