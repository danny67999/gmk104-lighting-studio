#include "renderer.h"
#include "renderer_fixed.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static uint8_t profile[GMK_PROFILE_MAX_BYTES];
static size_t length;
static unsigned layers;

static void write16(uint8_t *p, unsigned n) {
    p[0] = (uint8_t)n;
    p[1] = (uint8_t)(n >> 8);
}
static void write32(uint8_t *p, uint32_t n) {
    unsigned i;
    for (i = 0; i < 4; ++i) p[i] = (uint8_t)(n >> (i * 8));
}
static void mask_set(uint8_t *mask, unsigned index) {
    mask[index / 8] |= (uint8_t)(1u << (index % 8));
}
static int has_color(const uint8_t *frame, unsigned led) {
    return frame[led * 3] || frame[led * 3 + 1] || frame[led * 3 + 2];
}
static unsigned rgb_level(const uint8_t *frame, unsigned led) {
    return frame[led * 3] + frame[led * 3 + 1] + frame[led * 3 + 2];
}

static void start_profile(void) {
    unsigned scan;
    memset(profile, 0, sizeof profile);
    memcpy(profile, "GMKP", 4);
    profile[4] = 1;
    profile[5] = 0; /* Lighting Studio */
    profile[7] = 20;
    profile[10] = 3;
    profile[11] = 60;
    memcpy(profile + 16, "A104", 4);
    for (scan = 0; scan < GMK_PROFILE_KEY_COUNT; ++scan) {
        profile[32 + scan] = (uint8_t)scan;
        profile[136 + 2 * scan] = (uint8_t)((scan % 13) * 2);
        profile[136 + 2 * scan + 1] = (uint8_t)((scan / 13) * 2);
    }
    length = 344;
    layers = 0;
}

/* Caller edits the fixed record, including trigger and output masks, before
 * finish_profile. Layer records are added topmost first, as in Studio. */
static uint8_t *append_layer(unsigned effect, unsigned flags,
                             unsigned red, unsigned green, unsigned blue) {
    uint8_t *layer;
    assert(layers < GMK_PROFILE_MAX_LAYERS && length + 58 <= sizeof profile);
    layer = profile + length;
    memset(layer, 0, 58);
    layer[0] = (uint8_t)effect;
    layer[1] = (uint8_t)flags;
    write16(layer + 2, 256); /* speed 1 */
    layer[4] = 255; /* intensity */
    layer[5] = 255; /* opacity */
    layer[6] = 3;
    layer[7] = (uint8_t)red;
    layer[8] = (uint8_t)green;
    layer[9] = (uint8_t)blue;
    write16(layer + 10, 256); /* music sensitivity 1 */
    layer[12] = 40;
    layer[13] = 90;
    memset(layer + 14, 255, 26); /* trigger and output: all keys */
    layer[40] = (uint8_t)++layers; /* unique UUID */
    layer[56] = 1;
    layer[57] = 'A';
    length += 58;
    return layer;
}

static void finish_profile(unsigned sensor_flags) {
    profile[6] = (uint8_t)layers;
    profile[20] = (uint8_t)sensor_flags;
    write16(profile + 8, (unsigned)length);
    write32(profile + 12, gmk_profile_crc32(profile + 32, length - 32));
}

static gmk_renderer prepare(void) {
    gmk_renderer r;
    gmk_profile_view view = {0};
    assert(gmk_profile_validate(profile, length, &view));
    assert(gmk_renderer_init(&r, &view));
    return r;
}

static gmk_fixed_renderer prepare_fixed(void) {
    gmk_fixed_renderer r;
    gmk_profile_view view;
    assert(gmk_profile_validate(profile, length, &view));
    assert(gmk_fixed_init(&r, &view));
    return r;
}

