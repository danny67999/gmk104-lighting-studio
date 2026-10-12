#ifndef GMK104_ONBOARD_STORAGE_H
#define GMK104_ONBOARD_STORAGE_H

#include <stdint.h>

#include "../native_ripple/onboard_profile.h"

/* Offline reference only. The two slot numbers intentionally have no physical
 * flash addresses. Do not bind these callbacks to a keyboard until the real
 * flash map and chip capacity have been read and verified on that device. */
#define GMK_STORE_SECTOR_BYTES 4096u
#define GMK_STORE_PAGE_BYTES 256u
#define GMK_STORE_TAIL_OFFSET GMK_PROFILE_MAX_BYTES
#define GMK_STORE_TAIL_BYTES 32u

typedef struct {
    void *context;
    int (*read)(void *context, uint8_t slot, uint16_t offset,
                uint8_t *destination, uint16_t length);
    int (*erase)(void *context, uint8_t slot);
    int (*program)(void *context, uint8_t slot, uint16_t offset,
                   const uint8_t *source, uint16_t length);
} gmk_store_io;

typedef struct {
    uint8_t present;
    uint8_t slot;
    uint32_t generation;
    uint16_t profile_length;
    uint32_t profile_crc32;
} gmk_store_active;

typedef enum {
    GMK_STORE_OK = 0,
    GMK_STORE_BAD_ARGUMENT,
    GMK_STORE_BAD_PROFILE,
    GMK_STORE_IO_ERROR,
    GMK_STORE_VERIFY_ERROR,
    GMK_STORE_GENERATION_CONFLICT
} gmk_store_result;

/* scratch must have GMK_PROFILE_BUFFER_BYTES bytes. On success with present=1,
 * scratch contains the selected profile. A scan never writes flash. */
gmk_store_result gmk_store_scan(const gmk_store_io *io,
                                 uint8_t scratch[GMK_PROFILE_BUFFER_BYTES],
                                 gmk_store_active *active);

/* profile and scratch must not overlap. This validates the complete image
 * before erasing only the inactive slot. A failed/ambiguous write must be
 * resolved by a fresh read-only scan after reconnection, never auto-retried. */
gmk_store_result gmk_store_commit(const gmk_store_io *io,
                                   const uint8_t *profile,
                                   uint16_t profile_length,
                                   uint8_t scratch[GMK_PROFILE_BUFFER_BYTES],
                                   gmk_store_active *active);

#endif
