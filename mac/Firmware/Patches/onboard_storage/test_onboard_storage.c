#include "onboard_storage.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t sector[2][GMK_STORE_SECTOR_BYTES];
    uint32_t cut_after;
    int inject_cut;
    int power_lost;
    int fail_read;
    int corrupt_first_program_byte;
    uint32_t erased[2];
} simulated_flash;

static int valid_range(uint8_t slot, uint16_t offset, uint16_t length) {
    return slot < 2 && (uint32_t)offset + length <= GMK_STORE_SECTOR_BYTES;
}

static int read_flash(void *context, uint8_t slot, uint16_t offset,
                      uint8_t *destination, uint16_t length) {
    simulated_flash *flash = context;
    if (!valid_range(slot, offset, length) || flash->power_lost ||
        flash->fail_read) return -1;
    memcpy(destination, flash->sector[slot] + offset, length);
    return 0;
}

static int consume_byte(simulated_flash *flash, uint8_t *destination,
                        uint8_t value) {
    if (flash->power_lost) return -1;
    if (flash->inject_cut && flash->cut_after == 0) {
        flash->power_lost = 1;
        return -1;
    }
    *destination = value;
    if (flash->inject_cut && --flash->cut_after == 0) {
        flash->power_lost = 1;
        return -1;
    }
    return 0;
}

static int erase_flash(void *context, uint8_t slot) {
    simulated_flash *flash = context;
    uint16_t i;
    if (slot >= 2) return -1;
    flash->erased[slot]++;
    for (i = 0; i < GMK_STORE_SECTOR_BYTES; ++i)
        if (consume_byte(flash, &flash->sector[slot][i], 0xff) != 0)
            return -1;
    return 0;
}

static int program_flash(void *context, uint8_t slot, uint16_t offset,
                         const uint8_t *source, uint16_t length) {
    simulated_flash *flash = context;
    uint16_t i;
    if (!valid_range(slot, offset, length) ||
        offset / GMK_STORE_PAGE_BYTES !=
            (uint32_t)(offset + length - 1) / GMK_STORE_PAGE_BYTES)
        return -1;
    for (i = 0; i < length; ++i) {
        uint8_t value = source[i];
        uint8_t old = flash->sector[slot][offset + i];
        if (flash->corrupt_first_program_byte && offset == 0 && i == 0) {
            value &= 0xfe;
            flash->corrupt_first_program_byte = 0;
        }
        if ((old & value) != value) return -1; /* NOR flash cannot set 0 -> 1. */
        if (consume_byte(flash, &flash->sector[slot][offset + i], value) != 0)
            return -1;
    }
    return 0;
}

static gmk_store_io io_for(simulated_flash *flash) {
    gmk_store_io io = {flash, read_flash, erase_flash, program_flash};
    return io;
}

static uint16_t load_fixture(uint8_t *buffer) {
    const char *path = "mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin";
    FILE *file = fopen(path, "rb");
    long length;
    gmk_profile_view view;
    assert(file);
    assert(fseek(file, 0, SEEK_END) == 0);
    length = ftell(file);
    assert(length > 0 && length <= GMK_PROFILE_MAX_BYTES);
    rewind(file);
    assert(fread(buffer, 1, (size_t)length, file) == (size_t)length);
    assert(fclose(file) == 0);
    assert(gmk_profile_validate(buffer, (size_t)length, &view));
    return (uint16_t)length;
}

static void edit_profile(uint8_t *profile, uint16_t length, uint8_t color) {
    uint32_t crc;
    gmk_profile_view view;
    profile[344 + 7] = color; /* First layer's red channel. */
    crc = gmk_profile_crc32(profile + 32, length - 32);
    profile[12] = (uint8_t)crc;
    profile[13] = (uint8_t)(crc >> 8);
    profile[14] = (uint8_t)(crc >> 16);
    profile[15] = (uint8_t)(crc >> 24);
    assert(gmk_profile_validate(profile, length, &view));
}

static void force_generation(simulated_flash *flash, uint8_t slot,
                             uint32_t generation) {
    uint8_t *tail = flash->sector[slot] + GMK_STORE_TAIL_OFFSET;
    uint32_t crc;
    tail[8] = (uint8_t)generation;
    tail[9] = (uint8_t)(generation >> 8);
    tail[10] = (uint8_t)(generation >> 16);
    tail[11] = (uint8_t)(generation >> 24);
    crc = gmk_profile_crc32(tail, 24);
    tail[24] = (uint8_t)crc;
    tail[25] = (uint8_t)(crc >> 8);
    tail[26] = (uint8_t)(crc >> 16);
    tail[27] = (uint8_t)(crc >> 24);
}

static void check_scan(simulated_flash *flash, const uint8_t *expected,
                       uint16_t length, uint8_t slot, uint32_t generation) {
    uint8_t scratch[GMK_PROFILE_MAX_BYTES];
    gmk_store_active active;
    gmk_store_io io = io_for(flash);
    assert(gmk_store_scan(&io, scratch, &active) == GMK_STORE_OK);
    assert(active.present && active.slot == slot &&
           active.generation == generation && active.profile_length == length);
    assert(memcmp(scratch, expected, length) == 0);
}

