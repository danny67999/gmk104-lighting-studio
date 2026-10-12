#include "../onboard_runtime/stored_runtime.h"
#include "flash_binding.h"
#include <stdint.h>
#include <string.h>

static gmk_stored_runtime device;
static gmk_flash_binding flash;
static uint8_t initialized;
volatile uint8_t gmk_profile_active;

#ifndef GMK_PERSISTENT_HOST_TEST
static int wire_is_usb(void);
static uint32_t ram32(uint32_t address) {
    uint32_t value;
    __asm__ volatile("lw %0, 0(%1)" : "=r"(value) : "r"(address) : "memory");
    return value;
}
static int hardware_layout(void *context) {
    uint32_t chip, first, second, value;
    unsigned offset;
    (void)context;
    chip = ((uint32_t (*)(void))(uintptr_t)UINT32_C(0x2000B11C))();
    /* Exact fitted chip observed by the installed v0.8 survey. */
    if (chip != UINT32_C(0x00146085)) return 0;
    first = ram32(0xaf8); second = ram32(0xafc);
    if ((first != 0 && first != 0x40000u) ||
        (second != 0 && second != 0x40000u) || ram32(0x180) != 0xfc000u) return 0;
    /* These dynamically populated BLE journal pointers must remain in the
     * separately reserved pairing sectors, rather than our proposed slots. */
    value = ram32(0xbdc);
    if (value && value != 0xfc000u && value != 0xfd000u) return 0;
    value = ram32(0xc34);
    if (value && value != 0xfc000u && value != 0xfd000u) return 0;
    for (offset = 0x65c; offset < 0x66c; offset += 4) {
        value = ram32(offset);
        if (value && (value < 0xfc000u || value >= 0xfe000u)) return 0;
    }
    for (offset = 0x670; offset < 0x6b0; offset += 4) {
        value = ram32(offset);
        if (value && (value < 0xfc000u || value >= 0xfe000u)) return 0;
    }
    return 1;
}
static int hardware_read(void *context, uint32_t address, uint8_t *bytes, uint16_t count) {
    (void)context;
    ((int (*)(uint32_t, unsigned, uint8_t *))(uintptr_t)UINT32_C(0x2000F89C))(
        address, count, bytes);
    return 0; /* Journal validates every read rather than trusting this wrapper. */
}
static int hardware_erase(void *context, uint32_t address) {
    (void)context;
    if (!wire_is_usb()) return -1;
    ((void (*)(uint32_t))(uintptr_t)UINT32_C(0x2000B244))(address);
    return 0; /* flash_binding reads every erased byte before programming. */
}
static int hardware_program(void *context, uint32_t address, const uint8_t *bytes, uint16_t count) {
    (void)context;
    if (!wire_is_usb()) return -1;
    ((int (*)(uint32_t, unsigned, const uint8_t *))(uintptr_t)UINT32_C(0x2000F918))(
        address, count, bytes);
    return 0; /* Ownership/profile/tail/marker readbacks verify completion. */
}
static int wire_is_usb(void) {
    unsigned value;
    __asm__ volatile("lbu %0, 1039(gp)" : "=r"(value));
    return value == 2u;
}
static void profile_brightness(void) {
    uint32_t brightness;
    if (!device.playback.active) return;
    brightness = device.playback.renderer.profile.brightness;
    /* Same byte used by the pinned RGB brightness command and stock output
     * driver. The renderer already applies each layer's opacity/brightness. */
    __asm__ volatile("sb %0, -734(gp)" : : "r"(brightness) : "memory");
}
#else
extern gmk_flash_driver gmk_test_driver;
extern unsigned gmk_test_brightness;
extern int gmk_test_wired;
static int wire_is_usb(void) { return gmk_test_wired; }
static void profile_brightness(void) {
    if (device.playback.active) gmk_test_brightness = device.playback.renderer.profile.brightness;
}
#endif

static void ensure_initialized(void) {
    gmk_store_io io;
    if (initialized) return;
#ifndef GMK_PERSISTENT_HOST_TEST
    gmk_flash_driver driver = {0, hardware_layout, hardware_read, hardware_erase, hardware_program};
#else
    gmk_flash_driver driver = gmk_test_driver;
#endif
    memset(&io, 0, sizeof(io));
    gmk_flash_prepare(&flash, &driver, &io); /* Read-only allocation check. */
    gmk_stored_runtime_init(&device, &io);
    initialized = 1;
    gmk_profile_active = device.playback.active;
}
void gmk_persistent_boot(void) {
    ensure_initialized();
    profile_brightness();
}
void gmk_persistent_dispatch(uint8_t packet[32], int is_get) {
    uint8_t request[32];
    ensure_initialized();
    memcpy(request, packet, sizeof(request));
    if ((is_get && request[0] != 8) || (!is_get && request[0] != 7)) return;
    gmk_runtime_dispatch(&device.playback, request, packet, wire_is_usb());
    gmk_profile_active = device.playback.active;
}
void gmk_persistent_init(void) {
    ensure_initialized();
    gmk_runtime_select(&device.playback);
    gmk_profile_active = device.playback.active;
    profile_brightness();
}
void gmk_persistent_key_change(uint32_t factory_index, uint32_t down) {
    gmk_runtime_key_change(&device.playback, factory_index, down);
}
int gmk_persistent_render(uint8_t frame[GMK_FIXED_FRAME_BYTES], uint32_t elapsed_ms) {
    int completed = gmk_runtime_step(&device.playback, frame, elapsed_ms);
    gmk_profile_active = device.playback.active;
    profile_brightness();
    return completed;
}
#ifdef GMK_PERSISTENT_HOST_TEST
void gmk_test_power_cycle(void) {
    memset(&device, 0, sizeof(device));
    memset(&flash, 0, sizeof(flash));
    initialized = 0; gmk_profile_active = 0;
}
#endif
