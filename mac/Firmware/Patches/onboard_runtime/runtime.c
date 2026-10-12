#include "runtime.h"

#include <string.h>

static uint32_t get32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static int load_active(gmk_runtime *runtime) {
    gmk_profile_view view;
    return gmk_profile_validate(runtime->upload.active,
                                runtime->upload.active_length, &view) &&
           view.mode != 1 && gmk_fixed_init(&runtime->renderer, &view);
}

static void activate(gmk_runtime *runtime) {
    if (!__atomic_load_n(&runtime->upload.activation_pending, __ATOMIC_ACQUIRE)) return;
    runtime->active = 0;
    if (load_active(runtime)) {
#ifdef GMK_COOPERATIVE_RENDER
        runtime->frame_job.running = 0;
        runtime->event_read = runtime->event_write;
        runtime->event_overflow = 0;
#endif
        runtime->tick_ms = 0;
        runtime->frame_phase = 1000;
        runtime->applied_music_serial = runtime->music_serial;
        runtime->applied_temperature_serial = runtime->temperature_serial;
        runtime->active = 1;
    }
    /* The old upload buffer becomes writable only once every renderer
     * pointer refers to the new immutable active buffer. */
    gmk_upload_finish_activation(&runtime->upload);
}

int gmk_runtime_init(gmk_runtime *runtime, const uint8_t *saved,
                     uint16_t saved_length, gmk_profile_commit commit, void *user) {
    if (!runtime) return 0;
    memset(runtime, 0, sizeof(*runtime));
    gmk_upload_init(&runtime->upload, saved, saved_length, commit, user);
    runtime->frame_phase = 1000;
    runtime->active = (uint8_t)load_active(runtime);
    return runtime->active;
}

void gmk_runtime_select(gmk_runtime *runtime) {
    if (!runtime) return;
    activate(runtime);
    runtime->active = 0;
    runtime->tick_ms = 0;
    runtime->frame_phase = 1000;
    runtime->event_read = runtime->event_write;
    runtime->event_overflow = 0;
#ifdef GMK_COOPERATIVE_RENDER
    runtime->frame_job.running = 0;
#endif
    runtime->applied_music_serial = runtime->music_serial;
    runtime->applied_temperature_serial = runtime->temperature_serial;
    runtime->active = (uint8_t)load_active(runtime);
}

static void rejected_profile(uint8_t response[32], const uint8_t request[32],
                              uint16_t received) {
    memset(response, 0, 32);
    response[0] = 7; response[1] = 3; response[2] = 7;
    response[3] = request[3];
    memcpy(response + 4, "GMKU", 4);
    response[8] = 1; response[9] = 4;
    memcpy(response + 10, request + 4, 4);
    response[14] = (uint8_t)received;
    response[15] = (uint8_t)(received >> 8);
}

int gmk_runtime_dispatch(gmk_runtime *runtime, const uint8_t request[32],
                         uint8_t response[32], int wired) {
    gmk_profile_view view;
    int handled;
    if (!runtime || !request || !response) return 0;
    if (request[1] != 3 || request[2] != 7) return 0;
    /* A built-in-mode profile is outside the Studio/manual playback contract.
     * Reject it before either activation or a persistent commit callback. */
    if (request[0] == 7 && (request[3] == 4 || request[3] == 7) &&
        runtime->upload.state == 2 &&
        gmk_profile_validate(runtime->upload.pending,
                             runtime->upload.pending_length, &view) && view.mode == 1) {
        rejected_profile(response, request, runtime->upload.received);
        return 1;
    }
    handled = gmk_upload_handle(&runtime->upload, request, response, wired);
    if (!handled) return 0;
    if (request[0] == 8 && request[3] == 0 && response[8] == 1 &&
        (response[9] == 0 || response[9] == 5 || response[9] == 7))
        response[20] = GMK_RUNTIME_MAX_EFFECT_ID;
    if (request[0] == 7 && response[9] == 0) {
        if (request[3] == 4 || request[3] == 7) runtime->active = 1;
        else if (request[3] == 8) {
            runtime->music_sample = get32(request + 4);
            ++runtime->music_serial;
        } else if (request[3] == 9) {
            runtime->temperature_sample = (uint32_t)request[4] | (uint32_t)request[5] << 8;
            ++runtime->temperature_serial;
        }
    }
    return 1;
}

