#include "renderer_fixed.h"

/* Freestanding, allocation-free integer renderer. Coordinates are stored in
 * half-key units; ring radius and width use Q8 half-key units. Hue uses Q16
 * turns. No floating-point, math library, system clock, I/O, or flash access. */
#define MAP_START 32u
#define COORD_START 136u
#define FRAME_START 344u
#define PULSE_MAX_AGE_Q8 1152u /* 4.5 seconds after speed scaling */

enum {
    FX_RIPPLE, FX_RAINBOW_RIPPLE, FX_REACTIVE, FX_WAVE, FX_BREATHING,
    FX_SPECTRUM, FX_STATIC, FX_MUSIC, FX_TEMPERATURE, FX_KEY_HOLD,
    FX_STARLIGHT, FX_RAINBOW_STARLIGHT, FX_FIRE, FX_COLOR_WHEEL,
    FX_SCANNER, FX_COMET, FX_RAIN, FX_AURORA
};

typedef struct { uint8_t r, g, b; } rgb8;
#ifdef GMK_COOPERATIVE_RENDER
typedef gmk_fixed_active fixed_active;
#else
typedef struct {
    uint16_t age_q8;
    uint16_t reach_q8;
    uint8_t led;
    uint8_t x, y;
    uint8_t slot;
} fixed_active;
#endif

static uint16_t le16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}
static uint8_t u8_sat(uint32_t n) { return (uint8_t)(n > 255u ? 255u : n); }
static uint8_t mul255(unsigned a, unsigned b) {
    return (uint8_t)((a * b + 127u) / 255u);
}
static uint8_t mask_has(const uint8_t *mask, unsigned index) {
    return (uint8_t)(mask[index >> 3] & (uint8_t)(1u << (index & 7u)));
}
static void mask_set(uint8_t *mask, unsigned index) {
    mask[index >> 3] |= (uint8_t)(1u << (index & 7u));
}
static void mask_clear(uint8_t *mask, unsigned index) {
    mask[index >> 3] &= (uint8_t)~(1u << (index & 7u));
}
static uint8_t noise8(uint32_t seed) {
    seed ^= seed >> 16; seed *= UINT32_C(0x7feb352d);
    seed ^= seed >> 15; seed *= UINT32_C(0x846ca68b);
    seed ^= seed >> 16;
    return (uint8_t)(seed >> 24);
}
static uint8_t triangle8(uint16_t phase) {
    return (uint8_t)((phase < 32768u ? phase : (uint16_t)(65535u - phase)) >> 7);
}
static uint8_t coord_x(const gmk_fixed_renderer *r, unsigned led) {
    return r->profile.bytes[COORD_START + led * 2u];
}
static uint8_t coord_y(const gmk_fixed_renderer *r, unsigned led) {
    return r->profile.bytes[COORD_START + led * 2u + 1u];
}
static uint16_t isqrt32(uint32_t value) {
    uint32_t result = 0, bit = 1u << 30;
    while (bit > value) bit >>= 2;
    while (bit) {
        if (value >= result + bit) {
            value -= result + bit;
            result = (result >> 1) + bit;
        } else result >>= 1;
        bit >>= 2;
    }
    return (uint16_t)result;
}
static uint16_t phase16(uint32_t time_ms, unsigned base_period_ms, unsigned speed_q8) {
    uint32_t period = (base_period_ms * 256u) / speed_q8;
    return (uint16_t)(((time_ms % period) * 65536u) / period);
}
static rgb8 hue_rgb(uint16_t hue, uint8_t level) {
    uint32_t hue6 = (uint32_t)hue * 6u;
    unsigned sector = hue6 >> 16;
    uint32_t fraction = hue6 & 65535u;
    uint8_t up = (uint8_t)((fraction * 255u + 32767u) / 65535u);
    uint8_t down = (uint8_t)(((65535u - fraction) * 255u + 32767u) / 65535u);
    rgb8 color = {0, 0, 0};
    switch (sector) {
    case 0: color.r = 255; color.g = up; break;
    case 1: color.r = down; color.g = 255; break;
    case 2: color.g = 255; color.b = up; break;
    case 3: color.g = down; color.b = 255; break;
    case 4: color.r = up; color.b = 255; break;
    default: color.r = 255; color.b = down; break;
    }
    color.r = mul255(color.r, level);
    color.g = mul255(color.g, level);
    color.b = mul255(color.b, level);
    return color;
}
static rgb8 selected_rgb(const uint8_t *layer, uint8_t level) {
    rgb8 color;
    color.r = mul255(layer[7], level);
    color.g = mul255(layer[8], level);
    color.b = mul255(layer[9], level);
    return color;
}
static uint8_t rgb_coverage(rgb8 color) {
    uint8_t result = color.r > color.g ? color.r : color.g;
    return result > color.b ? result : color.b;
}

