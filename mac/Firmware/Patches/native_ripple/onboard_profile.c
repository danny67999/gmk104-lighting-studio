#include "onboard_profile.h"

#include <string.h>

#define HEADER 32u
#define MAP_BYTES 104u
#define COORD_BYTES 208u
#define MASK_BYTES 13u
#define LAYER_FIXED_BYTES 57u

static uint16_t le16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

uint32_t gmk_profile_crc32(const uint8_t *data, size_t length) {
    uint32_t crc = 0xffffffffu;
    size_t i;
    if (!data && length) return 0;
    for (i = 0; i < length; ++i) {
        unsigned bit;
        crc ^= data[i];
        for (bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
    }
    return ~crc;
}

static int valid_utf8(const uint8_t *p, size_t length) {
    size_t i = 0;
    int visible = 0;
    while (i < length) {
        uint8_t c = p[i];
        if (c < 0x80) {
            if (c != ' ' && c != '\t' && c != '\r' && c != '\n') visible = 1;
            ++i;
        } else if (c >= 0xc2 && c <= 0xdf && i + 1 < length &&
                   (p[i + 1] & 0xc0) == 0x80) {
            visible = 1; i += 2;
        } else if (c >= 0xe0 && c <= 0xef && i + 2 < length &&
                   (p[i + 1] & 0xc0) == 0x80 && (p[i + 2] & 0xc0) == 0x80 &&
                   !(c == 0xe0 && p[i + 1] < 0xa0) &&
                   !(c == 0xed && p[i + 1] >= 0xa0)) {
            visible = 1; i += 3;
        } else if (c >= 0xf0 && c <= 0xf4 && i + 3 < length &&
                   (p[i + 1] & 0xc0) == 0x80 && (p[i + 2] & 0xc0) == 0x80 &&
                   (p[i + 3] & 0xc0) == 0x80 &&
                   !(c == 0xf0 && p[i + 1] < 0x90) &&
                   !(c == 0xf4 && p[i + 1] >= 0x90)) {
            visible = 1; i += 4;
        } else return 0;
    }
    return visible;
}

static int mask_is_zero(const uint8_t *mask) {
    size_t i;
    for (i = 0; i < MASK_BYTES; ++i) if (mask[i]) return 0;
    return 1;
}

int gmk_profile_validate(const uint8_t *data, size_t length, gmk_profile_view *view) {
    uint8_t seen[GMK_PROFILE_KEY_COUNT] = {0};
    uint8_t sensor_flags = 0;
    size_t i, at;
    gmk_profile_view candidate = {0};

    if (!data || !view || length < HEADER + MAP_BYTES + COORD_BYTES ||
        length > GMK_PROFILE_BUFFER_BYTES) return 0;
    if (memcmp(data, "GMKP", 4) != 0 || data[4] != 1 ||
        memcmp(data + 16, "A104", 4) != 0 || le16(data + 8) != length ||
        data[5] > 2 || data[6] > GMK_PROFILE_MAX_LAYERS ||
        (data[5] == 0 ? data[6] == 0 : data[6] != 0) ||
        (data[7] > 18 && data[7] != 20) || data[10] > 4 ||
        (data[11] != 15 && data[11] != 30 && data[11] != 60 &&
         data[11] != 90 && data[11] != 120) ||
        (data[20] & (uint8_t)~3u)) return 0;
    for (i = 21; i < HEADER; ++i) if (data[i] != 0) return 0;
    if (gmk_profile_crc32(data + HEADER, length - HEADER) != le32(data + 12)) return 0;

    for (i = 0; i < GMK_PROFILE_KEY_COUNT; ++i) {
        uint8_t led = data[HEADER + i];
        if (led >= GMK_PROFILE_KEY_COUNT || seen[led]) return 0;
        seen[led] = 1;
    }
    for (i = HEADER + MAP_BYTES; i < HEADER + MAP_BYTES + COORD_BYTES; ++i)
        if (data[i] >= 128) return 0;

    at = HEADER + MAP_BYTES + COORD_BYTES;
    if (data[5] != 0 && data[20] != 0) return 0;
    if (data[5] == 1 && length != at) return 0;
    if (data[5] == 2 && length != at + 3 * GMK_PROFILE_KEY_COUNT) return 0;
    if (data[5] == 0) {
        size_t layer;
        for (layer = 0; layer < data[6]; ++layer) {
            uint8_t expected[MASK_BYTES] = {0};
            uint8_t effect, flags, name_length;
            const uint8_t *record, *trigger, *output;
            size_t key, prior;
            if (at + LAYER_FIXED_BYTES > length) return 0;
            record = data + at;
            effect = record[0]; flags = record[1];
            trigger = record + 14; output = record + 27;
            name_length = record[56];
            if (effect > GMK_PROFILE_MAX_EFFECT_ID || (flags & (uint8_t)~15u) ||
                le16(record + 2) < 64 || le16(record + 2) > 768 ||
                record[6] > 4 || le16(record + 10) < 64 ||
                le16(record + 10) > 1024 || record[12] < 10 ||
                record[12] > 80 || record[13] < 40 || record[13] > 110 ||
                record[13] - record[12] < 5 ||
                name_length == 0 || name_length > 80 ||
                at + LAYER_FIXED_BYTES + name_length > length ||
                !valid_utf8(record + LAYER_FIXED_BYTES, name_length)) return 0;
            if (flags & 8u) {
                for (i = 0; i < MASK_BYTES; ++i) if (trigger[i] != 0xff) return 0;
            }
            if (!mask_is_zero(trigger)) {
                if (flags & 2u) memset(expected, 0xff, MASK_BYTES);
                else for (key = 0; key < GMK_PROFILE_KEY_COUNT; ++key)
                    if (trigger[key / 8] & (uint8_t)(1u << (key % 8))) {
                        uint8_t led = data[HEADER + key];
                        expected[led / 8] |= (uint8_t)(1u << (led % 8));
                    }
            }
            if (memcmp(expected, output, MASK_BYTES) != 0) return 0;
            if ((flags & 1u) && record[5] != 0) {
                if (effect == 7) sensor_flags |= 1;
                if (effect == 8) sensor_flags |= 2;
            }
            for (prior = 0; prior < layer; ++prior)
                if (memcmp(record + 40, data + candidate.layer_offsets[prior] + 40, 16) == 0)
                    return 0;
            candidate.layer_offsets[layer] = (uint16_t)at;
            at += LAYER_FIXED_BYTES + name_length;
        }
        if (at != length || data[20] != sensor_flags) return 0;
    }

    candidate.bytes = data;
    candidate.length = (uint16_t)length;
    candidate.mode = data[5]; candidate.layer_count = data[6];
    candidate.brightness = data[10]; candidate.requested_fps = data[11];
    candidate.sensor_flags = data[20];
    *view = candidate;
    return 1;
}
