#include "renderer.h"

#include <math.h>
#include <string.h>

/* This reference implementation mirrors LightingEffects.swift's effect and
 * layer rules. It deliberately keeps bounded state and does no I/O, flash
 * access, allocation, or key scanning. It uses C99 libm; target performance
 * and code size must be measured before incorporating it into firmware. */

#define PROFILE_HEADER_BYTES 32u
#define PROFILE_MAP_BYTES 104u
#define PROFILE_GEOMETRY_BYTES 208u
#define PROFILE_COMMON_BYTES (PROFILE_HEADER_BYTES + PROFILE_MAP_BYTES + PROFILE_GEOMETRY_BYTES)
#define MASK_BYTES 13u
#define PI 3.14159265358979323846

enum {
    EFFECT_RIPPLE = 0,
    EFFECT_RAINBOW_RIPPLE = 1,
    EFFECT_REACTIVE = 2,
    EFFECT_WAVE = 3,
    EFFECT_BREATHING = 4,
    EFFECT_SPECTRUM = 5,
    EFFECT_STATIC = 6,
    EFFECT_MUSIC = 7,
    EFFECT_TEMPERATURE = 8
};

typedef struct {
    double r, g, b;
} rgb_unit;

typedef struct {
    uint8_t origin_led;
    double origin_x, origin_y;
    double age, reach;
} active_pulse;

static uint16_t read16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static double clamp01(double x) {
    if (x < 0) return 0;
    if (x > 1) return 1;
    return x;
}

static double maximum3(double a, double b, double c) {
    double result = a > b ? a : b;
    return result > c ? result : c;
}

static uint8_t byte(double value) {
    if (!(value > 0)) return 0;
    if (value >= 255) return 255;
    return (uint8_t)floor(value + 0.5);
}

static double wrapped(double seconds, double period) {
    double phase = fmod(seconds, period) / period;
    return phase < 0 ? phase + 1 : phase;
}

static rgb_unit color_hue(double hue, double level) {
    rgb_unit color = {0, 0, 0};
    double sector, fraction, up, down;
    hue -= floor(hue);
    sector = hue * 6;
    fraction = sector - floor(sector);
    up = floor(fraction * 255 + 0.5);
    down = floor((1 - fraction) * 255 + 0.5);
    switch ((int)sector) {
    case 0: color.r = 255; color.g = up; break;
    case 1: color.r = down; color.g = 255; break;
    case 2: color.g = 255; color.b = up; break;
    case 3: color.g = down; color.b = 255; break;
    case 4: color.r = up; color.b = 255; break;
    default: color.r = 255; color.b = down; break;
    }
    color.r = byte(color.r * clamp01(level));
    color.g = byte(color.g * clamp01(level));
    color.b = byte(color.b * clamp01(level));
    return color;
}

static rgb_unit color_selected(const uint8_t *layer, double level) {
    rgb_unit color;
    level = clamp01(level);
    color.r = byte(layer[7] * level);
    color.g = byte(layer[8] * level);
    color.b = byte(layer[9] * level);
    return color;
}

static int mask_has(const uint8_t *mask, unsigned index) {
    return (mask[index >> 3] & (uint8_t)(1u << (index & 7u))) != 0;
}

static double led_x(const gmk_renderer *r, unsigned led) {
    return r->profile.bytes[PROFILE_HEADER_BYTES + PROFILE_MAP_BYTES + 2u * led] / 2.0;
}

static double led_y(const gmk_renderer *r, unsigned led) {
    return r->profile.bytes[PROFILE_HEADER_BYTES + PROFILE_MAP_BYTES + 2u * led + 1u] / 2.0;
}

int gmk_renderer_init(gmk_renderer *renderer, const gmk_profile_view *profile) {
    gmk_profile_view verified;
    if (!renderer) return 0;
    memset(renderer, 0, sizeof *renderer);
    if (!profile || !gmk_profile_validate(profile->bytes, profile->length, &verified))
        return 0;
    renderer->profile = verified;
    renderer->initialized = 1;
    return 1;
}

void gmk_renderer_key_down(gmk_renderer *r, uint8_t scan_index, uint32_t time_ms) {
    gmk_renderer_pulse *pulse;
    unsigned led, key;
    double origin_x, origin_y, reach_squared = 0;
    if (!r || !r->initialized || scan_index >= GMK_PROFILE_KEY_COUNT) return;
    if (r->profile.mode != 0) return;
    led = r->profile.bytes[PROFILE_HEADER_BYTES + scan_index];
    origin_x = led_x(r, led);
    origin_y = led_y(r, led);
    for (key = 0; key < GMK_PROFILE_KEY_COUNT; ++key) {
        double dx = led_x(r, key) - origin_x;
        double dy = led_y(r, key) - origin_y;
        double squared = dx * dx + dy * dy;
        if (squared > reach_squared) reach_squared = squared;
    }
    pulse = &r->pulses[r->next_pulse];
    pulse->scan_index = scan_index;
    pulse->time_ms = time_ms;
    pulse->reach = (float)sqrt(reach_squared);
    r->next_pulse = (uint8_t)((r->next_pulse + 1u) % GMK_RENDERER_MAX_PULSES);
    if (r->pulse_count < GMK_RENDERER_MAX_PULSES) ++r->pulse_count;
}

