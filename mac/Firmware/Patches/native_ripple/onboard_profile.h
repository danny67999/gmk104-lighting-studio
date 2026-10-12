#ifndef GMK104_ONBOARD_PROFILE_H
#define GMK104_ONBOARD_PROFILE_H

#include <stddef.h>
#include <stdint.h>

/* Portable parser for the v1 Lighting Studio format. It performs no I/O and
 * makes no flash writes. Firmware must validate the whole profile before use. */
#define GMK_PROFILE_MAX_BYTES 4064u
#define GMK_PROFILE_KEY_COUNT 104u
#define GMK_PROFILE_MAX_LAYERS 16u
#if defined(GMK_MATRIX_COLUMNS)
#define GMK_PROFILE_MAX_EFFECT_ID 26u
#elif defined(GMK_MATRIX_RAIN)
#define GMK_PROFILE_MAX_EFFECT_ID 24u
#elif defined(GMK_EXTENDED_REACTIVE)
#define GMK_PROFILE_MAX_EFFECT_ID 23u
#else
#define GMK_PROFILE_MAX_EFFECT_ID 17u
#endif
/* Every valid v1 profile fits in this bound: header, permutation, geometry,
 * and sixteen maximum-length layer records. The 4064-byte sector allowance
 * remains a format/storage limit, rather than the size of each MCU buffer. */
#define GMK_PROFILE_BUFFER_BYTES (344u + GMK_PROFILE_MAX_LAYERS * (57u + 80u))

typedef struct {
    const uint8_t *bytes;
    uint16_t length;
    uint8_t mode;
    uint8_t layer_count;
    uint8_t brightness;
    uint8_t requested_fps;
    uint8_t sensor_flags;
    uint16_t layer_offsets[GMK_PROFILE_MAX_LAYERS];
} gmk_profile_view;

uint32_t gmk_profile_crc32(const uint8_t *data, size_t length);
int gmk_profile_validate(const uint8_t *data, size_t length, gmk_profile_view *view);

#endif