void gmk_runtime_key_change(gmk_runtime *runtime, uint32_t factory_scan_index,
                            uint32_t down) {
    uint8_t next;
    if (!runtime || !runtime->active || factory_scan_index >= GMK_PROFILE_KEY_COUNT) return;
    next = (uint8_t)((runtime->event_write + 1u) & (GMK_RUNTIME_EVENT_COUNT - 1u));
    if (next == runtime->event_read) {
        /* Losing a release must never leave a key lit forever. The effect
         * task clears all held keys before consuming the remaining events. */
        runtime->event_overflow = 1;
        return;
    }
    runtime->events[runtime->event_write] = (uint8_t)factory_scan_index | (down ? 0x80u : 0u);
    runtime->event_write = next;
}

int gmk_runtime_step(gmk_runtime *runtime, uint8_t frame[GMK_FIXED_FRAME_BYTES],
                     uint32_t elapsed_ms) {
    uint32_t serial, sample;
    unsigned rate;
    if (!runtime || !frame) return 0;
    activate(runtime);
    if (!runtime->active) return 0;
    runtime->tick_ms += elapsed_ms;
    serial = runtime->music_serial;
    if (serial != runtime->applied_music_serial) {
        sample = runtime->music_sample;
        gmk_fixed_set_music(&runtime->renderer, (uint8_t)sample, (uint8_t)(sample >> 8),
                             (uint8_t)(sample >> 16), (uint8_t)(sample >> 24), runtime->tick_ms);
        runtime->applied_music_serial = serial;
    }
    serial = runtime->temperature_serial;
    if (serial != runtime->applied_temperature_serial) {
        gmk_fixed_set_temperature(&runtime->renderer, (uint16_t)runtime->temperature_sample,
                                  runtime->tick_ms);
        runtime->applied_temperature_serial = serial;
    }
#ifdef GMK_COOPERATIVE_RENDER
    rate = runtime->renderer.profile.requested_fps;
    if (rate > 50u) rate = 50u;
    /* Never enqueue a backlog of overdue frames. Input/report processing
     * gets another stock main-loop visit after each bounded work unit. */
    if (runtime->frame_phase < 1000u) {
        uint32_t addition = rate * elapsed_ms;
        runtime->frame_phase = addition >= 1000u - runtime->frame_phase ? 1000u : runtime->frame_phase + addition;
    }
    if (runtime->event_overflow) {
        runtime->event_read = runtime->event_write; runtime->event_overflow = 0;
        gmk_fixed_clear_held(&runtime->renderer);
        runtime->renderer.pulse_count = 0; runtime->renderer.next_pulse = 0;
        runtime->renderer.distance_pending = 0; runtime->frame_job.running = 0;
    }
    if (runtime->frame_job.running) {
        int completed = gmk_fixed_job_step(&runtime->renderer, &runtime->frame_job, frame);
        if (completed < 0) runtime->active = 0;
        if (completed) runtime->frame_phase = 0;
        return completed > 0;
    }
    if (runtime->renderer.distance_pending) {
        gmk_fixed_prepare_distances(&runtime->renderer);
        return 0;
    }
    if (runtime->event_read != runtime->event_write) {
        uint8_t event = runtime->events[runtime->event_read];
        runtime->event_read = (uint8_t)((runtime->event_read + 1u) & (GMK_RUNTIME_EVENT_COUNT - 1u));
        if (event & 0x80u) gmk_fixed_begin_key_down(&runtime->renderer, event & 0x7fu, runtime->tick_ms);
        else gmk_fixed_key_up(&runtime->renderer, event & 0x7fu);
        return 0;
    }
    if (runtime->frame_phase < 1000u) return 0;
    gmk_fixed_job_start(&runtime->renderer, &runtime->frame_job, runtime->tick_ms);
    return 0;
#else
    if (runtime->event_overflow) {
        runtime->event_read = runtime->event_write;
        runtime->event_overflow = 0;
        gmk_fixed_clear_held(&runtime->renderer);
    }
    while (runtime->event_read != runtime->event_write) {
        uint8_t event = runtime->events[runtime->event_read];
        runtime->event_read = (uint8_t)((runtime->event_read + 1u) & (GMK_RUNTIME_EVENT_COUNT - 1u));
        if (event & 0x80u) gmk_fixed_key_down(&runtime->renderer, event & 0x7fu, runtime->tick_ms);
        else gmk_fixed_key_up(&runtime->renderer, event & 0x7fu);
    }
    rate = runtime->renderer.profile.requested_fps;
    if (rate > 50u) rate = 50u;
    runtime->frame_phase += rate * elapsed_ms;
    if (runtime->frame_phase < 1000u) return 0;
    runtime->frame_phase %= 1000u;
    if (gmk_fixed_render(&runtime->renderer, runtime->tick_ms, frame) != 1) {
        runtime->active = 0;
        return 0;
    }
    return 1;
#endif
}
