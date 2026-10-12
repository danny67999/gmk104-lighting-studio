#ifndef GMK104_PROFILE_RENDERER_FIXED_H
#define GMK104_PROFILE_RENDERER_FIXED_H

#include "onboard_profile.h"

#include <stdint.h>

/* Integer-only prototype intended for eventual freestanding firmware builds.
 * Its pulse envelope, angle, and breathing curve approximate the floating
 * reference in renderer.c; visual parity and target timing remain unverified. */
#define GMK_FIXED_FRAME_BYTES (GMK_PROFILE_KEY_COUNT * 3u)
#define GMK_FIXED_MAX_PULSES 16u

typedef struct {
    uint32_t time_ms;
    uint16_t reach_q8_half_keys;
    uint8_t scan_index;
} gmk_fixed_pulse;

typedef struct {
    gmk_profile_view profile;
    gmk_fixed_pulse pulses[GMK_FIXED_MAX_PULSES];
    /* One Q8 half-key distance row per pulse slot. A key-down computes it
     * once; all layers and frames reuse the exact same rounded distances. */
    uint16_t distances_q8[GMK_FIXED_MAX_PULSES][GMK_PROFILE_KEY_COUNT];
    uint32_t music_time_ms;
    uint32_t temperature_time_ms;
    uint16_t temperature_celsius_x100;
    uint8_t music[4];
    uint8_t held_scan[13];
#ifdef GMK_EXTENDED_REACTIVE
    uint8_t toggled_scan[13], toggled_output[13];
#endif
    uint8_t held_output[13];
    uint8_t pulse_count;
    uint8_t next_pulse;
    uint8_t has_music;
    uint8_t has_temperature;
    uint8_t initialized;
#ifdef GMK_MATRIX_COLUMNS
    uint8_t logical_output[GMK_PROFILE_KEY_COUNT];
#endif
#ifdef GMK_COOPERATIVE_RENDER
    uint8_t ripple_triggers[13], reactive_triggers[13];
    uint8_t bounds[4];
    uint8_t distance_pending, distance_slot, distance_led;
#endif
} gmk_fixed_renderer;

#ifdef GMK_COOPERATIVE_RENDER
/* One layer and at most two LED pixels per stock main-loop visit. The last
 * complete frame stays visible while this buffer is being composed. */
#define GMK_FIXED_PIXEL_BUDGET 2u
#define GMK_FIXED_DISTANCE_BUDGET 4u
typedef struct {
    uint16_t age_q8, reach_q8;
    uint8_t led, x, y, slot;
} gmk_fixed_active;
typedef struct {
    uint8_t frame[GMK_FIXED_FRAME_BYTES];
    gmk_fixed_active pulses[GMK_FIXED_MAX_PULSES];
    uint32_t time_ms;
    uint8_t running, layer_index, led, prepared, active_count, held_trigger;
} gmk_fixed_job;
void gmk_fixed_begin_key_down(gmk_fixed_renderer *renderer, uint8_t scan_index,
                              uint32_t time_ms);
void gmk_fixed_prepare_distances(gmk_fixed_renderer *renderer);
void gmk_fixed_job_start(const gmk_fixed_renderer *renderer, gmk_fixed_job *job,
                          uint32_t time_ms);
int gmk_fixed_job_step(const gmk_fixed_renderer *renderer, gmk_fixed_job *job,
                       uint8_t out[GMK_FIXED_FRAME_BYTES]);
#endif

int gmk_fixed_init(gmk_fixed_renderer *renderer, const gmk_profile_view *profile);
void gmk_fixed_key_down(gmk_fixed_renderer *renderer, uint8_t scan_index, uint32_t time_ms);
void gmk_fixed_key_up(gmk_fixed_renderer *renderer, uint8_t scan_index);
void gmk_fixed_clear_held(gmk_fixed_renderer *renderer);
void gmk_fixed_set_music(gmk_fixed_renderer *renderer, uint8_t bass, uint8_t mid,
                         uint8_t treble, uint8_t level, uint32_t time_ms);
void gmk_fixed_set_temperature(gmk_fixed_renderer *renderer,
                               uint16_t celsius_x100, uint32_t time_ms);
/* Same return convention as gmk_renderer_render: 1 frame, 0 built-in delegate,
 * -1 invalid. Global LED brightness is applied by the keyboard separately. */
int gmk_fixed_render(const gmk_fixed_renderer *renderer, uint32_t time_ms,
                     uint8_t out[GMK_FIXED_FRAME_BYTES]);

#endif
