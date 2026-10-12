#include "onboard_storage.h"

#include <string.h>

/* The tail is programmed after the profile. Its last four bytes are the
 * commit marker and are programmed only after full profile and metadata
 * readback. Unwritten flash is expected to be 0xff. */
static const uint8_t commit_marker[4] = {'C', 'M', 'I', 'T'};

static uint16_t read16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | (uint16_t)p[1] << 8);
}

static uint32_t read32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static void write16(uint8_t *p, uint16_t value) {
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
}

static void write32(uint8_t *p, uint32_t value) {
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

static int has_read(const gmk_store_io *io) {
    return io && io->read;
}

static int has_write(const gmk_store_io *io) {
    return has_read(io) && io->erase && io->program;
}

/* A malformed slot is ignored, but an I/O error fails the entire scan.
 * Suppressing read errors here could erase the only good copy. */
static gmk_store_result read_slot(const gmk_store_io *io, uint8_t slot,
                                  uint8_t *scratch, gmk_store_active *out) {
    uint8_t tail[GMK_STORE_TAIL_BYTES];
    uint16_t length;
    gmk_profile_view view;
    memset(out, 0, sizeof(*out));
    if (io->read(io->context, slot, GMK_STORE_TAIL_OFFSET,
                 tail, sizeof(tail)) != 0) return GMK_STORE_IO_ERROR;
    if (memcmp(tail + 28, commit_marker, sizeof(commit_marker)) != 0 ||
        memcmp(tail, "GMKS", 4) != 0 || tail[4] != 1 || tail[5] != slot ||
        tail[6] != 0 || tail[7] != 0 || tail[14] != 0 || tail[15] != 0 ||
        gmk_profile_crc32(tail, 24) != read32(tail + 24)) return GMK_STORE_OK;
    length = read16(tail + 12);
    if (length < 344 || length > GMK_PROFILE_BUFFER_BYTES) return GMK_STORE_OK;
    if (io->read(io->context, slot, 0, scratch, length) != 0)
        return GMK_STORE_IO_ERROR;
    if (gmk_profile_crc32(scratch, length) != read32(tail + 16) ||
        read32(scratch + 12) != read32(tail + 20) ||
        !gmk_profile_validate(scratch, length, &view)) return GMK_STORE_OK;
    out->present = 1;
    out->slot = slot;
    out->generation = read32(tail + 8);
    out->profile_length = length;
    out->profile_crc32 = read32(tail + 16);
    return GMK_STORE_OK;
}

static gmk_store_result select_slots(const gmk_store_active *first,
                                      const gmk_store_active *second,
                                      gmk_store_active *active) {
    uint32_t difference;
    if (!first->present && !second->present) {
        memset(active, 0, sizeof(*active));
        return GMK_STORE_OK;
    }
    if (!first->present || !second->present) {
        *active = first->present ? *first : *second;
        return GMK_STORE_OK;
    }
    difference = second->generation - first->generation;
    /* Modular comparison handles UINT32_MAX -> 0. Equal or exactly halfway
     * generations are ambiguous; fail closed instead of erasing either slot. */
    if (difference == 0 || difference == UINT32_C(0x80000000))
        return GMK_STORE_GENERATION_CONFLICT;
    *active = difference < UINT32_C(0x80000000) ? *second : *first;
    return GMK_STORE_OK;
}

gmk_store_result gmk_store_scan(const gmk_store_io *io,
                                 uint8_t scratch[GMK_PROFILE_BUFFER_BYTES],
                                 gmk_store_active *active) {
    gmk_store_active first, second;
    gmk_store_result result;
    gmk_profile_view view;
    if (!has_read(io) || !scratch || !active) return GMK_STORE_BAD_ARGUMENT;
    memset(active, 0, sizeof(*active));
    result = read_slot(io, 0, scratch, &first);
    if (result != GMK_STORE_OK) return result;
    result = read_slot(io, 1, scratch, &second);
    if (result != GMK_STORE_OK) return result;
    result = select_slots(&first, &second, active);
    if (result != GMK_STORE_OK || !active->present) return result;
    /* read_slot for the other slot may have overwritten scratch. */
    if (io->read(io->context, active->slot, 0, scratch,
                 active->profile_length) != 0) return GMK_STORE_IO_ERROR;
    if (gmk_profile_crc32(scratch, active->profile_length) !=
            active->profile_crc32 ||
        !gmk_profile_validate(scratch, active->profile_length, &view))
        return GMK_STORE_VERIFY_ERROR;
    return GMK_STORE_OK;
}

static void make_tail(uint8_t *tail, uint8_t slot, uint32_t generation,
                      const uint8_t *profile, uint16_t length) {
    memset(tail, 0, GMK_STORE_TAIL_BYTES);
    memcpy(tail, "GMKS", 4);
    tail[4] = 1;
    tail[5] = slot;
    write32(tail + 8, generation);
    write16(tail + 12, length);
    write32(tail + 16, gmk_profile_crc32(profile, length));
    write32(tail + 20, read32(profile + 12));
    write32(tail + 24, gmk_profile_crc32(tail, 24));
    memcpy(tail + 28, commit_marker, sizeof(commit_marker));
}

gmk_store_result gmk_store_commit(const gmk_store_io *io,
                                   const uint8_t *profile,
                                   uint16_t profile_length,
                                   uint8_t scratch[GMK_PROFILE_BUFFER_BYTES],
                                   gmk_store_active *active) {
    gmk_store_active old, verified;
    uint8_t tail[GMK_STORE_TAIL_BYTES], check[GMK_STORE_TAIL_BYTES];
    uint8_t target;
    uint16_t offset;
    uint32_t generation;
    gmk_profile_view view;
    gmk_store_result result;
    if (!has_write(io) || !profile || !scratch || !active || profile == scratch)
        return GMK_STORE_BAD_ARGUMENT;
    if (!gmk_profile_validate(profile, profile_length, &view))
        return GMK_STORE_BAD_PROFILE;
    result = gmk_store_scan(io, scratch, &old);
    if (result != GMK_STORE_OK) return result;
    target = old.present ? (uint8_t)(old.slot ^ 1u) : 0;
    generation = old.present ? old.generation + 1u : 1u;
    make_tail(tail, target, generation, profile, profile_length);
    if (io->erase(io->context, target) != 0) return GMK_STORE_IO_ERROR;
    for (offset = 0; offset < profile_length;) {
        uint16_t in_page = (uint16_t)(GMK_STORE_PAGE_BYTES -
                                       offset % GMK_STORE_PAGE_BYTES);
        uint16_t remaining = (uint16_t)(profile_length - offset);
        uint16_t chunk = in_page < remaining ? in_page : remaining;
        if (io->program(io->context, target, offset, profile + offset,
                        chunk) != 0) return GMK_STORE_IO_ERROR;
        offset = (uint16_t)(offset + chunk);
    }
    if (io->read(io->context, target, 0, scratch, profile_length) != 0)
        return GMK_STORE_IO_ERROR;
    if (memcmp(profile, scratch, profile_length) != 0 ||
        !gmk_profile_validate(scratch, profile_length, &view))
        return GMK_STORE_VERIFY_ERROR;
    if (io->program(io->context, target, GMK_STORE_TAIL_OFFSET,
                    tail, 28) != 0) return GMK_STORE_IO_ERROR;
    if (io->read(io->context, target, GMK_STORE_TAIL_OFFSET,
                 check, 28) != 0) return GMK_STORE_IO_ERROR;
    if (memcmp(tail, check, 28) != 0) return GMK_STORE_VERIFY_ERROR;
    if (io->program(io->context, target, GMK_STORE_TAIL_OFFSET + 28,
                    tail + 28, 4) != 0) return GMK_STORE_IO_ERROR;
    result = gmk_store_scan(io, scratch, &verified);
    if (result != GMK_STORE_OK) return result;
    if (!verified.present || verified.slot != target ||
        verified.generation != generation ||
        verified.profile_length != profile_length ||
        verified.profile_crc32 != read32(tail + 16) ||
        memcmp(scratch, profile, profile_length) != 0)
        return GMK_STORE_VERIFY_ERROR;
    *active = verified;
    return GMK_STORE_OK;
}
