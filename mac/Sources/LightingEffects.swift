import Foundation

enum LightingEffect: String, Codable, CaseIterable, Identifiable {
    case ripple, rainbowRipple, reactive, wave, breathing, spectrum, staticColor, adaptiveMusic, cpuTemperature
    case keyHold, starlight, rainbowStarlight, fire, colorWheel, scanner, comet, rain, aurora
    case keyToggle, rainbowReactive, splash, crossRipple, rowWave, columnWave
    case matrixRain, spacedMatrixRain, matrixKeyRain

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ripple: return "Ripple"
        case .rainbowRipple: return "Rainbow ripple"
        case .reactive: return "Reactive"
        case .wave: return "Rainbow wave"
        case .breathing: return "Breathing"
        case .spectrum: return "Spectrum cycle"
        case .staticColor: return "Static color"
        case .adaptiveMusic: return "Adaptive music"
        case .cpuTemperature: return "CPU temperature"
        case .keyHold: return "Hold (press/release)"
        case .starlight: return "Starlight"
        case .rainbowStarlight: return "Rainbow starlight"
        case .fire: return "Fire"
        case .colorWheel: return "Color wheel"
        case .scanner: return "Scanner"
        case .comet: return "Comet"
        case .rain: return "Rain"
        case .aurora: return "Aurora"
        case .keyToggle: return "Key toggle"
        case .rainbowReactive: return "Rainbow reactive"
        case .splash: return "Splash"
        case .crossRipple: return "Cross ripple"
        case .rowWave: return "Row wave"
        case .columnWave: return "Column wave"
        case .matrixRain: return "Matrix rain"
        case .spacedMatrixRain: return "Spaced matrix rain"
        case .matrixKeyRain: return "Matrix key rain"
        }
    }
    var requiresKeyPresses: Bool { [.ripple, .rainbowRipple, .reactive, .keyHold, .keyToggle, .rainbowReactive, .splash, .crossRipple, .rowWave, .columnWave, .matrixKeyRain].contains(self) }
    var requiresMapping: Bool { requiresKeyPresses || ![.breathing, .spectrum, .staticColor, .cpuTemperature].contains(self) }
    var usesSelectedColor: Bool { ![.wave, .spectrum, .rainbowRipple, .adaptiveMusic, .cpuTemperature,
                                    .rainbowStarlight, .fire, .colorWheel, .aurora, .rainbowReactive].contains(self) }
    var runsOnKeyboard: Bool { self != .adaptiveMusic && self != .cpuTemperature }
    var hasAdjustableSpeed: Bool { ![.staticColor, .cpuTemperature, .keyHold, .keyToggle].contains(self) }
}

struct LightingSettings: Codable, Equatable {
    var effect: LightingEffect = .ripple
    var color: RGB = RGB(r: 0, g: 220, b: 255)
    var speed: Double = 1
    var intensity: Double = 1
    // The keyboard applies brightness separately; frames apply intensity only.
    var brightness: Int = 3

    var musicSensitivity: Double = 1
    var temperatureCold: Double = 40
    var temperatureHot: Double = 90