int gmk_fixed_init(gmk_fixed_renderer *r, const gmk_profile_view *profile) {
    gmk_profile_view verified;
    unsigned i;
    if (!r) return 0;
    /* No libc initialization; the validated source remains immutable. */
    for (i = 0; i < sizeof *r; ++i) ((uint8_t *)r)[i] = 0;
    if (!profile || !gmk_profile_validate(profile->bytes, profile->length, &verified)) return 0;
    r->profile.bytes = verified.bytes;
    r->profile.length = verified.length;
    r->profile.mode = verified.mode;
    r->profile.layer_count = verified.layer_count;
    r->profile.brightness = verified.brightness;
    r->profile.requested_fps = verified.requested_fps;
    r->profile.sensor_flags = verified.sensor_flags;
    for (i = 0; i < GMK_PROFILE_MAX_LAYERS; ++i)
        r->profile.layer_offsets[i] = verified.layer_offsets[i];
#ifdef GMK_COOPERATIVE_RENDER
    r->bounds[0] = r->bounds[1] = 127;
    if (verified.mode == 0) for (i = 0; i < verified.layer_count; ++i) {
        const uint8_t *layer = verified.bytes + verified.layer_offsets[i];
        unsigned byte;
        if (!(layer[1] & 1u) || !layer[4] || !layer[5]) continue;
        if (layer[0] > FX_REACTIVE) continue;
        for (byte = 0; byte < 13; ++byte) {
            if (layer[0] == FX_REACTIVE) r->reactive_triggers[byte] |= layer[14 + byte];
            else r->ripple_triggers[byte] |= layer[14 + byte];
        }
    }
    for (i = 0; i < GMK_PROFILE_KEY_COUNT; ++i) {
        uint8_t x = coord_x(r, i), y = coord_y(r, i);
        if (x < r->bounds[0]) r->bounds[0] = x;
        if (y < r->bounds[1]) r->bounds[1] = y;
        if (x > r->bounds[2]) r->bounds[2] = x;
        if (y > r->bounds[3]) r->bounds[3] = y;
    }
#endif
    r->initialized = 1;
    return 1;
}

void gmk_fixed_key_down(gmk_fixed_renderer *r, uint8_t scan_index, uint32_t time_ms) {
    unsigned led, key;
    int origin_x, origin_y;
    uint16_t farthest_q8 = 0;
    gmk_fixed_pulse *pulse;
    if (!r || !r->initialized || r->profile.mode != 0 ||
        scan_index >= GMK_PROFILE_KEY_COUNT) return;
    led = r->profile.bytes[MAP_START + scan_index];
    mask_set(r->held_scan, scan_index);
    mask_set(r->held_output, led);
    origin_x = coord_x(r, led);
    origin_y = coord_y(r, led);
    pulse = &r->pulses[r->next_pulse];
    for (key = 0; key < GMK_PROFILE_KEY_COUNT; ++key) {
        int dx = (int)coord_x(r, key) - origin_x;
        int dy = (int)coord_y(r, key) - origin_y;
        uint32_t squared = (uint32_t)(dx * dx + dy * dy);
        uint16_t distance_q8 = isqrt32(squared << 16);
        r->distances_q8[r->next_pulse][key] = distance_q8;
        if (distance_q8 > farthest_q8) farthest_q8 = distance_q8;
    }
    pulse->scan_index = scan_index;
    pulse->time_ms = time_ms;
    pulse->reach_q8_half_keys = farthest_q8;
    r->next_pulse = (uint8_t)((r->next_pulse + 1u) % GMK_FIXED_MAX_PULSES);
    if (r->pulse_count < GMK_FIXED_MAX_PULSES) ++r->pulse_count;
}