static void test_per_key_mapping_and_blend(void) {
    uint8_t frame[GMK_RENDERER_FRAME_BYTES];
    uint8_t *top;
    gmk_renderer r;
    start_profile();
    profile[32] = 103;
    profile[135] = 0;
    top = append_layer(6, 1, 0, 200, 0);
    top[5] = 128;
    memset(top + 14, 0, 26);
    mask_set(top + 14, 0); /* physical scan 0 */
    mask_set(top + 27, 103); /* mapped output LED 103 */
    append_layer(6, 1 | 8, 100, 0, 0);
    finish_profile(0);
    r = prepare();
    assert(gmk_renderer_render(&r, 0, frame) == 1);
    assert(frame[103 * 3] == 50 && frame[103 * 3 + 1] == 100);
    assert(frame[0] == 100 && frame[1] == 0);

    top[1] |= 4; /* additive blend */
    finish_profile(0);
    r = prepare();
    assert(gmk_renderer_render(&r, 0, frame) == 1);
    assert(frame[103 * 3] == 100 && frame[103 * 3 + 1] == 100);

    /* Explicit empty selection remains inert even with all-key output set. */
    top[1] |= 2;
    memset(top + 14, 0, 26);
    finish_profile(0);
    r = prepare();
    assert(gmk_renderer_render(&r, 0, frame) == 1);
    assert(frame[103 * 3] == 100 && frame[103 * 3 + 1] == 0);
    puts("PASS: mapped key selection, both blend modes, empty selection");
}

static void test_reactive_trigger_and_far_edge_ripple(void) {
    uint8_t frame[GMK_RENDERER_FRAME_BYTES];
    uint8_t *layer;
    gmk_renderer r;
    start_profile();
    layer = append_layer(1, 1 | 2, 0, 220, 255); /* rainbow ripple */
    memset(layer + 14, 0, 13);
    mask_set(layer + 14, 0);
    finish_profile(0);
    r = prepare();
    gmk_renderer_key_down(&r, 1, 0); /* unselected key must not trigger */
    assert(gmk_renderer_render(&r, 1500, frame) == 1);
    assert(!has_color(frame, 12));
    gmk_renderer_key_down(&r, 0, 0);
    assert(gmk_renderer_render(&r, 1500, frame) == 1);
    assert(has_color(frame, 12)); /* opposite end of the first row */
    assert(!has_color(frame, 91)); /* ring has not reached the far corner */

    layer[0] = 2; /* reactive */
    finish_profile(0);
    r = prepare();
    gmk_renderer_key_down(&r, 0, 0);
    assert(gmk_renderer_render(&r, 0, frame) == 1);
    assert(has_color(frame, 0) && has_color(frame, 12));
    layer[1] &= (uint8_t)~2u;
    memset(layer + 27, 0, 13);
    mask_set(layer + 27, 0);
    finish_profile(0);
    r = prepare();
    gmk_renderer_key_down(&r, 0, 0);
    assert(gmk_renderer_render(&r, 0, frame) == 1);
    assert(has_color(frame, 0) && !has_color(frame, 12));
    puts("PASS: WASD-style trigger/output separation and far-edge rainbow ripple");
}

static void test_layer_speed_changes_onboard_animation(void) {
    uint8_t slow[GMK_FIXED_FRAME_BYTES], fast[GMK_FIXED_FRAME_BYTES];
    uint8_t *layer;
    gmk_fixed_renderer fixed;
    unsigned effect;
    for (effect = 0; effect <= 2; ++effect) {
        start_profile();
        layer = append_layer(effect, 1 | 8, 255, 180, 70);
        write16(layer + 2, 128); /* 0.5x */
        finish_profile(0);
        fixed = prepare_fixed();
        gmk_fixed_key_down(&fixed, 0, 0);
        assert(gmk_fixed_render(&fixed, effect == 2 ? 500 : 200, slow) == 1);

        write16(layer + 2, 512); /* 2x */
        finish_profile(0);
        fixed = prepare_fixed();
        gmk_fixed_key_down(&fixed, 0, 0);
        assert(gmk_fixed_render(&fixed, effect == 2 ? 500 : 200, fast) == 1);
        assert(memcmp(slow, fast, sizeof slow) != 0);
        if (effect == 2) {
            assert(rgb_level(slow, 0) > rgb_level(fast, 0));
        } else {
            assert(rgb_level(slow, 1) > rgb_level(fast, 1));
            assert(rgb_level(fast, 3) > rgb_level(slow, 3));
        }
    }
    puts("PASS: per-layer speed moves both ripples and changes reactive fade in the integer firmware renderer");
}

