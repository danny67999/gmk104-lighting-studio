#include "onboard_upload_device.h"
#include "renderer_fixed.h"

#include <stdint.h>
#include <string.h>

/* Experimental RAM-only bridge. No flash address or flash callback exists.
 * Studio/manual profiles can run until power loss; built-in profiles are
 * rejected on Activate because delegating mode 20 to another stock effect
 * has not yet been verified. The vendor gp register must remain untouched. */
static gmk_upload_device upload;
static gmk_fixed_renderer renderer;
static uint32_t tick_ms;
static uint16_t frame_phase;
static uint8_t initialized;
volatile uint8_t gmk_v07_profile_active;
static volatile uint8_t key_queue[16];
static volatile uint8_t key_write;
static volatile uint8_t key_read;
static volatile uint32_t music_sample;
static volatile uint32_t music_serial;
static uint32_t applied_music_serial;
static volatile uint32_t temperature_sample;
static volatile uint32_t temperature_serial;
static uint32_t applied_temperature_serial;

static void ensure_initialized(void) {
    if (initialized) return;
    gmk_upload_init(&upload, 0, 0, 0, 0);
    initialized = 1;
}

static int wire_is_usb(void) {
#ifdef GMK_V07_HOST_TEST
    return 1;
#else
    unsigned value;
    __asm__ volatile("lbu %0, 1039(gp)" : "=r"(value)); /* gp + 0x40f */
    return value == 2u;
#endif
}

static void unsupported_builtin_reply(uint8_t packet[32]) {
    uint8_t request[32];
    unsigned i;
    for (i = 0; i < 32; ++i) request[i] = packet[i];
    memset(packet, 0, 32);
    packet[0] = 7; packet[1] = 3; packet[2] = 7; packet[3] = 7;
    memcpy(packet + 4, "GMKU", 4);
    packet[8] = 1; packet[9] = 4; /* PROFILE error */
    for (i = 0; i < 4; ++i) packet[10 + i] = request[4 + i];
}

void gmk_v07_dispatch(uint8_t packet[32], int is_get) {
    uint8_t request[32];
    gmk_profile_view view;
    unsigned i;
    ensure_initialized();
    for (i = 0; i < 32; ++i) request[i] = packet[i];
    if ((is_get && request[0] != 8) || (!is_get && request[0] != 7)) return;
    if (request[0] == 7 && request[3] == 7 && upload.state == 2 &&
        gmk_profile_validate(upload.pending, upload.pending_length, &view) &&
        view.mode == 1) {
        unsupported_builtin_reply(packet);
        return;
    }
    if (!gmk_upload_handle(&upload, request, packet, wire_is_usb())) return;
    if (request[0] == 7 && request[3] == 7 && packet[9] == 0)
        gmk_v07_profile_active = 1; /* route the next tick to deferred init */
    if (request[0] == 7 && packet[9] == 0) {
        if (request[3] == 8) {
            music_sample = (uint32_t)request[4] | ((uint32_t)request[5] << 8) |
                           ((uint32_t)request[6] << 16) | ((uint32_t)request[7] << 24);
            ++music_serial;
        } else if (request[3] == 9) {
            temperature_sample = (uint32_t)request[4] | ((uint32_t)request[5] << 8);
            ++temperature_serial;
        }
    }
}

static void activate_in_effect_task(void) {
    gmk_profile_view view;
    if (!__atomic_load_n(&upload.activation_pending, __ATOMIC_ACQUIRE)) return;
    gmk_v07_profile_active = 0;
    if (gmk_profile_validate(upload.active, upload.active_length, &view) &&
        view.mode != 1 && gmk_fixed_init(&renderer, &view)) {
        tick_ms = 0;
        frame_phase = 1000;
        applied_music_serial = music_serial;
        applied_temperature_serial = temperature_serial;
        gmk_v07_profile_active = 1;
    }
    /* The old buffer can be reused only after the renderer has stopped
     * holding its pointer. The scan queue stays pending for the new profile. */
    gmk_upload_finish_activation(&upload);
}

void gmk_v07_init(void) {
    gmk_profile_view view;
    ensure_initialized();
    activate_in_effect_task();
    tick_ms = 0;
    frame_phase = 1000;
    key_read = key_write;
    applied_music_serial = music_serial;
    applied_temperature_serial = temperature_serial;
    gmk_v07_profile_active = 0;
    if (gmk_profile_validate(upload.active, upload.active_length, &view) &&
        view.mode != 1 && gmk_fixed_init(&renderer, &view))
        gmk_v07_profile_active = 1;
}

void gmk_v07_key_down(uint32_t factory_scan_index) {
    uint8_t next;
    if (!gmk_v07_profile_active || factory_scan_index >= GMK_PROFILE_KEY_COUNT) return;
    /* The scan callback must not compute 104 distances. Publish one byte and
     * let the effect task do the bounded work. A full queue drops the newest
     * event rather than delaying typing or overwriting an unread entry. */
    next = (uint8_t)((key_write + 1u) & 15u);
    if (next == key_read) return;
    key_queue[key_write] = (uint8_t)factory_scan_index;
    key_write = next;
}

void gmk_v07_render(uint8_t frame[GMK_FIXED_FRAME_BYTES], uint32_t elapsed_ms) {
    int result;
    unsigned rate;
    uint32_t serial, sample;
    activate_in_effect_task();
    if (!gmk_v07_profile_active) return;
    tick_ms += elapsed_ms;
    serial = music_serial;
    if (serial != applied_music_serial) {
        sample = music_sample;
        gmk_fixed_set_music(&renderer, (uint8_t)sample, (uint8_t)(sample >> 8),
                            (uint8_t)(sample >> 16), (uint8_t)(sample >> 24), tick_ms);
        applied_music_serial = serial;
    }
    serial = temperature_serial;
    if (serial != applied_temperature_serial) {
        sample = temperature_sample;
        gmk_fixed_set_temperature(&renderer, (uint16_t)sample, tick_ms);
        applied_temperature_serial = serial;
    }
    while (key_read != key_write) {
        uint8_t key = key_queue[key_read];
        key_read = (uint8_t)((key_read + 1u) & 15u);
        gmk_fixed_key_down(&renderer, key, tick_ms);
    }
    /* The stock 20 ms scheduler cannot exceed 50 frames/s. Lower requested
     * rates are approximated by an accumulator; the device must still be
     * benchmarked before a performance claim or attended installation. */
    rate = renderer.profile.requested_fps;
    if (rate > 50u) rate = 50u;
    frame_phase = (uint16_t)(frame_phase + rate * elapsed_ms);
    if (frame_phase < 1000u) return;
    frame_phase = (uint16_t)(frame_phase - 1000u);
    result = gmk_fixed_render(&renderer, tick_ms, frame);
    if (result != 1) gmk_v07_profile_active = 0;
}