    private enum CodingKeys: String, CodingKey {
        case effect, color, speed, intensity, brightness, musicSensitivity, temperatureCold, temperatureHot
    }
    init(effect: LightingEffect = .ripple, color: RGB = RGB(r: 0, g: 220, b: 255),
         speed: Double = 1, intensity: Double = 1, brightness: Int = 3) {
        self.effect = effect; self.color = color; self.speed = speed
        self.intensity = intensity; self.brightness = brightness
    }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        effect = try v.decode(LightingEffect.self, forKey: .effect)
        color = try v.decode(RGB.self, forKey: .color)
        speed = try v.decode(Double.self, forKey: .speed)
        intensity = try v.decode(Double.self, forKey: .intensity)
        brightness = try v.decode(Int.self, forKey: .brightness)
        musicSensitivity = try v.decodeIfPresent(Double.self, forKey: .musicSensitivity) ?? 1
        temperatureCold = try v.decodeIfPresent(Double.self, forKey: .temperatureCold) ?? 40
        temperatureHot = try v.decodeIfPresent(Double.self, forKey: .temperatureHot) ?? 90
    }
    func validate() throws {
        try require(speed.isFinite && (0.25...3).contains(speed), "Effect speed must be between 0.25 and 3.")
        try require(intensity.isFinite && (0...1).contains(intensity), "Effect intensity must be between 0 and 1.")
        try require((0...4).contains(brightness), "Brightness must be 0–4.")
        try require(musicSensitivity.isFinite && (0.25...4).contains(musicSensitivity), "Music sensitivity must be between 0.25 and 4.")
        try require(temperatureCold.isFinite && temperatureHot.isFinite && (10...80).contains(temperatureCold) &&
                    (40...110).contains(temperatureHot) && temperatureHot - temperatureCold >= 5,
                    "Choose a cool temperature of 10–80°C and a hot temperature of 40–110°C, at least 5°C apart.")
    }

    var normalized: LightingSettings {
        var settings = self
        settings.speed = speed.isFinite ? min(3, max(0.25, speed)) : 1
        settings.intensity = intensity.isFinite ? min(1, max(0, intensity)) : 1
        settings.brightness = min(4, max(0, brightness))
        settings.musicSensitivity = musicSensitivity.isFinite ? min(4, max(0.25, musicSensitivity)) : 1
        settings.temperatureCold = temperatureCold.isFinite ? min(80, max(10, temperatureCold)) : 40
        settings.temperatureHot = temperatureHot.isFinite ? min(110, max(settings.temperatureCold + 5, max(40, temperatureHot))) : 90
        return settings
    }
}

struct KeyPulse {
    let keyID: String
    // Use the same monotonic clock as LightingRenderer.frame's time argument.
    let time: TimeInterval
}

enum PulseTiming {
    /// Keep a slow acknowledged connection from skipping an entire pulse while
    /// a frame is in flight. New presses during that frame begin at age zero.
    /// Continuous effects and audio sampling continue to use the real clock.
    static func adjusted(_ pulses: [KeyPulse], previous: TimeInterval, now: TimeInterval,
                         maximumStep: TimeInterval) -> [KeyPulse] {
        let skipped = max(0, now - previous - maximumStep)
        return pulses.map { KeyPulse(keyID: $0.keyID, time: min(now, $0.time + skipped)) }
    }
}

enum LayerBlendMode: String, Codable, CaseIterable, Identifiable {
    case normal, additive
    var id: String { rawValue }
    var displayName: String { self == .normal ? "Normal" : "Add light" }
}

struct LightingLayer: Codable, Equatable, Identifiable {
    static let limit = 16
    static let emptyCanvas: LightingLayer = {
        var layer = LightingLayer(name:"Lights off",settings:LightingSettings(effect:.staticColor,color:.black))
        layer.id = UUID(uuidString:"00000000-0000-4000-8000-000000000000")!
        layer.enabled = false;layer.keyIDs = []
        return layer
    }()
    var id = UUID()
    var name: String
    var enabled = true
    var settings: LightingSettings
    var opacity: Double = 1
    var blendMode: LayerBlendMode = .normal
    // For key-reactive effects, this is always the trigger selection. It also
    // limits output unless affectAllKeys is enabled. Empty means no triggers.
    var keyIDs: [String]?
    var affectAllKeys = false

    init(name: String? = nil, settings: LightingSettings = LightingSettings()) {
        self.name = name ?? settings.effect.displayName
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, settings, opacity, blendMode, keyIDs, affectAllKeys
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        settings = try values.decode(LightingSettings.self, forKey: .settings)
        opacity = try values.decode(Double.self, forKey: .opacity)
        blendMode = try values.decode(LayerBlendMode.self, forKey: .blendMode)
        keyIDs = try values.decodeIfPresent([String].self, forKey: .keyIDs)
        affectAllKeys = try values.decodeIfPresent(Bool.self, forKey: .affectAllKeys) ?? false
    }

    func acceptsTrigger(_ keyID: String) -> Bool { keyIDs?.contains(keyID) ?? true }