void gmk_fixed_key_up(gmk_fixed_renderer *r, uint8_t scan_index) {
    unsigned led;
    if (!r || !r->initialized || r->profile.mode != 0 ||
        scan_index >= GMK_PROFILE_KEY_COUNT) return;
    led = r->profile.bytes[MAP_START + scan_index];
    mask_clear(r->held_scan, scan_index);
    mask_clear(r->held_output, led);
}

void gmk_fixed_clear_held(gmk_fixed_renderer *r) {
    unsigned i;
    if (!r) return;
    for (i = 0; i < 13u; ++i) r->held_scan[i] = r->held_output[i] = 0;
}

void gmk_fixed_set_music(gmk_fixed_renderer *r, uint8_t bass, uint8_t mid,
                         uint8_t treble, uint8_t level, uint32_t time_ms) {
    if (!r || !r->initialized) return;
    r->music[0] = bass;
    r->music[1] = mid;
    r->music[2] = treble;
    r->music[3] = level;
    r->music_time_ms = time_ms;
    r->has_music = 1;
}

void gmk_fixed_set_temperature(gmk_fixed_renderer *r,
                               uint16_t celsius_x100, uint32_t time_ms) {
    if (!r || !r->initialized) return;
    if (celsius_x100 < 100u || celsius_x100 > 12500u) {
        r->has_temperature = 0;
        return;
    }
    r->temperature_celsius_x100 = celsius_x100;
    r->temperature_time_ms = time_ms;
    r->has_temperature = 1;
}

static unsigned collect(const gmk_fixed_renderer *r, const uint8_t *layer,
                        uint32_t time_ms, fixed_active active[GMK_FIXED_MAX_PULSES]) {
    unsigned count = 0, slot;
    unsigned speed = le16(layer + 2);
    for (slot = 0; slot < r->pulse_count; ++slot) {
        const gmk_fixed_pulse *pulse = r->pulses + slot;
        uint32_t elapsed = time_ms - pulse->time_ms;
        uint32_t age_q8;
        unsigned led;
        /* Even the slowest supported speed expires by 18 real seconds. */
        if (elapsed >= 18000u || !mask_has(layer + 14, pulse->scan_index)) continue;
        age_q8 = elapsed * speed / 1000u;
        if (age_q8 >= PULSE_MAX_AGE_Q8) continue;
        led = r->profile.bytes[MAP_START + pulse->scan_index];
        active[count].age_q8 = (uint16_t)age_q8;
        active[count].reach_q8 = pulse->reach_q8_half_keys;
        active[count].led = (uint8_t)led;
        active[count].x = coord_x(r, led);
        active[count].y = coord_y(r, led);
        active[count].slot = (uint8_t)slot;
        ++count;
    }
    return count;
}

/* exp(-x*x/2) in byte form at x = 0, .25, .5, ..., 4. */
static const uint8_t gaussian_quarter[17] = {
    255, 247, 225, 192, 155, 117, 83, 55, 34, 20, 11, 6, 3, 1, 1, 0, 0
};
static uint8_t gaussian(uint32_t offset_q8) {
    unsigned index = offset_q8 >> 6;
    unsigned part = offset_q8 & 63u;
    if (index >= 16u) return 0;
    return (uint8_t)((gaussian_quarter[index] * (64u - part) +
                      gaussian_quarter[index + 1u] * part + 32u) >> 6);
}

/* Fast octant angle, Q16 turns, for hue. Exact atan2 is the host reference. */
static uint16_t angle16(int dx, int dy) {
    unsigned ax = (unsigned)(dx < 0 ? -dx : dx);
    unsigned ay = (unsigned)(dy < 0 ? -dy : dy);
    unsigned total = ax + ay;
    unsigned quarter;
    if (!total) return 0;
    if (dx >= 0 && dy >= 0) quarter = ay * 16384u / total;
    else if (dx < 0 && dy >= 0) quarter = 16384u + ax * 16384u / total;
    else if (dx < 0) quarter = 32768u + ay * 16384u / total;
    else quarter = 49152u + ax * 16384u / total;
    return (uint16_t)quarter;
}

