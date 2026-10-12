#ifndef GMK104_ONBOARD_RUNTIME_H
#define GMK104_ONBOARD_RUNTIME_H

#include "../native_ripple/onboard_upload_device.h"
#include "../native_ripple/renderer_fixed.h"

#define GMK_RUNTIME_EVENT_COUNT 32u
#define GMK_RUNTIME_MAX_EFFECT_ID GMK_PROFILE_MAX_EFFECT_ID

/* Hardware-independent integration core for the complete firmware. The flash
 * binding must supply a fully verified saved record and a one-shot commit
 * callback. This module contains no flash addresses or device I/O. */
typedef struct {
    gmk_upload_device upload;
    gmk_fixed_renderer renderer;
#ifdef GMK_COOPERATIVE_RENDER
    gmk_fixed_job frame_job;
#endif
    uint32_t tick_ms;
    uint32_t frame_phase;
    volatile uint8_t active;
    volatile uint8_t events[GMK_RUNTIME_EVENT_COUNT];
    volatile uint8_t event_write;
    volatile uint8_t event_read;
    volatile uint8_t event_overflow;
    volatile uint32_t music_sample;
    volatile uint32_t music_serial;
    uint32_t applied_music_serial;
    volatile uint32_t temperature_sample;
    volatile uint32_t temperature_serial;
    uint32_t applied_temperature_serial;
} gmk_runtime;

/* Returns 1 when a validated saved Studio/manual profile is ready to play.
 * The hardware boot hook can use this result to select the custom effect.
 * saved must not point inside runtime, which is cleared before initialization. */
int gmk_runtime_init(gmk_runtime *runtime, const uint8_t *saved,
                     uint16_t saved_length, gmk_profile_commit commit, void *user);
void gmk_runtime_select(gmk_runtime *runtime);
int gmk_runtime_dispatch(gmk_runtime *runtime, const uint8_t request[32],
                         uint8_t response[32], int wired);
void gmk_runtime_key_change(gmk_runtime *runtime, uint32_t factory_scan_index,
                            uint32_t down);
/* Returns 1 if a frame was rendered, 0 for a skipped frame/inactive profile.
 * elapsed_ms comes from the hardware scheduler, rather than host time. */
int gmk_runtime_step(gmk_runtime *runtime, uint8_t frame[GMK_FIXED_FRAME_BYTES],
                     uint32_t elapsed_ms);

#endif
