#include "stored_runtime.h"

#include <string.h>

static int commit_profile(const uint8_t *profile, uint16_t length, void *user) {
    gmk_stored_runtime *device = user;
    if (!device || !device->storage_ready) return 0;
    device->storage_result = gmk_store_commit(&device->storage, profile, length,
                                              device->scratch, &device->saved);
    if (device->storage_result == GMK_STORE_OK) return 1;
    /* Failure can follow a committed marker with a lost readback. Disable
     * further permanent writes for this boot instead of erasing again. */
    device->storage_ready = 0;
    device->playback.upload.commit = 0;
    return 0;
}

int gmk_stored_runtime_init(gmk_stored_runtime *device, const gmk_store_io *verified_io) {
    gmk_store_io io;
    if (!device) return 0;
    memset(&io, 0, sizeof(io));
    if (verified_io) io = *verified_io;
    memset(device, 0, sizeof(*device));
    device->storage = io;
    device->storage_result = GMK_STORE_BAD_ARGUMENT;
    if (io.read) {
        device->storage_result = gmk_store_scan(&device->storage, device->scratch,
                                                &device->saved);
        device->storage_ready = device->storage_result == GMK_STORE_OK &&
                                 io.erase != 0 && io.program != 0;
    }
    return gmk_runtime_init(&device->playback,
                            device->storage_result == GMK_STORE_OK && device->saved.present
                                ? device->scratch : 0,
                            device->storage_result == GMK_STORE_OK && device->saved.present
                                ? device->saved.profile_length : 0,
                            device->storage_ready ? commit_profile : 0, device);
}