static void layer_pixel(const gmk_fixed_renderer *r, const uint8_t *layer,
                        unsigned led, uint32_t time_ms,
                        const fixed_active *active, unsigned active_count,
                        unsigned min_x, unsigned max_x,
                        unsigned min_y, unsigned max_y,
                        uint8_t held_trigger,
                        rgb8 *color, uint8_t *coverage) {
    unsigned effect = layer[0];
    unsigned speed = le16(layer + 2);
    uint8_t intensity = layer[4];
    unsigned p;
    color->r = color->g = color->b = 0;
    *coverage = 0;
    if (!intensity) return;
    if (effect == FX_STATIC) {
        *color = selected_rgb(layer, intensity);
        *coverage = intensity;
    } else if (effect == FX_BREATHING) {
        uint16_t phase = phase16(time_ms, 3000u, speed);
        uint32_t triangle = phase <= 32767u ? (uint32_t)phase * 2u :
                                            (uint32_t)(65535u - phase) * 2u;
        uint32_t squared = triangle * triangle / 65535u;
        uint32_t cubed = squared * triangle / 65535u;
        uint32_t smooth = 3u * squared - 2u * cubed;
        uint32_t level = 6u + 249u * smooth / 65535u * smooth / 65535u;
        uint8_t output = mul255(u8_sat(level), intensity);
        *color = selected_rgb(layer, output);
        *coverage = output;
    } else if (effect == FX_SPECTRUM) {
        *color = hue_rgb(phase16(time_ms, 9000u, speed), intensity);
        *coverage = rgb_coverage(*color);
    } else if (effect == FX_WAVE) {
        uint16_t hue = (uint16_t)((uint32_t)coord_x(r, led) * 4096u +
                                  (uint32_t)coord_y(r, led) * 1434u -
                                  phase16(time_ms, 5000u, speed));
        *color = hue_rgb(hue, intensity);
        *coverage = rgb_coverage(*color);
    } else if (effect == FX_TEMPERATURE) {
        int32_t fraction;
        uint16_t hue;
        if (!r->has_temperature || time_ms - r->temperature_time_ms >= 5000u) return;
        fraction = ((int32_t)r->temperature_celsius_x100 - (int32_t)layer[12] * 100) * 255 /
                   (((int32_t)layer[13] - layer[12]) * 100);
        if (fraction < 0) fraction = 0;
        if (fraction > 255) fraction = 255;
        hue = (uint16_t)((255 - fraction) * 171u);
        *color = hue_rgb(hue, intensity);
        *coverage = rgb_coverage(*color);
    } else if (effect == FX_MUSIC) {
        unsigned x, height, band, level, bar, glow;
        uint16_t hue;
        if (!r->has_music || time_ms - r->music_time_ms >= 500u || !r->music[3]) return;
        x = ((unsigned)coord_x(r, led) - min_x) * 255u /
            (max_x > min_x + 1u ? max_x - min_x : 2u);
        height = (max_y - coord_y(r, led)) * 255u /
                 (max_y > min_y + 1u ? max_y - min_y : 2u);
        if (x < 128u) band = (r->music[0] * (255u - 2u * x) +
                              r->music[1] * 2u * x + 127u) / 255u;
        else {
            unsigned mix = (x - 128u) * 2u;
            if (mix > 255u) mix = 255u;
            band = (r->music[1] * (255u - mix) +
                    r->music[2] * mix + 127u) / 255u;
        }
        level = band * le16(layer + 10) / 256u;
        if (level > 255u) level = 255u;
        {
            int32_t raised = ((int32_t)level - (int32_t)height * 217 / 255) * 5;
            bar = raised <= 0 ? 0u : raised >= 255 ? 255u : (unsigned)raised;
        }
        glow = (20u * level + 235u * bar * level / 255u) / 255u;
        glow = glow * intensity / 255u;
        hue = (uint16_t)(x * 205u - phase16(time_ms, 12000u, speed));
        *color = hue_rgb(hue, u8_sat(glow));
        *coverage = rgb_coverage(*color);
    } else if (effect == FX_KEY_HOLD) {
        if (((layer[1] & 2u) && held_trigger) ||
            (!(layer[1] & 2u) && mask_has(r->held_output, led))) {
            *color = selected_rgb(layer, intensity);
            *coverage = intensity;
        }
    } else if (effect == FX_STARLIGHT || effect == FX_RAINBOW_STARLIGHT) {
        uint16_t phase = phase16(time_ms, 8000u, speed);
        unsigned moment = phase >> 13, progress = phase & 8191u;
        unsigned seed = noise8((uint32_t)led * 131u + moment * 1013u);
        unsigned glow = progress < 4096u ? progress * 255u / 4096u :
                                                (8192u - progress) * 255u / 4096u;
        glow = seed > 204u ? mul255(glow, intensity) : 0u;
        *color = effect == FX_STARLIGHT ? selected_rgb(layer, (uint8_t)glow) :
                 hue_rgb((uint16_t)(noise8((uint32_t)led * 13u + moment * 503u) * 257u), (uint8_t)glow);
        *coverage = (uint8_t)glow;
    } else if (effect == FX_FIRE) {
        unsigned height = max_y > min_y ? max_y - min_y : 1u;
        unsigned top = (unsigned)coord_y(r, led) - min_y;
        uint8_t flicker = noise8((uint32_t)led * 911u +
                                 (time_ms / (250000u / speed)) * 1777u);
        uint8_t level = u8_sat(200u - top * 95u / height + flicker / 3u);
        uint16_t hue = (uint16_t)(700u + (height - top) * 5300u / height + flicker * 10u);
        *color = hue_rgb(hue, mul255(level, intensity));
        *coverage = rgb_coverage(*color);
    } else if (effect == FX_COLOR_WHEEL) {
        int x = (int)coord_x(r, led) - (int)(min_x + max_x) / 2;
        int y = (int)coord_y(r, led) - (int)(min_y + max_y) / 2;
        *color = hue_rgb((uint16_t)(angle16(x, y) + phase16(time_ms, 4000u, speed)), intensity);
        *coverage = rgb_coverage(*color);
    } else if (effect == FX_SCANNER || effect == FX_COMET) {
        unsigned span = max_x > min_x ? max_x - min_x : 1u;
        unsigned x = (unsigned)coord_x(r, led) - min_x;
        uint16_t phase = phase16(time_ms, 4000u, speed);
        unsigned glow;
        if (effect == FX_SCANNER) {
            unsigned center = (unsigned)triangle8(phase) * span / 255u;
            unsigned difference = x > center ? x - center : center - x;
            glow = gaussian(difference * 256u / 3u);
        } else {
            int head = (int)((uint32_t)phase * (span + 12u) / 65535u) - 6;
            int distance = head - (int)x;
            glow = distance < 0 ? 0u : 255u * 7u / (7u + (unsigned)distance * 3u);
        }
        *color = selected_rgb(layer, mul255(glow, intensity));
        *coverage = mul255(glow, intensity);
    } else if (effect == FX_RAIN) {
        unsigned span = max_y > min_y ? max_y - min_y : 1u;
        unsigned column = coord_x(r, led) / 4u;
        uint16_t phase = (uint16_t)(phase16(time_ms, 3000u, speed) +
                                    (uint16_t)(noise8(column * 407u) * 257u));
        unsigned drop = min_y + (uint32_t)phase * span / 65535u;
        unsigned y = coord_y(r, led);
        unsigned distance = y > drop ? y - drop : drop - y;
        if (span > distance && span - distance < distance) distance = span - distance;
        *coverage = mul255(gaussian(distance * 256u / 4u), intensity);
        *color = selected_rgb(layer, *coverage);
    } else if (effect == FX_AURORA) {
        unsigned span = max_y > min_y ? max_y - min_y : 1u;
        uint16_t phase = (uint16_t)(phase16(time_ms, 8000u, speed) * 2u +
                                    (uint16_t)(coord_x(r, led) * 900u));
        unsigned wave = triangle8(phase);
        unsigned center = min_y + span * (35u + wave * 30u / 255u) / 100u;
        unsigned y = coord_y(r, led);
        unsigned distance = y > center ? y - center : center - y;
        unsigned glow = 35u + 220u * gaussian(distance * 256u / (span / 3u + 1u)) / 255u;
        *color = hue_rgb((uint16_t)(23500u + wave * 35u), mul255(glow, intensity));
        *coverage = rgb_coverage(*color);
    } else if (effect == FX_REACTIVE || effect == FX_RIPPLE ||
               effect == FX_RAINBOW_RIPPLE) {
        uint32_t level = 0, red = 0, green = 0, blue = 0;
        int x = coord_x(r, led), y = coord_y(r, led);
        for (p = 0; p < active_count; ++p) {
            const fixed_active *pulse = active + p;
            uint8_t contribution;
            if (effect == FX_REACTIVE) {
                unsigned remaining;
                if (!(layer[1] & 2u) && led != pulse->led) continue;
                if (pulse->age_q8 >= 358u) continue;
                remaining = 255u - pulse->age_q8 * 255u / 358u;
                contribution = mul255(remaining, remaining);
            } else {
                int dx = x - pulse->x, dy = y - pulse->y;
                uint32_t distance_q8 = r->distances_q8[pulse->slot][led];
                uint32_t radius_q8 = (uint32_t)pulse->age_q8 * 16u;
                uint32_t width_q8 = 307u + radius_q8 * 45u / 1000u;
                uint32_t difference = distance_q8 > radius_q8 ?
                                      distance_q8 - radius_q8 : radius_q8 - distance_q8;
                uint32_t offset_q8 = difference * 256u / width_q8;
                unsigned travel, exit_fade;
                if (offset_q8 >= 1024u) continue;
                travel = 255u - 51u * (radius_q8 < pulse->reach_q8 ?
                                        radius_q8 : pulse->reach_q8) /
                                       (pulse->reach_q8 > 256u ? pulse->reach_q8 : 256u);
                exit_fade = 255u;
                /* Avoid unsigned underflow when the wave has exited the board. */
                if (radius_q8 > pulse->reach_q8) {
                    unsigned loss = (radius_q8 - pulse->reach_q8) * 255u /
                                    (width_q8 * 3u);
                    exit_fade = loss >= 255u ? 0u : 255u - loss;
                }
                contribution = gaussian(offset_q8);
                contribution = mul255(contribution, travel);
                contribution = mul255(contribution, mul255(exit_fade, exit_fade));
                if (effect == FX_RAINBOW_RIPPLE) {
                    uint16_t angle = angle16(dx, dy);
                    uint16_t hue = (uint16_t)(angle + pulse->age_q8 * 102u);
                    rgb8 rainbow = hue_rgb(hue, 255);
                    red += rainbow.r * contribution;
                    green += rainbow.g * contribution;
                    blue += rainbow.b * contribution;
                }
            }
            level += contribution;
        }
        *coverage = mul255(u8_sat(level), intensity);
        if (effect == FX_RAINBOW_RIPPLE) {
            uint32_t denominator = 255u * (level > 255u ? level : 255u);
            color->r = u8_sat((red * intensity + denominator / 2u) / denominator);
            color->g = u8_sat((green * intensity + denominator / 2u) / denominator);
            color->b = u8_sat((blue * intensity + denominator / 2u) / denominator);
        } else *color = selected_rgb(layer, *coverage);
    }
}

