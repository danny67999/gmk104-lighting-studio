#ifndef GMK104_PROFILE_RENDERER_H
#define GMK104_PROFILE_RENDERER_H

#include "onboard_profile.h"

#include <stdint.h>

/* Portable, allocation-free reference renderer for a previously validated
 * GMKP v1 profile. This is not a firmware image or a hardware upload path.
 * The profile buffer must remain immutable and alive for the renderer's life.
 * Time arguments are monotonic milliseconds from the same 32-bit clock. */
#define GMK_RENDERER_FRAME_BYTES (GMK_PROFILE_KEY_COUNT * 3u)
#define GMK_RENDERER_MAX_PULSES 16u

typedef struct {
    uint32_t time_ms;
    /* Farthest mapped key distance, in full-key units. */
    float reach;
    uint8_t scan_index;
} gmk_renderer_pulse;

typedef struct {
    gmk_profile_view profile;
    gmk_renderer_pulse pulses[GMK_RENDERER_MAX_PULSES];
    uint32_t music_time_ms;
    uint32_t temperature_time_ms;
    uint16_t temperature_celsius_x100;
    uint8_t music[4]; /* bass, mid, treble, overall level, each 0..255 */
    uint8_t pulse_count;
    uint8_t next_pulse;
    uint8_t has_music;
    uint8_t has_temperature;
    uint8_t initialized;
} gmk_renderer;

/* Revalidates the complete profile. Returns 1 on success, 0 otherwise. */
int gmk_renderer_init(gmk_renderer *renderer, const gmk_profile_view *profile);

/* A true key-down transition, in factory scan order; repeated scan events
 * should not be sent. Pulses are bounded and the oldest are overwritten. */
void gmk_renderer_key_down(gmk_renderer *renderer, uint8_t scan_index, uint32_t time_ms);

/* The Mac supplies only scalar sensor data. Stale audio is ignored after
 * 500 ms, stale temperature after 5000 ms; neither is stored in the profile. */
void gmk_renderer_set_music(gmk_renderer *renderer, uint8_t bass, uint8_t mid,
                            uint8_t treble, uint8_t level, uint32_t time_ms);
void gmk_renderer_set_temperature(gmk_renderer *renderer,
                                  uint16_t celsius_x100, uint32_t time_ms);

/* Returns 1 and writes 312 RGB bytes for Studio/manual mode. Returns 0 for
 * built-in mode, which the caller must dispatch to the stock effect engine.
 * Returns -1 for invalid arguments or an uninitialized renderer. Global
 * brightness remains a separate keyboard setting, as in Lighting Studio. */
int gmk_renderer_render(const gmk_renderer *renderer, uint32_t time_ms,
                        uint8_t out[GMK_RENDERER_FRAME_BYTES]);

#endif