    func validate(allowedKeyIDs: Set<String>? = nil) throws {
        try settings.validate()
        try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80,
                    "Give each layer a name of 1–80 characters.")
        try require(opacity.isFinite && (0...1).contains(opacity), "Layer opacity must be between 0 and 1.")
        if let keyIDs {
            try require(keyIDs.count <= 104 && Set(keyIDs).count == keyIDs.count && keyIDs.allSatisfy { !$0.isEmpty },
                        "Layer key selections must contain unique keyboard keys.")
            if let allowedKeyIDs {
                try require(Set(keyIDs).isSubset(of: allowedKeyIDs), "A layer contains keys outside this keyboard layout.")
            }
        }
    }

    static func validate(_ layers: [Self], allowedKeyIDs: Set<String>? = nil) throws {
        try require((0...limit).contains(layers.count), "Use up to \(limit) lighting layers.")
        try require(Set(layers.map(\.id)).count == layers.count, "Lighting layers must have unique identifiers.")
        for layer in layers { try layer.validate(allowedKeyIDs: allowedKeyIDs) }
    }
}

enum LayerRenderer {
    /// The UI lists topmost layers first. Compose bottom to top into a single
    /// framebuffer so adding layers never adds competing HID writers.
    static func frame(layers: [LightingLayer], keys: [KeyGeometry], mapping: MappingFile,
                      pulses: [KeyPulse], time: TimeInterval, heldKeys: Set<String> = [], toggledKeys: Set<String> = [],
                      inputs: LightingInputs = LightingInputs()) -> [RGB] {
        var result = Array(repeating: RGB.black, count: LightingRenderer.ledCount)
        let grouped = Dictionary(grouping: mapping.mappings.filter(\.confirmed), by: \.keyId)
        let indices = Dictionary(grouping: mapping.mappings.compactMap(\.ledIndex), by: { $0 })
        for layer in layers.reversed() where layer.enabled && layer.opacity > 0 {
            guard layer.keyIDs?.isEmpty != true else { continue }
            let opacity = layer.opacity.isFinite ? min(1, max(0, layer.opacity)) : 0
            // Trigger filtering belongs to each layer, so one layer's WASD
            // selection cannot consume or suppress another layer's key events.
            let layerPulses = layer.settings.effect.requiresKeyPresses ? pulses.filter { layer.acceptsTrigger($0.keyID) } : pulses
            let layerHeld = Set(heldKeys.filter(layer.acceptsTrigger))
            let layerToggled = Set(toggledKeys.filter(layer.acceptsTrigger))
            let colors = LightingRenderer.frame(settings: layer.settings, keys: keys, mapping: mapping,
                                                pulses: layerPulses, time: time, reactiveAffectsAllKeys: layer.affectAllKeys,
                                                heldKeys: layerHeld, toggledKeys: layerToggled, inputs: inputs)
            // The effect's white raster supplies coverage independent of its
            // chosen hue. Idle reactive pixels are transparent; static black is opaque.
            var coverageSettings = layer.settings
            coverageSettings.color = RGB(r: 255, g: 255, b: 255)
            // A rainbow's combined RGB channels do not measure its opacity.
            // Use the same ripple envelope in white, independent of hue overlap.
            if coverageSettings.effect == .rainbowRipple { coverageSettings.effect = .ripple }
            if coverageSettings.effect == .rainbowReactive { coverageSettings.effect = .reactive }
            let coverage = layer.settings.effect.usesSelectedColor || [.rainbowRipple, .rainbowReactive].contains(layer.settings.effect)
                ? LightingRenderer.frame(settings: coverageSettings, keys: keys, mapping: mapping,
                                         pulses: layerPulses, time: time, reactiveAffectsAllKeys: layer.affectAllKeys,
                                         heldKeys: layerHeld, toggledKeys: layerToggled, inputs: inputs)
                : colors
            let affectedKeyIDs = layer.affectAllKeys ? nil : layer.keyIDs
            let mask: Set<Int>? = affectedKeyIDs.map { ids in
                Set(ids.compactMap { id in
                    guard let entries = grouped[id], entries.count == 1, let index = entries[0].ledIndex,
                          (0..<LightingRenderer.ledCount).contains(index), indices[index]?.count == 1,
                          keys.contains(where: { $0.id == id }) else { return nil }
                    return index
                })
            }
            for index in result.indices where mask == nil || mask!.contains(index) {
                let alpha = Double(max(coverage[index].r, coverage[index].g, coverage[index].b)) / 255 * opacity
                let remaining = layer.blendMode == .normal ? 1 - alpha : 1
                func channel(_ below: UInt8, _ above: UInt8) -> UInt8 {
                    UInt8(min(255, max(0, (Double(below) * remaining + Double(above) * opacity).rounded())))
                }
                result[index] = RGB(r: channel(result[index].r, colors[index].r),
                                    g: channel(result[index].g, colors[index].g),
                                    b: channel(result[index].b, colors[index].b))
            }
        }
        return result
    }
}

