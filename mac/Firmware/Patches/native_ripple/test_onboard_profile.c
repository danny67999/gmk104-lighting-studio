#include "onboard_profile.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void put16(uint8_t *p, unsigned value) {
    p[0] = (uint8_t)value; p[1] = (uint8_t)(value >> 8);
}
static void put32(uint8_t *p, uint32_t value) {
    unsigned i;
    for (i = 0; i < 4; ++i) p[i] = (uint8_t)(value >> (8 * i));
}
static void fix_crc(uint8_t *bytes, size_t length) {
    put32(bytes + 12, gmk_profile_crc32(bytes + 32, length - 32));
}
static void rejects(const uint8_t *bytes, size_t length) {
    gmk_profile_view view;
    memset(&view, 0xa5, sizeof view);
    assert(!gmk_profile_validate(bytes, length, &view));
    assert(view.bytes != bytes); /* invalid data never creates a usable view */
}

int main(void) {
    const char *path = "mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin";
    uint8_t original[GMK_PROFILE_MAX_BYTES] = {0};
    uint8_t changed[GMK_PROFILE_MAX_BYTES] = {0};
    gmk_profile_view view;
    size_t length;
    FILE *input = fopen(path, "rb");
    assert(input != NULL);
    length = fread(original, 1, sizeof original, input);
    assert(!ferror(input) && feof(input));
    fclose(input);
    assert(length == 1514 && gmk_profile_validate(original, length, &view));
    assert(view.mode == 0 && view.layer_count == 16 && view.sensor_flags == 3);
    assert(view.requested_fps == 120 && view.layer_offsets[0] == 344);
    for (unsigned i = 0; i < 9; ++i)
        assert(original[view.layer_offsets[i]] == i);
    puts("PASS: portable firmware parser accepts the Mac all-effects, 16-layer profile vector");

    memcpy(changed, original, length);
    changed[400] ^= 1;
    rejects(changed, length);
    rejects(original, length - 1);
    memcpy(changed, original, length);
    changed[view.layer_offsets[0] + 27] ^= 1; /* wrong output mask despite valid CRC */
    fix_crc(changed, length);
    rejects(changed, length);
    memcpy(changed, original, length);
    memcpy(changed + view.layer_offsets[1] + 40,
           changed + view.layer_offsets[0] + 40, 16);
    fix_crc(changed, length);
    rejects(changed, length);
    memcpy(changed, original, length);
    changed[20] = 0; /* enabled music/temperature layers still need both */
    rejects(changed, length);
    memcpy(changed, original, length);
    changed[32] = changed[33]; /* duplicate output LED */
    fix_crc(changed, length);
    rejects(changed, length);
    memcpy(changed, original, length);
    changed[136] = 128; /* geometry is bounded to 7-bit coordinates */
    fix_crc(changed, length);
    rejects(changed, length);
    memcpy(changed, original, length);
    changed[view.layer_offsets[0] + 57] = 0xff; /* invalid UTF-8 */
    fix_crc(changed, length);
    rejects(changed, length);
    puts("PASS: checksum, length, mapping, geometry, name, mask, layer ID and sensor corruption are rejected");

    memcpy(changed, original, length);
    memset(changed + view.layer_offsets[0] + 14, 0, 26);
    fix_crc(changed, length);
    assert(gmk_profile_validate(changed, length, &view));
    puts("PASS: explicit empty key selection stays inactive even with affect-all-keys set");

    memcpy(changed, original, 344);
    changed[5] = 1; changed[6] = 0; changed[20] = 0;
    put16(changed + 8, 344); fix_crc(changed, 344);
    assert(gmk_profile_validate(changed, 344, &view) && view.mode == 1 && view.layer_count == 0);
    changed[20] = 1;
    rejects(changed, 344);
    memcpy(changed, original, 344);
    changed[5] = 2; changed[6] = 0; changed[20] = 0;
    memset(changed + 344, 0x7f, 312);
    put16(changed + 8, 656); fix_crc(changed, 656);
    assert(gmk_profile_validate(changed, 656, &view) && view.mode == 2);
    puts("PASS: built-in and manual 104-key RGB modes validate independently");
    return 0;
}