int main(void) {
    uint8_t first[GMK_PROFILE_MAX_BYTES], second[GMK_PROFILE_MAX_BYTES];
    uint8_t scratch[GMK_PROFILE_MAX_BYTES];
    simulated_flash *flash = malloc(sizeof(*flash));
    simulated_flash *baseline = malloc(sizeof(*baseline));
    gmk_store_active active;
    gmk_store_io io;
    uint16_t length;
    uint32_t cut;
    assert(flash && baseline);
    memset(flash, 0xff, sizeof(*flash));
    flash->inject_cut = flash->power_lost = flash->fail_read = 0;
    flash->corrupt_first_program_byte = 0;
    flash->erased[0] = flash->erased[1] = 0;
    length = load_fixture(first);
    memcpy(second, first, length);
    edit_profile(second, length, 0x42);
    io = io_for(flash);

    assert(gmk_store_scan(&io, scratch, &active) == GMK_STORE_OK &&
           !active.present);
    {
        gmk_store_io read_only = io;
        read_only.erase = NULL;
        read_only.program = NULL;
        assert(gmk_store_scan(&read_only, scratch, &active) == GMK_STORE_OK &&
               !active.present);
    }
    assert(gmk_store_commit(&io, first, length, scratch, &active) == GMK_STORE_OK);
    check_scan(flash, first, length, 0, 1);
    assert(gmk_store_commit(&io, second, length, scratch, &active) == GMK_STORE_OK);
    check_scan(flash, second, length, 1, 2);
    assert(flash->erased[0] == 1 && flash->erased[1] == 1);

    /* Reject malformed input before any erase; a read failure also prevents
     * an erase because the active generation cannot be proved. */
    memcpy(baseline, flash, sizeof(*baseline));
    first[0] ^= 1;
    assert(gmk_store_commit(&io, first, length, scratch, &active) ==
           GMK_STORE_BAD_PROFILE);
    assert(memcmp(flash->sector, baseline->sector, sizeof(flash->sector)) == 0);
    first[0] ^= 1;
    flash->fail_read = 1;
    assert(gmk_store_commit(&io, first, length, scratch, &active) ==
           GMK_STORE_IO_ERROR);
    flash->fail_read = 0;
    assert(memcmp(flash->sector, baseline->sector, sizeof(flash->sector)) == 0);

    /* A silent write error must fail precommit readback and preserve slot 1. */
    flash->corrupt_first_program_byte = 1;
    assert(gmk_store_commit(&io, first, length, scratch, &active) ==
           GMK_STORE_VERIFY_ERROR);
    check_scan(flash, second, length, 1, 2);

    /* Restore both valid generations. Simulate a power cut after EVERY byte
     * of erase, profile program, metadata program and final commit marker. */
    for (cut = 0; cut <= GMK_STORE_SECTOR_BYTES + length + 28 + 4; ++cut) {
        gmk_store_result result;
        memcpy(flash, baseline, sizeof(*flash));
        flash->inject_cut = 1;
        flash->cut_after = cut;
        io = io_for(flash);
        result = gmk_store_commit(&io, first, length, scratch, &active);
        assert(result == GMK_STORE_IO_ERROR || result == GMK_STORE_OK);
        flash->inject_cut = flash->power_lost = 0; /* Restore power. */
        io = io_for(flash);
        assert(gmk_store_scan(&io, scratch, &active) == GMK_STORE_OK);
        assert(active.present && active.profile_length == length);
        if (active.slot == 0) {
            assert(active.generation == 3);
            assert(memcmp(scratch, first, length) == 0);
        } else {
            assert(active.slot == 1 && active.generation == 2);
            assert(memcmp(scratch, second, length) == 0);
        }
    }

    /* If the newest data later corrupts, the older valid generation loads. */
    memcpy(flash, baseline, sizeof(*flash));
    flash->sector[1][0] &= 0xfe;
    check_scan(flash, first, length, 0, 1);

    /* Conflicting committed generations are not permission to erase either. */
    memcpy(flash, baseline, sizeof(*flash));
    force_generation(flash, 1, 1);
    io = io_for(flash);
    assert(gmk_store_scan(&io, scratch, &active) ==
           GMK_STORE_GENERATION_CONFLICT);
    assert(gmk_store_commit(&io, first, length, scratch, &active) ==
           GMK_STORE_GENERATION_CONFLICT);
    assert(flash->erased[0] == baseline->erased[0] &&
           flash->erased[1] == baseline->erased[1]);

    /* Generation arithmetic must permit the UINT32_MAX -> 0 transition. */
    memcpy(flash, baseline, sizeof(*flash));
    force_generation(flash, 0, UINT32_MAX);
    flash->sector[1][GMK_STORE_TAIL_OFFSET + 28] = 0xff;
    check_scan(flash, first, length, 0, UINT32_MAX);
    io = io_for(flash);
    assert(gmk_store_commit(&io, second, length, scratch, &active) == GMK_STORE_OK);
    check_scan(flash, second, length, 1, 0);

    free(baseline);
    free(flash);
    printf("PASS: two-slot journal, readback, rollback and %u power-cut points\n",
           (unsigned)(GMK_STORE_SECTOR_BYTES + length + 28 + 4 + 1));
    return 0;
}