enum LightingRenderer {
    static let ledCount = 104

    static func maximumPulseAge(settings: LightingSettings) -> TimeInterval {
        4.5 / settings.normalized.speed
    }

    /// A complete direct-RGB frame. Spatial effects use only unambiguous,
    /// confirmed LED mappings; unknown LEDs stay black. Brightness is a
    /// separate device setting so preview and transport share the same colors.
    static func frame(settings: LightingSettings, keys: [KeyGeometry], mapping: MappingFile,
                      pulses: [KeyPulse], time: TimeInterval, reactiveAffectsAllKeys: Bool = false,
                      heldKeys: Set<String> = [], toggledKeys: Set<String> = [], inputs: LightingInputs = LightingInputs()) -> [RGB] {
        let settings = settings.normalized
        var frame = Array(repeating: RGB.black, count: ledCount)
        if settings.intensity == 0 { return frame }
        let clock = time.isFinite ? time : 0

        switch settings.effect {
        case .staticColor:
            return Array(repeating: scale(settings.color, by: settings.intensity), count: ledCount)
        case .breathing:
            // Ease both ends of the breathing cycle and keep a faint idle glow.
            let phase = wrapped(clock, period: 3 / settings.speed)
            let breath = (1 - cos(phase * 2 * .pi)) / 2
            let level = 0.025 + 0.975 * breath * breath
            return Array(repeating: scale(settings.color, by: level * settings.intensity), count: ledCount)
        case .spectrum:
            let hue = wrapped(clock, period: 9 / settings.speed)
            return Array(repeating: hueColor(hue, level: settings.intensity), count: ledCount)
        case .cpuTemperature:
            guard let temperature = inputs.temperature(at: time) else { return frame }
            let fraction = min(1, max(0, (temperature - settings.temperatureCold) / (settings.temperatureHot - settings.temperatureCold)))
            return Array(repeating: hueColor((1 - fraction) * (2.0 / 3), level: settings.intensity), count: ledCount)
        case .ripple, .rainbowRipple, .reactive, .wave, .adaptiveMusic, .keyHold,
             .starlight, .rainbowStarlight, .fire, .colorWheel, .scanner, .comet, .rain, .aurora,
             .keyToggle, .rainbowReactive, .splash, .crossRipple, .rowWave, .columnWave, .matrixRain, .spacedMatrixRain, .matrixKeyRain:
            break
        }

        let mapped = confirmedKeys(keys: keys, mapping: mapping)
        if settings.effect == .spacedMatrixRain || settings.effect == .matrixKeyRain {
            let known = Set(mapped.map(\.id))
            let validPulses = pulses.filter { known.contains($0.keyID) }
            for key in mapped {
                frame[key.index] = settings.effect == .spacedMatrixRain
                    ? LogicalMatrixRaster.automatic(keyID: key.id, time: clock, settings: settings)
                    : LogicalMatrixRaster.reactive(keyID: key.id, time: clock, pulses: validPulses, settings: settings)
            }
            return frame
        }
        if settings.effect == .matrixRain {
            let ys = mapped.map { Int(($0.y * 2).rounded()) }
            guard let minY = ys.min(), let maxY = ys.max() else { return frame }
            for key in mapped {
                frame[key.index] = MatrixRainRaster.pixel(x: Int((key.x * 2).rounded()), y: Int((key.y * 2).rounded()),
                    minY: minY, maxY: maxY, time: clock, settings: settings)
            }
            return frame
        }
        if settings.effect == .keyHold || settings.effect == .keyToggle {
            let litKeys = settings.effect == .keyToggle ? toggledKeys : heldKeys
            guard mapped.contains(where: { litKeys.contains($0.id) }) else { return frame }
            for key in mapped where reactiveAffectsAllKeys || litKeys.contains(key.id) {
                frame[key.index] = scale(settings.color, by: settings.intensity)
            }
            return frame
        }
        if settings.effect == .adaptiveMusic {
            let audio = inputs.music.fresh(at: time)
            guard audio.level > 0, let minX = mapped.map(\.x).min(), let maxX = mapped.map(\.x).max(),
                  let minY = mapped.map(\.y).min(), let maxY = mapped.map(\.y).max() else { return frame }
            for key in mapped {
                let x = (key.x - minX) / max(1, maxX - minX)
                let height = (maxY - key.y) / max(1, maxY - minY)
                let band = x < 0.5 ? audio.bass * (1 - x * 2) + audio.mid * x * 2
                    : audio.mid * (2 - x * 2) + audio.treble * (x * 2 - 1)
                let level = min(1, band * settings.musicSensitivity)
                let bar = min(1, max(0, (level - height * 0.85) * 5))
                let glow = (0.08 * level + 0.92 * bar * level) * settings.intensity
                frame[key.index] = hueColor(x * 0.8 - wrapped(clock, period: 12 / settings.speed), level: glow)
            }
            return frame
        }
        if settings.effect == .wave {
            let phase = wrapped(clock, period: 5 / settings.speed)
            for key in mapped {
                // One hue cycle spans eight key units, tilted slightly diagonally.
                let hue = key.x / 8 + key.y * (0.35 / 8) - phase
                frame[key.index] = hueColor(hue, level: settings.intensity)
            }
            return frame
        }
        if [.starlight, .rainbowStarlight, .fire, .colorWheel, .scanner, .comet, .rain, .aurora].contains(settings.effect) {
            guard let minX = mapped.map(\.x).min(), let maxX = mapped.map(\.x).max(),
                  let minY = mapped.map(\.y).min(), let maxY = mapped.map(\.y).max() else { return frame }
            let spanX = max(1, maxX - minX), spanY = max(1, maxY - minY)
            let movement = wrapped(clock, period: 4 / settings.speed)
            for key in mapped {
                let x = (key.x - minX) / spanX, y = (key.y - minY) / spanY
                let color: RGB
                switch settings.effect {
                case .starlight, .rainbowStarlight:
                    let moment = wrapped(clock, period: 8 / settings.speed) * 8
                    let tick = Int(moment), progress = moment - Double(tick)
                    let seed = noise(Double(key.index) * 13.31 + Double(tick) * 71.9)
                    let glow = seed > 0.80 ? pow(sin(.pi * progress), 2) : 0
                    color = settings.effect == .starlight
                        ? scale(settings.color, by: glow * settings.intensity)
                        : hueColor(noise(Double(key.index) * 5.17 + Double(tick) * 3.77), level: glow * settings.intensity)
                case .fire:
                    let flicker = noise(Double(key.index) * 7.11 + floor(wrapped(clock, period: 16 / settings.speed) * 32) * 23.3)
                    let flame = max(0.08, 0.85 - y * 0.52 + flicker * 0.38)
                    color = hueColor(0.005 + (1 - y) * 0.09 + flicker * 0.025, level: flame * settings.intensity)
                case .colorWheel:
                    let angle = atan2(y - 0.5, x - 0.5) / (2 * .pi)
                    color = hueColor(angle + movement, level: settings.intensity)
                case .scanner:
                    let position = 1 - abs(2 * movement - 1)
                    let distance = abs(x - position)
                    color = scale(settings.color, by: exp(-distance * distance / 0.003) * settings.intensity)
                case .comet:
                    let head = movement * 1.3 - 0.15
                    let distance = head - x
                    let glow = distance < 0 ? exp(-pow(distance / 0.025, 2)) : exp(-distance / 0.12)
                    color = scale(settings.color, by: glow * settings.intensity)
                case .rain:
                    let column = floor(key.x * 1.6)
                    let offset = noise(column * 12.7)
                    let drop = wrapped(wrapped(clock, period: 3 / settings.speed) + offset, period: 1)
                    let distance = abs(y - drop)
                    let wrapDistance = min(distance, 1 - distance)
                    color = scale(settings.color, by: exp(-pow(wrapDistance / 0.10, 2)) * settings.intensity)
                case .aurora:
                    let fold = sin(x * 13 + movement * 2 * .pi * 2 + y * 3)
                    let band = exp(-pow((y - 0.48 - 0.22 * fold) / 0.28, 2))
                    color = hueColor(0.38 + 0.12 * sin(x * 6 - movement * 2 * .pi), level: (0.08 + 0.92 * band) * settings.intensity)
                default: color = .black
                }
                frame[key.index] = color
            }
            return frame
        }

        guard time.isFinite else { return frame }
        let origins = Dictionary(uniqueKeysWithValues: mapped.map { ($0.id, $0) })
        let active = pulses.compactMap { pulse -> (origin: MappedKey, age: Double, reach: Double)? in
            guard pulse.time.isFinite, let origin = origins[pulse.keyID] else { return nil }
            let age = (time - pulse.time) * settings.speed
            guard age.isFinite, age >= 0, age < 4.5 else { return nil }
            let reach = mapped.map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? 0
            return (origin, age, reach)
        }
        for key in mapped {
            var level = 0.0
            var rainbow = (r: 0.0, g: 0.0, b: 0.0)
            for pulse in active {
                if settings.effect == .reactive || settings.effect == .rainbowReactive {
                    guard (reactiveAffectsAllKeys || key.id == pulse.origin.id), pulse.age < 1.4 else { continue }
                    let remaining = 1 - pulse.age / 1.4
                    let contribution = remaining * remaining
                    level += contribution
                    if settings.effect == .rainbowReactive {
                        let color = hueColor(Double(pulse.origin.index) * 0.618 + pulse.age * 0.4, level: 1)
                        rainbow.r += Double(color.r) * contribution
                        rainbow.g += Double(color.g) * contribution
                        rainbow.b += Double(color.b) * contribution
                    }
                } else {
                    let dx = abs(key.x - pulse.origin.x), dy = abs(key.y - pulse.origin.y)
                    let distance: Double
                    let reach: Double
                    switch settings.effect {
                    case .rowWave: distance = dx; reach = mapped.map { abs($0.x - pulse.origin.x) }.max() ?? 0
                    case .columnWave: distance = dy; reach = mapped.map { abs($0.y - pulse.origin.y) }.max() ?? 0
                    case .crossRipple:
                        guard min(dx, dy) <= 0.75 else { continue }
                        distance = max(dx, dy); reach = mapped.map { max(abs($0.x - pulse.origin.x), abs($0.y - pulse.origin.y)) }.max() ?? 0
                    default: distance = hypot(dx, dy); reach = pulse.reach
                    }
                    let radius = pulse.age * (settings.effect == .splash ? 6 : 8)
                    // A soft ring expands from the actual key center; its width
                    // grows gently as it travels and the tail fades to zero.
                    let width = 0.6 + radius * 0.045
                    let offset = (settings.effect == .splash ? max(0, distance - radius) : distance - radius) / width
                    // Keep a visible ring through the farthest key. Hue wraps
                    // independently and never limits the wave's travel distance.
                    let travelFade = 1 - 0.2 * min(1, radius / max(1, reach))
                    let exitFade = max(0, 1 - max(0, radius - reach) / (width * 3))
                    let contribution = exp(-0.5 * offset * offset) * travelFade * exitFade * exitFade
                    level += contribution
                    if settings.effect == .rainbowRipple {
                        // Each ring contains a full spectrum around its origin;
                        // the colors rotate as it expands. Every press has its
                        // own origin and age, so overlapping rings mix smoothly.
                        let angle = atan2(key.y - pulse.origin.y, key.x - pulse.origin.x)
                        let color = hueColor(angle / (2 * .pi) + pulse.age * 0.4, level: 1)
                        rainbow.r += Double(color.r) * contribution
                        rainbow.g += Double(color.g) * contribution
                        rainbow.b += Double(color.b) * contribution
                    }
                }
            }
            // Overlapping key presses add light without wrapping color bytes.
            if settings.effect == .rainbowRipple || settings.effect == .rainbowReactive {
                // Keep the mixed hue when overlaps reach full brightness. The
                // frame stays premultiplied by the same coverage used by layers.
                let amount = settings.intensity / max(1, level)
                func byte(_ value: Double) -> UInt8 { UInt8(min(255, max(0, (value * amount).rounded()))) }
                frame[key.index] = RGB(r: byte(rainbow.r), g: byte(rainbow.g), b: byte(rainbow.b))
            } else {
                frame[key.index] = scale(settings.color, by: min(1, level) * settings.intensity)
            }
        }
        return frame
    }

