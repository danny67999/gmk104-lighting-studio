#ifndef GMK104_STORED_RUNTIME_H
#define GMK104_STORED_RUNTIME_H

#include "runtime.h"
#include "../onboard_storage/onboard_storage.h"

/* One static allocation; no heap or 4 KB stack buffer. The caller must supply
 * flash callbacks for a separately verified physical allocation. This module
 * neither chooses flash addresses nor establishes their ownership. */
typedef struct {
    gmk_runtime playback;
    uint8_t scratch[GMK_PROFILE_BUFFER_BYTES];
    gmk_store_io storage;
    gmk_store_active saved;
    gmk_store_result storage_result;
    uint8_t storage_ready;
} gmk_stored_runtime;

/* Read-only boot restore. Returns 1 when a saved custom profile can start.
 * Empty verified storage permits a first save. A read/generation error disables
 * persistent capability for this boot, while allowing volatile playback. */
int gmk_stored_runtime_init(gmk_stored_runtime *device, const gmk_store_io *verified_io);

#endif