static void test_sensor_expiration_preserves_other_layers(void) {
    uint8_t frame[GMK_RENDERER_FRAME_BYTES];
    gmk_renderer r;
    start_profile();
    append_layer(7, 1 | 8, 255, 255, 255);
    append_layer(6, 1 | 8, 0, 0, 50);
    finish_profile(1);
    r = prepare();
    assert(gmk_renderer_render(&r, 0, frame) == 1 && frame[2] == 50);
    gmk_renderer_set_music(&r, 255, 255, 255, 255, 0);
    assert(gmk_renderer_render(&r, 100, frame) == 1 &&
           (frame[0] > 0 || frame[1] > 0));
    assert(gmk_renderer_render(&r, 500, frame) == 1 &&
           frame[0] == 0 && frame[1] == 0 && frame[2] == 50);

    start_profile();
    append_layer(8, 1 | 8, 255, 255, 255);
    append_layer(6, 1 | 8, 0, 0, 50);
    finish_profile(2);
    r = prepare();
    gmk_renderer_set_temperature(&r, 9000, 0);
    assert(gmk_renderer_render(&r, 100, frame) == 1 && frame[0] > 0);
    assert(gmk_renderer_render(&r, 5000, frame) == 1 &&
           frame[0] == 0 && frame[1] == 0 && frame[2] == 50);
    puts("PASS: stale Mac sensor samples become transparent; independent layers continue");
}

static void test_all_effects_and_bounded_pulses(void) {
    uint8_t frame[GMK_RENDERER_FRAME_BYTES];
    unsigned effect, press;
    for (effect = 0; effect < 9; ++effect) {
        gmk_renderer r;
        start_profile();
        append_layer(effect, 1 | 8, 0, 220, 255);
        finish_profile(effect == 7 ? 1 : effect == 8 ? 2 : 0);
        r = prepare();
        gmk_renderer_key_down(&r, 0, 0);
        gmk_renderer_set_music(&r, 255, 255, 255, 255, 0);
        gmk_renderer_set_temperature(&r, 4000, 0);
        assert(gmk_renderer_render(&r, 0, frame) == 1);
        assert(has_color(frame, 0));
        if (effect == 4) {
            uint8_t first = frame[1];
            assert(gmk_renderer_render(&r, 1500, frame) == 1);
            assert(frame[1] > first);
        }
        for (press = 0; press < 32; ++press)
            gmk_renderer_key_down(&r, (uint8_t)(press % 104), press);
        assert(r.pulse_count == GMK_RENDERER_MAX_PULSES);
        assert(gmk_renderer_render(&r, 100, frame) == 1);
    }
    puts("PASS: all nine effect IDs render and pulse storage stays bounded");
}

static void test_other_modes_and_invalid_inputs(void) {
    uint8_t frame[GMK_RENDERER_FRAME_BYTES];
    gmk_renderer r;
    gmk_profile_view view = {0};
    start_profile();
    profile[5] = 2;
    profile[344 + 3 * 103] = 12;
    profile[344 + 3 * 103 + 1] = 34;
    profile[344 + 3 * 103 + 2] = 56;
    length = 656;
    finish_profile(0);
    r = prepare();
    assert(gmk_renderer_render(&r, 0, frame) == 1);
    assert(frame[309] == 12 && frame[310] == 34 && frame[311] == 56);
    profile[5] = 1;
    length = 344;
    finish_profile(0);
    r = prepare();
    assert(gmk_renderer_render(&r, 0, frame) == 0);
    assert(gmk_renderer_render(NULL, 0, frame) == -1);
    assert(gmk_renderer_render(&r, 0, NULL) == -1);
    assert(!gmk_renderer_init(NULL, &view));
    puts("PASS: manual RGB frame, built-in delegation, invalid inputs");
}

