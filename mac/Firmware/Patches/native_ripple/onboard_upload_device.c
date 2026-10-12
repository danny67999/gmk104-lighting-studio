#include "onboard_upload_device.h"

#include <string.h>

#define SUCCESS 0u
#define INVALID 1u
#define SESSION 2u
#define BOUNDS 3u
#define PROFILE 4u
#define SAVE_FAILED 5u
#define BUSY 6u

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
    unsigned i;
    for (i = 0; i < 4; ++i) p[i] = (uint8_t)(value >> (8u * i));
}
static int zero_tail(const uint8_t *p, unsigned start) {
    unsigned i;
    for (i = start; i < 32; ++i) if (p[i] != 0) return 0;
    return 1;
}
static void header(uint8_t *reply, uint8_t kind, uint8_t operation, uint8_t status) {
    memset(reply, 0, 32);
    reply[0] = kind; reply[1] = 3; reply[2] = 7; reply[3] = operation;
    memcpy(reply + 4, "GMKU", 4);
    reply[8] = 1; reply[9] = status;
}
static void acknowledgment(uint8_t *reply, uint8_t operation, uint8_t status,
                           uint32_t session, uint16_t offset, uint32_t crc) {
    header(reply, 7, operation, status);
    put32(reply + 10, session);
    put16(reply + 14, offset);
    put32(reply + 16, crc);
}

void gmk_upload_init(gmk_upload_device *device, const uint8_t *saved,
                     uint16_t saved_length, gmk_profile_commit commit, void *user) {
    gmk_profile_view view;
    if (!device) return;
    memset(device, 0, sizeof *device);
    device->active = device->buffers[0];
    device->pending = device->buffers[1];
    device->commit = commit; device->user = user;
    if (saved && gmk_profile_validate(saved, saved_length, &view)) {
        memcpy(device->active, saved, saved_length);
        device->active_length = saved_length;
        device->active_crc = gmk_profile_crc32(saved, saved_length);
    }
}

void gmk_upload_finish_activation(gmk_upload_device *device) {
    if (device) __atomic_store_n(&device->activation_pending, 0u, __ATOMIC_RELEASE);
}

