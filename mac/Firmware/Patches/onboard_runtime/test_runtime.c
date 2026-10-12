#include "runtime.h"
#include "stored_runtime.h"
#include "../onboard_storage/onboard_storage.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static gmk_runtime runtime;
static gmk_stored_runtime stored;
static gmk_runtime *current_runtime = &runtime;
static uint8_t sectors[2][GMK_STORE_SECTOR_BYTES];
static uint8_t scratch[GMK_PROFILE_MAX_BYTES];
static unsigned commits;
static int fail_commit;
static int fail_read;
static unsigned erases;

static void put16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void put32(uint8_t *p, uint32_t v) {
    unsigned i; for (i = 0; i < 4; ++i) p[i] = (uint8_t)(v >> (i * 8));
}
static int read_slot(void *user, uint8_t slot, uint16_t offset, uint8_t *out, uint16_t count) {
    (void)user;
    if (fail_read || slot >= 2 || (uint32_t)offset + count > GMK_STORE_SECTOR_BYTES) return -1;
    memcpy(out, sectors[slot] + offset, count); return 0;
}
static int erase_slot(void *user, uint8_t slot) {
    (void)user; if (slot >= 2) return -1;
    ++erases;
    memset(sectors[slot], 0xff, sizeof(sectors[slot])); return 0;
}
static int program_slot(void *user, uint8_t slot, uint16_t offset,
                        const uint8_t *in, uint16_t count) {
    unsigned i;
    (void)user;
    if (slot >= 2 || !count || (uint32_t)offset + count > GMK_STORE_SECTOR_BYTES ||
        offset / 256u != (offset + count - 1u) / 256u) return -1;
    for (i = 0; i < count; ++i) {
        if ((sectors[slot][offset + i] & in[i]) != in[i]) return -1;
        sectors[slot][offset + i] = in[i];
    }
    return 0;
}
static gmk_store_io storage = {0, read_slot, erase_slot, program_slot};
static int persist(const uint8_t *profile, uint16_t length, void *user) {
    gmk_store_active active;
    (void)user; ++commits;
    if (fail_commit) return 0;
    return gmk_store_commit(&storage, profile, length, scratch, &active) == GMK_STORE_OK;
}
static void exchange(uint8_t report[32], int wired) {
    uint8_t request[32]; memcpy(request, report, 32);
    assert(gmk_runtime_dispatch(current_runtime, request, report, wired));
    assert(memcmp(report + 4, "GMKU", 4) == 0 && report[8] == 1);
}
static uint8_t upload(const uint8_t *profile, uint16_t length, uint32_t session, int permanent) {
    uint8_t report[32] = {7, 3, 7, 1};
    uint16_t at = 0;
    put32(report + 4, session); put16(report + 8, length);
    put32(report + 10, gmk_profile_crc32(profile, length));
    exchange(report, 1); assert(report[9] == 0);
    while (at < length) {
        uint8_t count = (uint8_t)(length - at > 21u ? 21u : length - at);
        memset(report, 0, 32); report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 2;
        put32(report + 4, session); put16(report + 8, at); report[10] = count;
        memcpy(report + 11, profile + at, count); exchange(report, 1);
        assert(report[9] == 0); at = (uint16_t)(at + count);
    }
    memset(report, 0, 32); report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 3;
    put32(report + 4, session); exchange(report, 1); assert(report[9] == 0);
    memset(report, 0, 32); report[0] = 7; report[1] = 3; report[2] = 7;
    report[3] = permanent ? 4 : 7; put32(report + 4, session); exchange(report, 1);
    return report[9];
}
static uint16_t focused_profile(uint8_t *out, const uint8_t *fixture, uint8_t effect) {
    uint8_t *layer;
    uint16_t length = (uint16_t)(344u + 57u + fixture[400]);
    memcpy(out, fixture, length);
    out[6] = 1; out[20] = 0; out[11] = 60; put16(out + 8, length);
    out[32 + 39] = 103; out[32 + 103] = 39;
    layer = out + 344;
    layer[0] = effect; layer[1] = 1;
    put16(layer + 2, 256); layer[4] = 255; layer[5] = 255;
    layer[7] = 220; layer[8] = 30; layer[9] = 0;
    memset(layer + 14, 0, 26);
    layer[14 + 39 / 8] = (uint8_t)(1u << (39 % 8));
    layer[27 + 103 / 8] = (uint8_t)(1u << (103 % 8));
    put32(out + 12, gmk_profile_crc32(out + 32, length - 32));
    return length;
}
static uint16_t largest_profile(uint8_t *out, const uint8_t *fixture) {
    size_t source_at = 344, destination_at = 344, layer;
    memcpy(out, fixture, 344);
    for (layer = 0; layer < 16; ++layer) {
        memcpy(out + destination_at, fixture + source_at, 57);
        out[destination_at + 56] = 80;
        memset(out + destination_at + 57, 'x', 80);
        source_at += 57u + fixture[source_at + 56];
        destination_at += 137;
    }
    assert(destination_at == GMK_PROFILE_BUFFER_BYTES);
    put16(out + 8, (uint16_t)destination_at);
    put32(out + 12, gmk_profile_crc32(out + 32, destination_at - 32));
    return (uint16_t)destination_at;
}
int main(void) {
    uint8_t fixture[GMK_PROFILE_MAX_BYTES], focused[GMK_PROFILE_MAX_BYTES];
    uint8_t frame[GMK_FIXED_FRAME_BYTES] = {0}, report[32] = {8, 3, 7, 0};
    size_t fixture_length, i;
    uint16_t length;
    gmk_store_active saved;
    FILE *file = fopen("mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin", "rb");
    assert(file); fixture_length = fread(fixture, 1, sizeof(fixture), file);
    assert(!ferror(file) && feof(file)); fclose(file);
    memset(sectors, 0xff, sizeof(sectors));
    assert(!gmk_runtime_init(&runtime, 0, 0, persist, 0));
    exchange(report, 1); assert(report[9] == 7 && report[20] == 17);
    assert(((unsigned)report[10] | (unsigned)report[11] << 8) == GMK_PROFILE_BUFFER_BYTES);

    length = focused_profile(focused, fixture, 9);
    assert(upload(focused, length, 1, 0) == 0 && commits == 0);
    assert(gmk_runtime_step(&runtime, frame, 20));
    gmk_runtime_key_change(&runtime, 39, 255);
    assert(gmk_runtime_step(&runtime, frame, 20) && frame[103 * 3] > 0 && frame[39 * 3] == 0);
    for (i = 0; i < 250; ++i) (void)gmk_runtime_step(&runtime, frame, 20);
    assert(frame[103 * 3] > 0);
    gmk_runtime_key_change(&runtime, 39, 0);
    assert(gmk_runtime_step(&runtime, frame, 20));
    for (i = 0; i < sizeof(frame); ++i) assert(frame[i] == 0);
    gmk_runtime_key_change(&runtime, 39, 255);
    assert(gmk_runtime_step(&runtime, frame, 20) && frame[103 * 3] > 0);
    for (i = 0; i < 40; ++i) gmk_runtime_key_change(&runtime, 39, 255);
    gmk_runtime_key_change(&runtime, 39, 0); /* dropped release after overflow */
    assert(gmk_runtime_step(&runtime, frame, 20) && frame[103 * 3] == 0);
    puts("PASS: runtime forwards remapped press/release, holds without fading, and clears a dropped release");

    length = focused_profile(focused, fixture, 6);
    assert(upload(focused, length, 2, 1) == 0 && commits == 1);
    assert(gmk_runtime_step(&runtime, frame, 20) && frame[103 * 3] > 0);
    memset(&runtime, 0, sizeof(runtime)); /* simulated power removal */
    assert(gmk_store_scan(&storage, scratch, &saved) == GMK_STORE_OK && saved.present);
    assert(gmk_runtime_init(&runtime, scratch, saved.profile_length, persist, 0));
    assert(gmk_runtime_step(&runtime, frame, 20) && frame[103 * 3] > 0);
    puts("PASS: persistent journal record starts the runtime after simulated power removal without a host upload");

    assert(upload(fixture, (uint16_t)fixture_length, 3, 1) == 0 && commits == 2);
    assert(gmk_runtime_step(&runtime, frame, 20) && runtime.renderer.profile.layer_count == 16);
    assert(gmk_store_scan(&storage, scratch, &saved) == GMK_STORE_OK && saved.present);
    assert(gmk_runtime_init(&runtime, scratch, saved.profile_length, persist, 0));
    assert(runtime.renderer.profile.layer_count == 16);
    puts("PASS: all sixteen layers and their per-layer speeds survive a journal/runtime boot roundtrip");

    fail_commit = 1;
    assert(upload(focused, length, 4, 1) == 5 && commits == 3);
    memset(report, 0, 32); report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 4;
    put32(report + 4, 4); exchange(report, 1);
    assert(report[9] == 2 && commits == 3 && runtime.renderer.profile.layer_count == 16);
    puts("PASS: failed persistent save cannot repeat its commit or replace the running layout");

    memset(report, 0, 32); report[0] = 8; report[1] = 3; report[2] = 7;
    exchange(report, 0); assert(report[9] == 0 && report[20] == 17);

    /* The actual v1 bound preserves sixteen 80-byte names without three
     * sector-sized buffers in the MCU. Boot restoration invokes no writer. */
    length = largest_profile(focused, fixture);
    current_runtime = &stored.playback;
    assert(gmk_stored_runtime_init(&stored, &storage));
    {
        unsigned before = erases;
        assert(upload(focused, length, 5, 1) == 0 && erases == before + 1);
        assert(gmk_runtime_step(current_runtime, frame, 20));
        assert(gmk_stored_runtime_init(&stored, &storage));
        assert(erases == before + 1 && stored.saved.profile_length == GMK_PROFILE_BUFFER_BYTES);
        assert(stored.playback.renderer.profile.layer_count == 16);
        assert(memcmp(stored.playback.upload.active, focused, length) == 0);
        assert(gmk_runtime_step(current_runtime, frame, 20));
    }
    puts("PASS: maximum-size sixteen-layer profile boots without writes using bounded persistent-runtime buffers");

    /* Unknown storage state offers only volatile playback. The original
     * saved record is retained and a fresh read-only initialization recovers it. */
    fail_read = 1;
    assert(!gmk_stored_runtime_init(&stored, &storage));
    assert(stored.storage_result == GMK_STORE_IO_ERROR && !stored.storage_ready);
    memset(report, 0, 32); report[0] = 8; report[1] = 3; report[2] = 7;
    exchange(report, 1); assert(report[9] == 5);
    fail_read = 0;
    assert(gmk_stored_runtime_init(&stored, &storage));
    {
        unsigned before = erases;
        fail_read = 1;
        assert(upload(focused, length, 6, 1) == 5 && erases == before);
        assert(!stored.storage_ready && !stored.playback.upload.commit);
        fail_read = 0;
        memset(report, 0, 32); report[0] = 8; report[1] = 3; report[2] = 7;
        exchange(report, 1); assert(report[9] == 5);
        assert(upload(focused, length, 7, 1) == 5 && erases == before);
    }
    puts("PASS: boot/save read failures disable permanent writes for this boot and preserve the journal");

    /* A syntactically sound tail can claim more bytes than the bounded MCU
     * scratch buffer. Ignore that slot before its payload read; retain the
     * earlier valid generation. ASan checks the actual 2536-byte allocation. */
    {
        uint8_t damaged_slot = stored.saved.slot;
        uint8_t *tail = sectors[damaged_slot] + GMK_STORE_TAIL_OFFSET;
        put16(tail + 12, GMK_PROFILE_BUFFER_BYTES + 1u);
        put32(tail + 24, gmk_profile_crc32(tail, 24));
        assert(gmk_stored_runtime_init(&stored, &storage));
        assert(stored.saved.slot != damaged_slot && stored.saved.profile_length == fixture_length);
        assert(memcmp(stored.playback.upload.active, fixture, fixture_length) == 0);
        memset(report, 0, 32); report[0] = 7; report[1] = 3; report[2] = 7; report[3] = 1;
        put32(report + 4, 8); put16(report + 8, GMK_PROFILE_BUFFER_BYTES + 1u);
        exchange(report, 1); assert(report[9] == 3 && stored.playback.upload.state == 0);
    }
    puts("PASS: oversized upload and stored-tail lengths cannot overrun bounded MCU buffers");
    puts("Offline runtime tests only; physical flash binding and boot selection are still required.");
    return 0;
}