void gmk_renderer_set_music(gmk_renderer *r, uint8_t bass, uint8_t mid,
                            uint8_t treble, uint8_t level, uint32_t time_ms) {
    if (!r || !r->initialized) return;
    r->music[0] = bass;
    r->music[1] = mid;
    r->music[2] = treble;
    r->music[3] = level;
    r->music_time_ms = time_ms;
    r->has_music = 1;
}

void gmk_renderer_set_temperature(gmk_renderer *r,
                                  uint16_t celsius_x100, uint32_t time_ms) {
    if (!r || !r->initialized) return;
    if (celsius_x100 < 100 || celsius_x100 > 12500) {
        r->has_temperature = 0;
        return;
    }
    r->temperature_celsius_x100 = celsius_x100;
    r->temperature_time_ms = time_ms;
    r->has_temperature = 1;
}

static unsigned collect_pulses(const gmk_renderer *r, const uint8_t *layer,
                               uint32_t time_ms, active_pulse result[GMK_RENDERER_MAX_PULSES]) {
    unsigned count = 0, slot;
    const uint8_t *trigger = layer + 14;
    double speed = read16(layer + 2) / 256.0;
    for (slot = 0; slot < r->pulse_count; ++slot) {
        const gmk_renderer_pulse *pulse = &r->pulses[slot];
        uint32_t elapsed = time_ms - pulse->time_ms;
        double age = elapsed * speed / 1000.0;
        unsigned led;
        if (!mask_has(trigger, pulse->scan_index) || !(age < 4.5)) continue;
        led = r->profile.bytes[PROFILE_HEADER_BYTES + pulse->scan_index];
        result[count].origin_led = (uint8_t)led;
        result[count].origin_x = led_x(r, led);
        result[count].origin_y = led_y(r, led);
        result[count].age = age;
        result[count].reach = pulse->reach;
        ++count;
    }
    return count;
}

static void layer_color(const gmk_renderer *r, const uint8_t *layer,
                        unsigned led, uint32_t time_ms,
                        const active_pulse *pulses, unsigned pulse_count,
                        double min_x, double max_x, double min_y, double max_y,
                        rgb_unit *color, double *coverage) {
    const double seconds = time_ms / 1000.0;
    const double speed = read16(layer + 2) / 256.0;
    const double intensity = layer[4] / 255.0;
    const unsigned effect = layer[0];
    unsigned p;
    color->r = color->g = color->b = 0;
    *coverage = 0;
    if (intensity == 0) return;
    if (effect == EFFECT_STATIC) {
        *color = color_selected(layer, intensity);
        *coverage = byte(255 * intensity) / 255.0;
    } else if (effect == EFFECT_BREATHING) {
        double phase = wrapped(seconds, 3 / speed);
        double breath = (1 - cos(phase * 2 * PI)) / 2;
        double level = (0.025 + 0.975 * breath * breath) * intensity;
        *color = color_selected(layer, level);
        *coverage = byte(255 * level) / 255.0;
    } else if (effect == EFFECT_SPECTRUM) {
        *color = color_hue(wrapped(seconds, 9 / speed), intensity);
        *coverage = maximum3(color->r, color->g, color->b) / 255.0;
    } else if (effect == EFFECT_TEMPERATURE) {
        double temperature, fraction;
        if (!r->has_temperature || time_ms - r->temperature_time_ms >= 5000u) return;
        temperature = r->temperature_celsius_x100 / 100.0;
        fraction = clamp01((temperature - layer[12]) / (layer[13] - layer[12]));
        *color = color_hue((1 - fraction) * (2.0 / 3.0), intensity);
        *coverage = maximum3(color->r, color->g, color->b) / 255.0;
    } else if (effect == EFFECT_WAVE) {
        double hue = led_x(r, led) / 8.0 + led_y(r, led) * (0.35 / 8.0) -
                     wrapped(seconds, 5 / speed);
        *color = color_hue(hue, intensity);
        *coverage = maximum3(color->r, color->g, color->b) / 255.0;
    } else if (effect == EFFECT_MUSIC) {
        double x, height, bass, mid, treble, band, level, bar, glow;
        if (!r->has_music || time_ms - r->music_time_ms >= 500u || !r->music[3]) return;
        x = (led_x(r, led) - min_x) / fmax(1, max_x - min_x);
        height = (max_y - led_y(r, led)) / fmax(1, max_y - min_y);
        bass = r->music[0] / 255.0;
        mid = r->music[1] / 255.0;
        treble = r->music[2] / 255.0;
        band = x < 0.5 ? bass * (1 - x * 2) + mid * x * 2
                       : mid * (2 - x * 2) + treble * (x * 2 - 1);
        level = fmin(1, band * (read16(layer + 10) / 256.0));
        bar = clamp01((level - height * 0.85) * 5);
        glow = (0.08 * level + 0.92 * bar * level) * intensity;
        *color = color_hue(x * 0.8 - wrapped(seconds, 12 / speed), glow);
        *coverage = maximum3(color->r, color->g, color->b) / 255.0;
    } else if (effect == EFFECT_REACTIVE || effect == EFFECT_RIPPLE ||
               effect == EFFECT_RAINBOW_RIPPLE) {
        double level = 0;
        double red = 0, green = 0, blue = 0;
        double x = led_x(r, led), y = led_y(r, led);
        for (p = 0; p < pulse_count; ++p) {
            const active_pulse *pulse = pulses + p;
            if (effect == EFFECT_REACTIVE) {
                double remaining;
                if (!(layer[1] & 2u) && led != pulse->origin_led) continue;
                if (pulse->age >= 1.4) continue;
                remaining = 1 - pulse->age / 1.4;
                level += remaining * remaining;
            } else {
                double dx = x - pulse->origin_x, dy = y - pulse->origin_y;
                double distance = hypot(dx, dy);
                double radius = pulse->age * 8;
                double width = 0.6 + radius * 0.045;
                double offset = (distance - radius) / width;
                double travel_fade, exit_fade, contribution;
                if (fabs(offset) > 8) continue;
                travel_fade = 1 - 0.2 * fmin(1, radius / fmax(1, pulse->reach));
                exit_fade = fmax(0, 1 - fmax(0, radius - pulse->reach) / (width * 3));
                contribution = exp(-0.5 * offset * offset) * travel_fade * exit_fade * exit_fade;
                level += contribution;
                if (effect == EFFECT_RAINBOW_RIPPLE) {
                    rgb_unit rainbow = color_hue(atan2(dy, dx) / (2 * PI) +
                                                 pulse->age * 0.4, 1);
                    red += rainbow.r * contribution;
                    green += rainbow.g * contribution;
                    blue += rainbow.b * contribution;
                }
            }
        }
        *coverage = byte(255 * clamp01(level) * intensity) / 255.0;
        if (effect == EFFECT_RAINBOW_RIPPLE) {
            double amount = intensity / fmax(1, level);
            color->r = byte(red * amount);
            color->g = byte(green * amount);
            color->b = byte(blue * amount);
        } else *color = color_selected(layer, clamp01(level) * intensity);
    }
}