    private struct MappedKey {
        let id: String
        let index: Int
        let x: Double
        let y: Double
    }

    private static func confirmedKeys(keys: [KeyGeometry], mapping: MappingFile) -> [MappedKey] {
        guard mapping.schemaVersion == 1, mapping.layoutId == "ansi-104", mapping.ledCount == ledCount else { return [] }
        let geometry = Dictionary(grouping: keys, by: \.id)
        let keyMappings = Dictionary(grouping: mapping.mappings, by: \.keyId)
        let ledMappings = Dictionary(grouping: mapping.mappings.compactMap(\.ledIndex), by: { $0 })
        return mapping.mappings.compactMap { entry in
            guard entry.confirmed, let index = entry.ledIndex,
                  (0..<ledCount).contains(index), ledMappings[index]?.count == 1,
                  keyMappings[entry.keyId]?.count == 1,
                  let candidates = geometry[entry.keyId], candidates.count == 1,
                  let key = candidates.first,
                  key.x.isFinite, key.y.isFinite, key.width.isFinite, key.height.isFinite,
                  key.width > 0, key.height > 0 else { return nil }
            let x = key.x + key.width / 2
            let y = key.y + key.height / 2
            guard x.isFinite, y.isFinite else { return nil }
            return MappedKey(id: key.id, index: index, x: x, y: y)
        }
    }