int gmk_fixed_render(const gmk_fixed_renderer *r, uint32_t time_ms,
                     uint8_t out[GMK_FIXED_FRAME_BYTES]) {
    unsigned led, layer_index, min_x = 127u, min_y = 127u, max_x = 0, max_y = 0;
    if (!r || !r->initialized || !out) return -1;
    for (led = 0; led < GMK_FIXED_FRAME_BYTES; ++led) out[led] = 0;
    if (r->profile.mode == 1) return 0;
    if (r->profile.mode == 2) {
        for (led = 0; led < GMK_FIXED_FRAME_BYTES; ++led)
            out[led] = r->profile.bytes[FRAME_START + led];
        return 1;
    }
    for (led = 0; led < GMK_PROFILE_KEY_COUNT; ++led) {
        unsigned x = coord_x(r, led), y = coord_y(r, led);
        if (x < min_x) min_x = x;
        if (x > max_x) max_x = x;
        if (y < min_y) min_y = y;
        if (y > max_y) max_y = y;
    }
    for (layer_index = r->profile.layer_count; layer_index > 0; --layer_index) {
        const uint8_t *layer = r->profile.bytes + r->profile.layer_offsets[layer_index - 1u];
        const uint8_t *output_mask = layer + 27;
        fixed_active active[GMK_FIXED_MAX_PULSES];
        unsigned active_count = 0, opacity;
        uint8_t held_trigger = 0;
        if (!(layer[1] & 1u) || !layer[5]) continue;
        opacity = layer[5];
        if (layer[0] <= FX_REACTIVE)
            active_count = collect(r, layer, time_ms, active);
        if (layer[0] == FX_KEY_HOLD && (layer[1] & 2u)) {
            unsigned scan;
            for (scan = 0; scan < GMK_PROFILE_KEY_COUNT; ++scan)
                if (mask_has(r->held_scan, scan) && mask_has(layer + 14, scan)) {
                    held_trigger = 1;
                    break;
                }
        }
        for (led = 0; led < GMK_PROFILE_KEY_COUNT; ++led) {
            rgb8 color;
            uint8_t coverage;
            unsigned alpha, keep, off = led * 3u;
            if (!mask_has(output_mask, led)) continue;
            layer_pixel(r, layer, led, time_ms, active, active_count,
                        min_x, max_x, min_y, max_y, held_trigger, &color, &coverage);
            alpha = mul255(coverage, opacity);
            keep = (layer[1] & 4u) ? 255u : 255u - alpha;
            out[off] = u8_sat(((unsigned)out[off] * keep +
                               (unsigned)color.r * opacity + 127u) / 255u);
            out[off + 1u] = u8_sat(((unsigned)out[off + 1u] * keep +
                                    (unsigned)color.g * opacity + 127u) / 255u);
            out[off + 2u] = u8_sat(((unsigned)out[off + 2u] * keep +
                                    (unsigned)color.b * opacity + 127u) / 255u);
        }
    }
    return 1;
}

