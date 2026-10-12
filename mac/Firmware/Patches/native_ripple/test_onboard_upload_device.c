#include "onboard_upload_device.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static gmk_upload_device device;
static uint8_t saved[GMK_PROFILE_MAX_BYTES];
static uint16_t saved_length;
static int fail_commit;
static unsigned commit_calls;

static uint16_t get16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}
static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static void put16(uint8_t *p, uint16_t value) {
    p[0] = (uint8_t)value; p[1] = (uint8_t)(value >> 8);
}
static void put32(uint8_t *p, uint32_t value) {
    for (unsigned i = 0; i < 4; ++i) p[i] = (uint8_t)(value >> (8 * i));
}
static int persist(const uint8_t *profile, uint16_t length, void *user) {
    gmk_profile_view view;
    assert(user == &saved_length);
    ++commit_calls;
    if (fail_commit || !gmk_profile_validate(profile, length, &view)) return 0;
    memcpy(saved, profile, length);
    saved_length = length;
    return memcmp(saved, profile, length) == 0;
}
static uint8_t exchange(uint8_t request[32], uint8_t reply[32], int wired) {
    assert(gmk_upload_handle(&device, request, reply, wired));
    assert(memcmp(reply + 4, "GMKU", 4) == 0 && reply[8] == 1);
    return reply[9];
}
static void begin(const uint8_t *profile, uint16_t length, uint32_t session) {
    uint8_t p[32] = {7, 3, 7, 1}, r[32];
    put32(p + 4, session); put16(p + 8, length);
    put32(p + 10, gmk_profile_crc32(profile, length));
    assert(exchange(p, r, 1) == 0 && get32(r + 10) == session && get16(r + 14) == 0);
}
static void transfer(const uint8_t *profile, uint16_t length, uint32_t session) {
    uint16_t at = 0;
    while (at < length) {
        uint8_t p[32] = {7, 3, 7, 2}, r[32];
        uint8_t count = (uint8_t)((length - at) < 21 ? length - at : 21);
        put32(p + 4, session); put16(p + 8, at); p[10] = count;
        memcpy(p + 11, profile + at, count);
        assert(exchange(p, r, 1) == 0);
        at = (uint16_t)(at + count);
        assert(get16(r + 14) == at);
    }
}
static void validate(uint16_t length, uint32_t crc, uint32_t session) {
    uint8_t p[32] = {7, 3, 7, 3}, r[32];
    put32(p + 4, session);
    assert(exchange(p, r, 1) == 0 && get16(r + 14) == length && get32(r + 16) == crc);
}
static void commit(uint16_t length, uint32_t crc, uint32_t session, int success) {
    uint8_t p[32] = {7, 3, 7, 4}, r[32];
    put32(p + 4, session);
    assert((exchange(p, r, 1) == 0) == success);
    if (success) assert(get16(r + 14) == length && get32(r + 16) == crc);
}