    private static func wrapped(_ time: Double, period: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: period) / period
        return phase < 0 ? phase + 1 : phase
    }

    private static func noise(_ seed: Double) -> Double {
        let value = sin(seed * 12.9898) * 43758.5453
        return value - floor(value)
    }

    private static func scale(_ color: RGB, by level: Double) -> RGB {
        let amount = level.isFinite ? min(1, max(0, level)) : 0
        return RGB(r: UInt8((Double(color.r) * amount).rounded()),
                   g: UInt8((Double(color.g) * amount).rounded()),
                   b: UInt8((Double(color.b) * amount).rounded()))
    }

    private static func hueColor(_ hue: Double, level: Double) -> RGB {
        let hue = hue - floor(hue)
        let sector = hue * 6
        let fraction = sector - floor(sector)
        let up = UInt8((fraction * 255).rounded())
        let down = UInt8(((1 - fraction) * 255).rounded())
        let color: RGB
        switch Int(sector) {
        case 0: color = RGB(r: 255, g: up, b: 0)
        case 1: color = RGB(r: down, g: 255, b: 0)
        case 2: color = RGB(r: 0, g: 255, b: up)
        case 3: color = RGB(r: 0, g: down, b: 255)
        case 4: color = RGB(r: up, g: 0, b: 255)
        default: color = RGB(r: 255, g: 0, b: down)
        }
        return scale(color, by: level)
    }
}