#ifdef GMK_COOPERATIVE_RENDER
void gmk_fixed_begin_key_down(gmk_fixed_renderer *r, uint8_t scan_index, uint32_t time_ms) {
    gmk_fixed_pulse *pulse;
    unsigned led;
    if (!r || !r->initialized || r->profile.mode != 0 || scan_index >= GMK_PROFILE_KEY_COUNT) return;
    led = r->profile.bytes[MAP_START + scan_index];
    mask_set(r->held_scan, scan_index); mask_set(r->held_output, led);
    if (!mask_has(r->ripple_triggers, scan_index) && !mask_has(r->reactive_triggers, scan_index)) return;
    pulse = &r->pulses[r->next_pulse];
    pulse->scan_index = scan_index; pulse->time_ms = time_ms; pulse->reach_q8_half_keys = 0;
    if (mask_has(r->ripple_triggers, scan_index)) {
        r->distance_pending = 1; r->distance_slot = r->next_pulse; r->distance_led = 0;
    }
    r->next_pulse = (uint8_t)((r->next_pulse + 1u) % GMK_FIXED_MAX_PULSES);
    if (r->pulse_count < GMK_FIXED_MAX_PULSES) ++r->pulse_count;
}
void gmk_fixed_prepare_distances(gmk_fixed_renderer *r) {
    unsigned work, slot, origin, end;
    gmk_fixed_pulse *pulse;
    if (!r || !r->distance_pending) return;
    slot = r->distance_slot; pulse = &r->pulses[slot];
    origin = r->profile.bytes[MAP_START + pulse->scan_index];
    end = r->distance_led + GMK_FIXED_DISTANCE_BUDGET;
    if (end > GMK_PROFILE_KEY_COUNT) end = GMK_PROFILE_KEY_COUNT;
    for (work = r->distance_led; work < end; ++work) {
        int dx = (int)coord_x(r, work) - coord_x(r, origin);
        int dy = (int)coord_y(r, work) - coord_y(r, origin);
        uint16_t distance = isqrt32((uint32_t)(dx * dx + dy * dy) << 16);
        r->distances_q8[slot][work] = distance;
        if (distance > pulse->reach_q8_half_keys) pulse->reach_q8_half_keys = distance;
    }
    r->distance_led = (uint8_t)end;
    if (end == GMK_PROFILE_KEY_COUNT) r->distance_pending = 0;
}
void gmk_fixed_job_start(const gmk_fixed_renderer *r, gmk_fixed_job *job, uint32_t time_ms) {
    unsigned i;
    for (i = 0; i < GMK_FIXED_FRAME_BYTES; ++i) job->frame[i] = 0;
    job->time_ms = time_ms; job->layer_index = r->profile.layer_count;
    job->running = 1; job->led = 0; job->prepared = 0;
}
int gmk_fixed_job_step(const gmk_fixed_renderer *r, gmk_fixed_job *job, uint8_t out[GMK_FIXED_FRAME_BYTES]) {
    const uint8_t *layer;
    unsigned led, end, opacity;
    if (!r || !job || !out || !r->initialized || !job->running) return 0;
    if (r->profile.mode == 1) { job->running = 0; return -1; }
    if (r->profile.mode == 2) {
        for (led = 0; led < GMK_FIXED_FRAME_BYTES; ++led) out[led] = r->profile.bytes[FRAME_START + led];
        job->running = 0; return 1;
    }
    while (job->layer_index) {
        layer = r->profile.bytes + r->profile.layer_offsets[job->layer_index - 1u];
        if ((layer[1] & 1u) && layer[4] && layer[5]) break;
        --job->layer_index;
    }
    if (!job->layer_index) {
        for (led = 0; led < GMK_FIXED_FRAME_BYTES; ++led) out[led] = job->frame[led];
        job->running = 0; return 1;
    }
    layer = r->profile.bytes + r->profile.layer_offsets[job->layer_index - 1u];
    if (!job->prepared) {
        job->active_count = 0; job->held_trigger = 0;
        if (layer[0] <= FX_REACTIVE) job->active_count = (uint8_t)collect(r, layer, job->time_ms, job->pulses);
        if (layer[0] == FX_KEY_HOLD && (layer[1] & 2u)) {
            unsigned scan;
            for (scan = 0; scan < GMK_PROFILE_KEY_COUNT; ++scan)
                if (mask_has(r->held_scan, scan) && mask_has(layer + 14, scan)) { job->held_trigger = 1; break; }
        }
        job->prepared = 1;
    }
    opacity = layer[5]; end = job->led + GMK_FIXED_PIXEL_BUDGET;
    if (end > GMK_PROFILE_KEY_COUNT) end = GMK_PROFILE_KEY_COUNT;
    for (led = job->led; led < end; ++led) {
        rgb8 color; uint8_t coverage; unsigned alpha, keep, off = led * 3u;
        if (!mask_has(layer + 27, led)) continue;
        layer_pixel(r, layer, led, job->time_ms, job->pulses, job->active_count,
                    r->bounds[0], r->bounds[2], r->bounds[1], r->bounds[3], job->held_trigger, &color, &coverage);
        alpha = mul255(coverage, opacity); keep = (layer[1] & 4u) ? 255u : 255u - alpha;
        job->frame[off] = u8_sat(((unsigned)job->frame[off] * keep + (unsigned)color.r * opacity + 127u) / 255u);
        job->frame[off + 1u] = u8_sat(((unsigned)job->frame[off + 1u] * keep + (unsigned)color.g * opacity + 127u) / 255u);
        job->frame[off + 2u] = u8_sat(((unsigned)job->frame[off + 2u] * keep + (unsigned)color.b * opacity + 127u) / 255u);
    }
    job->led = (uint8_t)end;
    if (end == GMK_PROFILE_KEY_COUNT) { --job->layer_index; job->led = 0; job->prepared = 0; }
    return 0;
}
#endif