int main(void) {
    uint8_t original[GMK_PROFILE_MAX_BYTES], changed[GMK_PROFILE_MAX_BYTES];
    uint8_t request[32], reply[32];
    uint16_t length, at;
    uint32_t crc;
    gmk_profile_view view;
    FILE *input = fopen("mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin", "rb");
    assert(input != NULL);
    length = (uint16_t)fread(original, 1, sizeof original, input);
    assert(!ferror(input) && feof(input) && length == 1514);
    fclose(input);
    assert(gmk_profile_validate(original, length, &view));
    crc = gmk_profile_crc32(original, length);
    gmk_upload_init(&device, NULL, 0, persist, &saved_length);
    memset(request, 0, sizeof request);
    request[0] = 8; request[1] = 3; request[2] = 7;
    assert(exchange(request, reply, 1) == 7 && get16(reply + 10) == GMK_PROFILE_BUFFER_BYTES);
    assert(get16(reply + 14) == 0 && reply[12] == 21);
    assert(exchange(request, reply, 0) == 0); /* wireless save not advertised */

    begin(original, length, 0x12345678);
    memset(request, 0, sizeof request);
    request[0] = 7; request[1] = 3; request[2] = 7; request[3] = 2;
    put32(request + 4, 0x12345679); request[10] = 1;
    assert(exchange(request, reply, 1) != 0 && device.received == 0);
    put32(request + 4, 0x12345678); put16(request + 8, 1);
    assert(exchange(request, reply, 1) != 0 && device.received == 0);
    transfer(original, length, 0x12345678);
    validate(length, crc, 0x12345678);
    commit(length, crc, 0x12345678, 1);
    assert(saved_length == length && memcmp(saved, original, length) == 0);
    assert(device.active_length == length && memcmp(device.active, original, length) == 0);
    assert(device.activation_pending == 1 && device.pending == device.buffers[0]);
    memset(request, 0, sizeof request);
    request[0] = 8; request[1] = 3; request[2] = 7;
    assert(exchange(request, reply, 1) == 7 && reply[13] == 1);
    puts("PASS: device handler stages, validates and commits the complete Mac profile through bounded reports");

    memset(request, 0, sizeof request);
    request[0] = 8; request[1] = 3; request[2] = 7;
    assert(exchange(request, reply, 1) == 7 && get16(reply + 14) == length && get32(reply + 16) == crc);
    for (at = 0; at < length;) {
        uint8_t count = (uint8_t)((length - at) < 19 ? length - at : 19);
        memset(request, 0, sizeof request);
        request[0] = 8; request[1] = 3; request[2] = 7; request[3] = 5;
        put16(request + 4, at); request[6] = count;
        assert(exchange(request, reply, 1) == 0 && get16(reply + 10) == at && reply[12] == count);
        assert(memcmp(reply + 13, original + at, count) == 0);
        at = (uint16_t)(at + count);
    }
    puts("PASS: capability and 19-byte readback return the exact active profile");

    memset(request, 0, sizeof request);
    request[0] = 7; request[1] = 3; request[2] = 7; request[3] = 8;
    request[4] = 200; request[5] = 100; request[6] = 50; request[7] = 250;
    assert(exchange(request, reply, 1) == 0 && get16(reply + 14) == length &&
           get32(reply + 16) == crc);
    assert(exchange(request, reply, 0) != 0);
    request[8] = 1;
    assert(exchange(request, reply, 1) != 0);
    request[8] = 0;
    request[3] = 9; put16(request + 4, 4300); request[6] = 0; request[7] = 0;
    assert(exchange(request, reply, 1) == 0 && get32(reply + 16) == crc);
    put16(request + 4, 0);
    assert(exchange(request, reply, 1) != 0);
    put16(request + 4, 4300); request[6] = 1;
    assert(exchange(request, reply, 1) != 0);
    puts("PASS: bounded music and temperature packets require wired, active sensor layers");

    memcpy(changed, original, length);
    changed[10] = (uint8_t)((changed[10] + 1) % 5); /* valid but distinct brightness */
    assert(gmk_profile_validate(changed, length, &view));
    memset(request, 0, sizeof request);
    request[0] = 7; request[1] = 3; request[2] = 7; request[3] = 1;
    put32(request + 4, 0xabcdef01); put16(request + 8, length);
    put32(request + 10, gmk_profile_crc32(changed, length));
    assert(exchange(request, reply, 1) != 0 && device.activation_pending == 1);
    assert(device.pending == device.buffers[0]);
    gmk_upload_finish_activation(&device);
    assert(device.activation_pending == 0);
    memset(request, 0, sizeof request);
    request[0] = 8; request[1] = 3; request[2] = 7;
    assert(exchange(request, reply, 1) == 7 && reply[13] == 0);
    begin(changed, length, 0xabcdef01);
    transfer(changed, length, 0xabcdef01);
    validate(length, gmk_profile_crc32(changed, length), 0xabcdef01);
    fail_commit = 1;
    commit(length, gmk_profile_crc32(changed, length), 0xabcdef01, 0);
    assert(commit_calls == 2);
    commit(length, gmk_profile_crc32(changed, length), 0xabcdef01, 0);
    assert(commit_calls == 2);
    assert(device.active_crc == crc && memcmp(device.active, original, length) == 0);
    assert(memcmp(saved, original, length) == 0);
    puts("PASS: failed persistence preserves the previous active profile");

    memset(request, 0, sizeof request);
    request[0] = 7; request[1] = 3; request[2] = 7; request[3] = 4;
    put32(request + 4, 0xabcdef01);
    assert(exchange(request, reply, 0) != 0 && device.active_crc == crc);
    gmk_upload_init(&device, saved, saved_length, persist, &saved_length);
    assert(device.active_length == length && device.active_crc == crc);
    puts("PASS: wireless writes are rejected and a simulated reboot reloads the saved profile");

    /* A RAM-only activation is the first hardware test path: it changes no
     * flash and disappears after reboot. It is intentionally distinct from
     * Commit, whose callback must verify persistent storage. */
    gmk_upload_init(&device, NULL, 0, NULL, NULL);
    assert(exchange((uint8_t[32]){8, 3, 7, 0}, reply, 1) == 5);
    begin(original, length, 0x99887766);
    transfer(original, length, 0x99887766);
    validate(length, crc, 0x99887766);
    memset(request, 0, sizeof request);
    request[0] = 7; request[1] = 3; request[2] = 7; request[3] = 7;
    put32(request + 4, 0x99887766);
    assert(exchange(request, reply, 1) == 0 && device.active_crc == crc);
    gmk_upload_init(&device, NULL, 0, NULL, NULL);
    assert(device.active_length == 0);
    puts("PASS: RAM-only profile activation accepts a validated transfer but expires on reboot");
    return 0;
}
