#ifndef GMK104_ONBOARD_UPLOAD_DEVICE_H
#define GMK104_ONBOARD_UPLOAD_DEVICE_H

#include "onboard_profile.h"

#include <stdint.h>

/* The owner of this context allocates it statically, not on the MCU stack.
 * The callback must persist and read back the entire profile before returning
 * success. A NULL callback allows offline RAM-stage tests but advertises no
 * persistent-save capability. There are no flash addresses in this module. */
typedef int (*gmk_profile_commit)(const uint8_t *profile, uint16_t length, void *user);

typedef struct {
    /* The old active bytes stay immutable until the render task consumes an
     * activation. The inactive buffer is reused only afterward. */
    uint8_t buffers[2][GMK_PROFILE_BUFFER_BYTES];
    uint8_t *active;
    uint8_t *pending;
    uint16_t active_length;
    uint16_t pending_length;
    uint16_t received;
    uint32_t active_crc;
    uint32_t expected_crc;
    uint32_t session;
    uint8_t state; /* 0 idle, 1 receiving, 2 validated */
    /* Aligned word published with release/acquire operations between the
     * HID callback and effect task on the single-core keyboard. */
    uint32_t activation_pending;
    gmk_profile_commit commit;
    void *user;
} gmk_upload_device;

void gmk_upload_init(gmk_upload_device *device, const uint8_t *saved,
                     uint16_t saved_length, gmk_profile_commit commit, void *user);

/* Call from the render task after it has replaced every pointer to the old
 * profile. Until then, Begin is rejected and the old buffer is immutable. */
void gmk_upload_finish_activation(gmk_upload_device *device);

/* Returns 1 if channel 3/value 7 was handled, 0 for another channel.
 * Both request and response are full 32-byte HID reports. wired must be true
 * for Begin/Chunk/Validate/Commit/Read and bounded scalar music/temperature
 * samples (set operations 8/9); Query may inspect capability safely. The
 * firmware adapter applies a sample only after this handler acknowledges it. */
int gmk_upload_handle(gmk_upload_device *device, const uint8_t request[32],
                      uint8_t response[32], int wired);

#endif