static void test_fixed_path(void) {
    uint8_t frame[GMK_RENDERER_FRAME_BYTES];
    uint8_t reference[GMK_RENDERER_FRAME_BYTES];
    unsigned effect;
    gmk_fixed_renderer fixed;
    gmk_renderer floating;
    uint8_t *layer;

    start_profile();
    layer = append_layer(1, 1 | 2, 0, 220, 255);
    memset(layer + 14, 0, 13);
    mask_set(layer + 14, 0);
    finish_profile(0);
    fixed = prepare_fixed();
    gmk_fixed_key_down(&fixed, 1, 0);
    assert(gmk_fixed_render(&fixed, 1500, frame) == 1 && !has_color(frame, 12));
    gmk_fixed_key_down(&fixed, 0, 0);
    assert(gmk_fixed_render(&fixed, 1500, frame) == 1 && has_color(frame, 12));

    for (effect = 0; effect < 9; ++effect) {
        unsigned led;
        unsigned long error = 0;
        start_profile();
        append_layer(effect, 1 | 8, 0, 220, 255);
        finish_profile(effect == 7 ? 1 : effect == 8 ? 2 : 0);
        fixed = prepare_fixed();
        floating = prepare();
        gmk_fixed_key_down(&fixed, 0, 0);
        gmk_renderer_key_down(&floating, 0, 0);
        gmk_fixed_set_music(&fixed, 255, 255, 255, 255, 1000);
        gmk_renderer_set_music(&floating, 255, 255, 255, 255, 1000);
        gmk_fixed_set_temperature(&fixed, 6500, 1000);
        gmk_renderer_set_temperature(&floating, 6500, 1000);
        assert(gmk_fixed_render(&fixed, 1100, frame) == 1);
        assert(gmk_renderer_render(&floating, 1100, reference) == 1);
        for (led = 0; led < GMK_RENDERER_FRAME_BYTES; ++led)
            error += frame[led] > reference[led] ?
                     frame[led] - reference[led] : reference[led] - frame[led];
        assert(error < 312u * 35u); /* approximation, not pixel parity */
        if (effect != 0 && effect != 1 && effect != 2) assert(has_color(frame, 0));
    }

    start_profile();
    append_layer(7, 1 | 8, 255, 255, 255);
    append_layer(6, 1 | 8, 0, 0, 50);
    finish_profile(1);
    fixed = prepare_fixed();
    gmk_fixed_set_music(&fixed, 255, 255, 255, 255, 0);
    assert(gmk_fixed_render(&fixed, 100, frame) == 1 && has_color(frame, 0));
    assert(gmk_fixed_render(&fixed, 500, frame) == 1 &&
           frame[0] == 0 && frame[1] == 0 && frame[2] == 50);

    start_profile();
    append_layer(8, 1 | 8, 255, 255, 255);
    append_layer(6, 1 | 8, 0, 0, 50);
    finish_profile(2);
    fixed = prepare_fixed();
    gmk_fixed_set_temperature(&fixed, 9000, 0);
    assert(gmk_fixed_render(&fixed, 100, frame) == 1 && frame[0] > 0);
    assert(gmk_fixed_render(&fixed, 5000, frame) == 1 &&
           frame[0] == 0 && frame[1] == 0 && frame[2] == 50);

    start_profile();
    profile[5] = 2;
    profile[344] = 12;
    length = 656;
    finish_profile(0);
    fixed = prepare_fixed();
    assert(gmk_fixed_render(&fixed, 0, frame) == 1 && frame[0] == 12);
    profile[5] = 1;
    length = 344;
    finish_profile(0);
    fixed = prepare_fixed();
    assert(gmk_fixed_render(&fixed, 0, frame) == 0);
    puts("PASS: integer-only path covers all effects, far-edge ripple, sensor expiry, and other modes");
}