int gmk_renderer_render(const gmk_renderer *r, uint32_t time_ms,
                        uint8_t out[GMK_RENDERER_FRAME_BYTES]) {
    unsigned layer_index, led;
    double min_x = 128, min_y = 128, max_x = 0, max_y = 0;
    if (!r || !r->initialized || !out) return -1;
    memset(out, 0, GMK_RENDERER_FRAME_BYTES);
    if (r->profile.mode == 1) return 0;
    if (r->profile.mode == 2) {
        memcpy(out, r->profile.bytes + PROFILE_COMMON_BYTES, GMK_RENDERER_FRAME_BYTES);
        return 1;
    }
    for (led = 0; led < GMK_PROFILE_KEY_COUNT; ++led) {
        double x = led_x(r, led), y = led_y(r, led);
        if (x < min_x) min_x = x;
        if (x > max_x) max_x = x;
        if (y < min_y) min_y = y;
        if (y > max_y) max_y = y;
    }
    /* The binary and Mac editor list topmost layers first. */
    for (layer_index = r->profile.layer_count; layer_index > 0; --layer_index) {
        const uint8_t *layer = r->profile.bytes + r->profile.layer_offsets[layer_index - 1];
        const uint8_t *output_mask = layer + 27;
        active_pulse active[GMK_RENDERER_MAX_PULSES];
        unsigned active_count = 0;
        double opacity;
        if (!(layer[1] & 1u) || layer[5] == 0) continue;
        opacity = layer[5] / 255.0;
        if (layer[0] == EFFECT_RIPPLE || layer[0] == EFFECT_RAINBOW_RIPPLE ||
            layer[0] == EFFECT_REACTIVE)
            active_count = collect_pulses(r, layer, time_ms, active);
        for (led = 0; led < GMK_PROFILE_KEY_COUNT; ++led) {
            rgb_unit color;
            double coverage, alpha, keep;
            unsigned off = led * 3u;
            if (!mask_has(output_mask, led)) continue;
            layer_color(r, layer, led, time_ms, active, active_count,
                        min_x, max_x, min_y, max_y, &color, &coverage);
            alpha = coverage * opacity;
            keep = (layer[1] & 4u) ? 1 : 1 - alpha;
            out[off] = byte(out[off] * keep + color.r * opacity);
            out[off + 1] = byte(out[off + 1] * keep + color.g * opacity);
            out[off + 2] = byte(out[off + 2] * keep + color.b * opacity);
        }
    }
    return 1;
}