int gmk_upload_handle(gmk_upload_device *device, const uint8_t request[32],
                      uint8_t response[32], int wired) {
    uint8_t kind, operation;
    uint32_t session;
    uint16_t offset;
    if (!device || !request || !response) return 0;
    if (request[1] != 3 || request[2] != 7) return 0;
    kind = request[0]; operation = request[3];
    if (kind == 8 && operation == 0) {
        header(response, 8, 0, 0);
        if (!zero_tail(request, 4)) { response[9] = INVALID; return 1; }
        response[9] = wired ? (uint8_t)(device->commit ? 7 : 5) : 0;
        put16(response + 10, GMK_PROFILE_BUFFER_BYTES);
        response[12] = 21;
        response[13] = (uint8_t)__atomic_load_n(&device->activation_pending, __ATOMIC_ACQUIRE);
        put16(response + 14, device->active_length);
        put32(response + 16, device->active_crc);
        return 1;
    }
    if (!wired) {
        header(response, kind, operation, INVALID);
        return 1;
    }
    if (kind == 7 && operation == 1) {
        uint16_t length = get16(request + 8);
        session = get32(request + 4);
        if (__atomic_load_n(&device->activation_pending, __ATOMIC_ACQUIRE)) {
            acknowledgment(response, 1, BUSY, session, 0, 0);
            return 1;
        }
        if (!zero_tail(request, 14) || session == 0 || length < 344 ||
            length > GMK_PROFILE_BUFFER_BYTES) {
            acknowledgment(response, 1, BOUNDS, session, 0, 0);
            return 1;
        }
        device->session = session;
        device->pending_length = length;
        device->expected_crc = get32(request + 10);
        device->received = 0;
        device->state = 1;
        acknowledgment(response, 1, SUCCESS, session, 0, 0);
        return 1;
    }
    if (kind == 7 && operation == 2) {
        uint8_t count = request[10];
        session = get32(request + 4); offset = get16(request + 8);
        if (device->state != 1 || session != device->session) {
            acknowledgment(response, 2, SESSION, session, device->received, 0);
            return 1;
        }
        if (count == 0 || count > 21 || !zero_tail(request, 11u + count) ||
            offset != device->received || (uint32_t)offset + count > device->pending_length) {
            acknowledgment(response, 2, BOUNDS, session, device->received, 0);
            return 1;
        }
        memcpy(device->pending + offset, request + 11, count);
        device->received = (uint16_t)(offset + count);
        acknowledgment(response, 2, SUCCESS, session, device->received, 0);
        return 1;
    }
    if (kind == 7 && operation == 3) {
        gmk_profile_view view;
        session = get32(request + 4);
        if (!zero_tail(request, 8) || device->state != 1 || session != device->session) {
            acknowledgment(response, 3, SESSION, session, device->received, 0);
            return 1;
        }
        if (device->received != device->pending_length ||
            gmk_profile_crc32(device->pending, device->received) != device->expected_crc ||
            !gmk_profile_validate(device->pending, device->received, &view)) {
            acknowledgment(response, 3, PROFILE, session, device->received, 0);
            return 1;
        }
        device->state = 2;
        acknowledgment(response, 3, SUCCESS, session, device->received, device->expected_crc);
        return 1;
    }
    if (kind == 7 && operation == 4) {
        session = get32(request + 4);
        if (!zero_tail(request, 8) || device->state != 2 || session != device->session) {
            acknowledgment(response, 4, SESSION, session, device->received, 0);
            return 1;
        }
        /* A commit attempt is one-shot. Even a callback failure might mean
         * flash reached the final marker before readback failed. A second
         * command must not silently attempt another erase/write cycle. */
        device->state = 0;
        if (!device->commit || !device->commit(device->pending, device->pending_length, device->user)) {
            acknowledgment(response, 4, SAVE_FAILED, session, device->received, 0);
            return 1;
        }
        {
            uint8_t *old_active = device->active;
            device->active = device->pending;
            device->pending = old_active;
        }
        device->active_length = device->pending_length;
        device->active_crc = device->expected_crc;
        __atomic_store_n(&device->activation_pending, 1u, __ATOMIC_RELEASE);
        acknowledgment(response, 4, SUCCESS, session, device->active_length, device->active_crc);
        return 1;
    }
    if (kind == 7 && operation == 7) {
        session = get32(request + 4);
        if (!zero_tail(request, 8) || device->state != 2 || session != device->session) {
            acknowledgment(response, 7, SESSION, session, device->received, 0);
            return 1;
        }
        {
            uint8_t *old_active = device->active;
            device->active = device->pending;
            device->pending = old_active;
        }
        device->active_length = device->pending_length;
        device->active_crc = device->expected_crc;
        device->state = 0;
        __atomic_store_n(&device->activation_pending, 1u, __ATOMIC_RELEASE);
        acknowledgment(response, 7, SUCCESS, session, device->active_length, device->active_crc);
        return 1;
    }
    if (kind == 8 && operation == 5) {
        uint8_t count = request[6];
        offset = get16(request + 4);
        header(response, 8, 5, SUCCESS);
        put16(response + 10, offset);
        response[12] = count;
        if (!zero_tail(request, 7) || count == 0 || count > 19 ||
            (uint32_t)offset + count > device->active_length) {
            response[9] = BOUNDS; response[12] = 0;
            return 1;
        }
        memcpy(response + 13, device->active + offset, count);
        return 1;
    }
    if (kind == 7 && (operation == 8 || operation == 9)) {
        uint8_t required_flag = operation == 8 ? 1u : 2u;
        unsigned tail_start = operation == 8 ? 8u : 6u;
        int valid = zero_tail(request, tail_start) && device->active_length >= 344u &&
                    (device->active[20] & required_flag) != 0;
        if (operation == 9) {
            uint16_t temperature = get16(request + 4);
            valid = valid && temperature >= 100u && temperature <= 12500u;
        }
        acknowledgment(response, operation, valid ? SUCCESS : INVALID, 0,
                       device->active_length, device->active_crc);
        return 1;
    }
    header(response, kind, operation, INVALID);
    return 1;
}
