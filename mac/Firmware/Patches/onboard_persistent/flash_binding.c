#include "flash_binding.h"
#include <string.h>

_Static_assert(GMK_PROFILE_BUFFER_BYTES < GMK_FLASH_OWNER_OFFSET,
               "Profile overlaps sector reservation record");
static const uint8_t owner[GMK_FLASH_OWNER_BYTES] = {
    'G','M','K','1','0','4','-','P','R','O','F','I','L','E','-','1',
    0x00,0xc0,0x08,0x00,0x00,0xd0,0x08,0x00,
    0x85,0x60,0x14,0x00,0x47,0x4d,0x4b,0x4f
};
static uint32_t address(uint8_t slot) {
    return slot == 0 ? GMK_FLASH_SLOT0 : GMK_FLASH_SLOT1;
}
static int allowed(gmk_flash_binding *binding) {
    if (!binding || !binding->ready ||
        !binding->driver.layout_valid(binding->driver.context)) {
        if (binding) binding->ready = 0;
        return 0;
    }
    return 1;
}
/* A marker can be interrupted bit-by-bit, not just at byte boundaries. NOR
 * programming clears bits only: every completed bit must match the marker.
 * An incomplete marker is accepted only with the rest of the sector blank. */
static int sector_ours(gmk_flash_binding *binding, uint8_t slot) {
    uint8_t bytes[32];
    unsigned offset, i;
    int blank_elsewhere = 1, complete = 1, compatible = 1;
    for (offset = 0; offset < GMK_STORE_SECTOR_BYTES; offset += sizeof(bytes)) {
        if (binding->driver.read(binding->driver.context, address(slot) + offset,
                                  bytes, sizeof(bytes)) != 0) return 0;
        for (i = 0; i < sizeof(bytes); ++i) {
            if (offset == GMK_FLASH_OWNER_OFFSET) {
                if (bytes[i] != owner[i]) complete = 0;
                if ((bytes[i] & owner[i]) != owner[i]) compatible = 0;
            } else if (bytes[i] != 0xffu) blank_elsewhere = 0;
        }
    }
    return complete || (blank_elsewhere && compatible);
}
static int read_slot(void *context, uint8_t slot, uint16_t offset,
                      uint8_t *bytes, uint16_t count) {
    gmk_flash_binding *binding = context;
    if (slot > 1 || !bytes || !count ||
        (uint32_t)offset + count > GMK_STORE_SECTOR_BYTES || !allowed(binding)) return -1;
    if (!(binding->readable_mask & (1u << slot))) {
        /* Ignore a foreign/partially erased inactive slot without preventing
         * read-only restore from the other intact, owned generation. */
        memset(bytes, 0xff, count);
        return 0;
    }
    return binding->driver.read(binding->driver.context, address(slot) + offset, bytes, count);
}
static int program_slot(void *context, uint8_t slot, uint16_t offset,
                         const uint8_t *bytes, uint16_t count) {
    gmk_flash_binding *binding = context;
    if (binding->readable_mask != 3u) return -1;
    if (slot > 1 || !bytes || !count || count > GMK_STORE_PAGE_BYTES ||
        (uint32_t)offset + count > GMK_STORE_SECTOR_BYTES ||
        offset / GMK_STORE_PAGE_BYTES != (offset + count - 1u) / GMK_STORE_PAGE_BYTES ||
        ((uint32_t)offset < GMK_FLASH_OWNER_OFFSET + GMK_FLASH_OWNER_BYTES &&
         (uint32_t)offset + count > GMK_FLASH_OWNER_OFFSET) || !allowed(binding)) return -1;
    return binding->driver.program(binding->driver.context, address(slot) + offset, bytes, count);
}
static int erase_slot(void *context, uint8_t slot) {
    gmk_flash_binding *binding = context;
    uint8_t bytes[32];
    unsigned offset, i;
    if (binding->readable_mask != 3u || slot > 1 || !allowed(binding) ||
        !sector_ours(binding, slot)) return -1;
    if (binding->driver.erase(binding->driver.context, address(slot)) != 0) return -1;
    /* Verify the entire erase before marking ownership or accepting payload. */
    for (offset = 0; offset < GMK_STORE_SECTOR_BYTES; offset += sizeof(bytes)) {
        if (binding->driver.read(binding->driver.context, address(slot) + offset,
                                  bytes, sizeof(bytes)) != 0) return -1;
        for (i = 0; i < sizeof(bytes); ++i) if (bytes[i] != 0xffu) return -1;
    }
    if (!allowed(binding) || binding->driver.program(binding->driver.context,
          address(slot) + GMK_FLASH_OWNER_OFFSET, owner, sizeof(owner)) != 0) return -1;
    if (binding->driver.read(binding->driver.context, address(slot) + GMK_FLASH_OWNER_OFFSET,
                              bytes, sizeof(bytes)) != 0 || memcmp(bytes, owner, sizeof(owner))) return -1;
    return 0;
}
int gmk_flash_prepare(gmk_flash_binding *binding, const gmk_flash_driver *driver,
                      gmk_store_io *io) {
    if (!binding || !driver || !io) return 0;
    memset(binding, 0, sizeof(*binding));
    memset(io, 0, sizeof(*io));
    binding->driver = *driver;
    if (!driver->layout_valid || !driver->read || !driver->erase || !driver->program ||
        !driver->layout_valid(driver->context)) return 0;
    binding->readable_mask = (uint8_t)((sector_ours(binding, 0) ? 1u : 0u) |
                                      (sector_ours(binding, 1) ? 2u : 0u));
    binding->ready = 1;
    io->context = binding;
    io->read = read_slot;
    if (binding->readable_mask == 3u) {
        io->erase = erase_slot; io->program = program_slot;
    }
    return 1;
}