static void test_full_sixteen_layer_vector(void) {
    uint8_t bytes[GMK_PROFILE_MAX_BYTES];
    uint8_t frame[GMK_FIXED_FRAME_BYTES];
    uint8_t reference[GMK_RENDERER_FRAME_BYTES];
    gmk_profile_view view;
    gmk_fixed_renderer fixed;
    gmk_renderer floating;
    FILE *input = fopen("mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin", "rb");
    size_t size;
    unsigned press, led;
    unsigned long difference = 0;
    clock_t started;
    assert(input != NULL);
    size = fread(bytes, 1, sizeof bytes, input);
    assert(!ferror(input) && feof(input));
    fclose(input);
    assert(size == 1514 && gmk_profile_validate(bytes, size, &view));
    assert(view.layer_count == 16 && view.sensor_flags == 3);
    assert(gmk_fixed_init(&fixed, &view));
    assert(gmk_renderer_init(&floating, &view));
    for (press = 0; press < 16; ++press) {
        gmk_fixed_key_down(&fixed, (uint8_t)press, press * 2u);
        gmk_renderer_key_down(&floating, (uint8_t)press, press * 2u);
    }
    gmk_fixed_set_music(&fixed, 200, 140, 220, 200, 50);
    gmk_renderer_set_music(&floating, 200, 140, 220, 200, 50);
    gmk_fixed_set_temperature(&fixed, 6850, 50);
    gmk_renderer_set_temperature(&floating, 6850, 50);
    assert(gmk_fixed_render(&fixed, 100, frame) == 1);
    assert(gmk_renderer_render(&floating, 100, reference) == 1);
    for (led = 0; led < GMK_FIXED_FRAME_BYTES; ++led)
        difference += frame[led] > reference[led] ?
                      frame[led] - reference[led] : reference[led] - frame[led];
    assert(difference < 312u * 75u); /* broad approximation bound */
    started = clock();
    for (led = 0; led < 100; ++led)
        assert(gmk_fixed_render(&fixed, 100u + led * 16u, frame) == 1);
    printf("PASS: 16-layer fixture; host integer render %.3f ms/frame; mean byte difference %.1f\n",
           (double)(clock() - started) * 10.0 / CLOCKS_PER_SEC,
           (double)difference / 312.0);
}

static void test_worst_case_ripple_stack(void) {
    uint8_t frame[GMK_FIXED_FRAME_BYTES];
    gmk_fixed_renderer fixed;
    clock_t started;
    unsigned layer, press, step;
    start_profile();
    for (layer = 0; layer < 16; ++layer)
        append_layer(1, 1 | 2 | 4 | 8, 0, 220, 255);
    finish_profile(0);
    fixed = prepare_fixed();
    for (press = 0; press < 16; ++press)
        gmk_fixed_key_down(&fixed, (uint8_t)press, press);
    started = clock();
    for (step = 0; step < 100; ++step)
        assert(gmk_fixed_render(&fixed, 100u + step * 16u, frame) == 1);
    assert(has_color(frame, 12));
    printf("PASS: 16 all-key rainbow-ripple layers and 16 overlapping presses; "
           "host integer render %.3f ms/frame\n",
           (double)(clock() - started) * 10.0 / CLOCKS_PER_SEC);
    started = clock();
    for (press = 0; press < 1024; ++press)
        gmk_fixed_key_down(&fixed, (uint8_t)(press % GMK_PROFILE_KEY_COUNT), press);
    printf("Host key-down distance preparation %.3f ms/press\n",
           (double)(clock() - started) * 1000.0 / (CLOCKS_PER_SEC * 1024.0));
}

static void test_cached_distances_after_slot_reuse(void) {
    gmk_fixed_renderer fixed;
    unsigned press, slot, led;
    start_profile();
    profile[32] = 103;
    profile[135] = 0;
    append_layer(1, 1 | 2 | 8, 0, 220, 255);
    finish_profile(0);
    fixed = prepare_fixed();
    for (press = 0; press < 32; ++press)
        gmk_fixed_key_down(&fixed, (uint8_t)press, press);
    assert(fixed.pulse_count == GMK_FIXED_MAX_PULSES);
    for (slot = 0; slot < GMK_FIXED_MAX_PULSES; ++slot) {
        unsigned origin = profile[32 + fixed.pulses[slot].scan_index];
        int ox = profile[136 + 2 * origin];
        int oy = profile[136 + 2 * origin + 1];
        uint16_t farthest = 0;
        for (led = 0; led < GMK_PROFILE_KEY_COUNT; ++led) {
            int dx = (int)profile[136 + 2 * led] - ox;
            int dy = (int)profile[136 + 2 * led + 1] - oy;
            uint16_t expected = (uint16_t)floor(sqrt((double)(dx * dx + dy * dy) * 65536.0));
            assert(fixed.distances_q8[slot][led] == expected);
            if (expected > farthest) farthest = expected;
        }
        assert(fixed.pulses[slot].reach_q8_half_keys == farthest);
    }
    puts("PASS: every cached distance and reach matches direct calculation after pulse-slot reuse");
}

