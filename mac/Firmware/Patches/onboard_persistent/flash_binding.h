#ifndef GMK104_FLASH_BINDING_H
#define GMK104_FLASH_BINDING_H
#include "../onboard_storage/onboard_storage.h"

/* This allocation is restricted to the surveyed 1 MB target and the pinned
 * vendor layout. Callbacks refuse unknown sector contents or moved stock
 * OTA/BLE storage. No erase/program occurs while preparing or restoring. */
#define GMK_FLASH_OWNER_OFFSET 3968u
#define GMK_FLASH_OWNER_BYTES 32u
#define GMK_FLASH_SLOT0 UINT32_C(0x8C000)
#define GMK_FLASH_SLOT1 UINT32_C(0x8D000)

typedef struct {
    void *context;
    int (*layout_valid)(void *context);
    int (*read)(void *context, uint32_t address, uint8_t *bytes, uint16_t count);
    int (*erase)(void *context, uint32_t address);
    int (*program)(void *context, uint32_t address, const uint8_t *bytes, uint16_t count);
} gmk_flash_driver;

typedef struct {
    gmk_flash_driver driver;
    uint8_t ready;
    uint8_t readable_mask;
} gmk_flash_binding;

/* Prepare performs only reads. Unknown data disables storage. A complete
 * ownership marker permits recovery of an interrupted journal payload. A
 * partially written ownership marker is recoverable only while every byte
 * outside it is erased. It does not turn arbitrary nonblank data into ours. */
int gmk_flash_prepare(gmk_flash_binding *binding, const gmk_flash_driver *driver,
                      gmk_store_io *io);
#endif