static void test_extended_effects_and_held_release(void) {
    uint8_t frame[GMK_FIXED_FRAME_BYTES], earlier[GMK_FIXED_FRAME_BYTES];
    gmk_fixed_renderer fixed;
    uint8_t *layer;
    unsigned effect, led;
    start_profile();
    layer = append_layer(9, 1, 255, 30, 0); /* held key, selected scan 0 only */
    memset(layer + 14, 0, 26);
    mask_set(layer + 14, 0);
    mask_set(layer + 27, 0);
    append_layer(6, 1 | 8, 0, 0, 80); /* blue background */
    finish_profile(0);
    fixed = prepare_fixed();
    assert(gmk_fixed_render(&fixed, 0, frame) == 1 && frame[2] == 80);
    gmk_fixed_key_down(&fixed, 1, 0);
    assert(gmk_fixed_render(&fixed, 5000, frame) == 1 && frame[0] == 0 && frame[2] == 80);
    gmk_fixed_key_down(&fixed, 0, 0);
    assert(gmk_fixed_render(&fixed, 5000, frame) == 1 && frame[0] == 255 && frame[3] == 0);
    gmk_fixed_key_up(&fixed, 0);
    assert(gmk_fixed_render(&fixed, 5001, frame) == 1 && frame[0] == 0 && frame[2] == 80);
    layer[1] |= 2u; /* Affect all keys with scan 0 as sole trigger. */
    memset(layer + 27, 255, 13);
    finish_profile(0);
    fixed = prepare_fixed();
    gmk_fixed_key_down(&fixed, 0, 0);
    assert(gmk_fixed_render(&fixed, 10000, frame) == 1);
    assert(frame[0] == 255 && frame[103 * 3] == 255);
    gmk_fixed_key_up(&fixed, 0);
    assert(gmk_fixed_render(&fixed, 10001, frame) == 1 && frame[0] == 0 && frame[103 * 3 + 2] == 80);
    gmk_fixed_key_down(&fixed, 0, 0);
    gmk_fixed_clear_held(&fixed); /* queue overflow must fail dark, never stick on */
    assert(gmk_fixed_render(&fixed, 10002, frame) == 1 && frame[0] == 0);
    puts("PASS: native key hold follows press/release, obeys trigger reach, and clears safely after overflow");

    for (effect = 10; effect <= 17; ++effect) {
        unsigned colored = 0;
        start_profile();
        append_layer(effect, 1 | 8, 40, 180, 255);
        finish_profile(0);
        fixed = prepare_fixed();
        assert(gmk_fixed_render(&fixed, 500, earlier) == 1);
        assert(gmk_fixed_render(&fixed, 1500, frame) == 1);
        for (led = 0; led < GMK_PROFILE_KEY_COUNT; ++led)
            colored += has_color(frame, led);
        assert(colored > 0 && memcmp(earlier, frame, sizeof frame) != 0);
    }
    puts("PASS: eight extra native animations produce changing, mapped per-key frames");
}

int main(void) {
    test_per_key_mapping_and_blend();
    test_reactive_trigger_and_far_edge_ripple();
    test_layer_speed_changes_onboard_animation();
    test_sensor_expiration_preserves_other_layers();
    test_all_effects_and_bounded_pulses();
    test_other_modes_and_invalid_inputs();
    test_fixed_path();
    test_full_sixteen_layer_vector();
    test_worst_case_ripple_stack();
    test_cached_distances_after_slot_reuse();
    test_extended_effects_and_held_release();
    printf("Renderer state: reference %zu bytes; integer-only %zu bytes\n",
           sizeof(gmk_renderer), sizeof(gmk_fixed_renderer));
    return 0;
}
