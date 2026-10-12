import Foundation

/// Bounded, versioned lighting profile for a future on-keyboard renderer.
/// Encoding is offline only; the current v0.6 firmware does not accept it.
struct OnboardProfile {
    static let magic: [UInt8] = Array("GMKP".utf8)
    static let version: UInt8 = 1
    static let headerSize = 32
    // Reserve the last 32 bytes of a 4 KB flash sector for the journal's
    // generation and commit record. Profile bytes alone never occupy it.
    static let maximumSize = 4096 - 32
    static let keyCount = 104
    static let keyMaskBytes = 13
    static let effectIDs: [LightingEffect] = [
        .ripple, .rainbowRipple, .reactive, .wave, .breathing,
        .spectrum, .staticColor, .adaptiveMusic, .cpuTemperature,
        .keyHold, .starlight, .rainbowStarlight, .fire, .colorWheel,
        .scanner, .comet, .rain, .aurora, .keyToggle, .rainbowReactive, .splash, .crossRipple, .rowWave, .columnWave, .matrixRain, .spacedMatrixRain, .matrixKeyRain
    ]

    let bytes: [UInt8]
    var needsMacAudio: Bool { bytes[20] & 1 != 0 }
    var needsMacTemperature: Bool { bytes[20] & 2 != 0 }
    var maximumEffectID: Int {
        guard bytes[5] == 0 else { return 0 }
        var offset = Self.headerSize + 104 + 208
        var highest = 0
        for _ in 0..<bytes[6] {
            highest = max(highest, Int(bytes[offset]))
            offset += 57 + Int(bytes[offset + 56])
        }
        return highest
    }

    static func compile(_ profile: LightingProfile, keys: [KeyGeometry],
                        mapping: MappingFile, factoryMapping: MappingFile) throws -> Self {
        try profile.validate()
        try mapping.validate(keys: keys)
        try factoryMapping.validate(keys: keys)
        try require(keys.count == keyCount && Set(keys.map(\.id)).count == keyCount,
                    "The keyboard layout must contain 104 unique keys.")
        try require(mapping.mappings.allSatisfy { $0.confirmed && $0.ledIndex != nil } &&
                    factoryMapping.mappings.allSatisfy { $0.confirmed && $0.ledIndex != nil },
                    "Map and confirm all 104 keys before preparing an on-keyboard profile.")
        let layout = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0) })
        let output = Dictionary(uniqueKeysWithValues: mapping.mappings.map { ($0.keyId, $0.ledIndex!) })
        let scan = Dictionary(uniqueKeysWithValues: factoryMapping.mappings.map { ($0.keyId, $0.ledIndex!) })

        var scanToOutput = [UInt8](repeating: 255, count: keyCount)
        var geometry = [UInt8](repeating: 0, count: keyCount * 2)
        for (id, scanIndex) in scan {
            guard let led = output[id], let key = layout[id] else {
                throw ControllerError.message("The key mapping and layout do not match.")
            }
            try require(key.x.isFinite && key.y.isFinite && key.width.isFinite && key.height.isFinite &&
                        key.width > 0 && key.height > 0,
                        "The keyboard geometry contains an invalid key.")
            let x = ((key.x + key.width / 2) * 2).rounded()
            let y = ((key.y + key.height / 2) * 2).rounded()
            try require((0...127).contains(x) && (0...127).contains(y),
                        "A key position is outside the supported keyboard area.")
            scanToOutput[scanIndex] = UInt8(led)
            geometry[led * 2] = UInt8(x)
            geometry[led * 2 + 1] = UInt8(y)
        }
        try require(Set(scanToOutput) == Set(UInt8(0)..<UInt8(keyCount)),
                    "Every physical key must map to one unique LED.")

        // Keep the wire protocol's one-layer minimum. An empty editable draft
        // becomes a disabled black layer, and therefore clears every LED.
        let draftLayers = profile.mode == .studio ? profile.studioLayers : []
        let layers = profile.mode == .studio && draftLayers.isEmpty ? [LightingLayer.emptyCanvas] : draftLayers
        try LightingLayer.validate(layers.isEmpty ? [LightingLayer()] : layers, allowedKeyIDs: Set(layout.keys))
        let mode: UInt8 = profile.mode == .studio ? 0 : profile.mode == .builtIn ? 1 : 2
        var payload = scanToOutput + geometry
        if profile.mode == .frame {
            guard let colors = profile.colors, colors.count == keyCount else {
                throw ControllerError.message("A manual color layout must have 104 colors.")
            }
            payload += colors.flatMap(\.bytes)
        }
        var sensorFlags: UInt8 = 0
        if profile.mode == .studio {
            try require((1...LightingLayer.limit).contains(layers.count), "The on-keyboard profile needs 1–16 layers.")
            for layer in layers {
                guard let effectID = effectIDs.firstIndex(of: layer.settings.effect) else {
                    throw ControllerError.message("This lighting effect is not supported by the on-keyboard profile format.")
                }
                let name = Array(layer.name.utf8)
                try require(name.count <= 80, "On-keyboard layer names must fit in 80 UTF-8 bytes.")
                if layer.enabled && layer.opacity > 0 {
                    if layer.settings.effect == .adaptiveMusic { sensorFlags |= 1 }
                    if layer.settings.effect == .cpuTemperature { sensorFlags |= 2 }
                }
                var flags: UInt8 = layer.enabled ? 1 : 0
                if layer.affectAllKeys { flags |= 2 }
                if layer.blendMode == .additive { flags |= 4 }
                if layer.keyIDs == nil { flags |= 8 }
                let selected = layer.keyIDs.map(Set.init) ?? Set(layout.keys)
                let trigger = mask(selected.compactMap { scan[$0] })
                // Lighting Studio treats an explicit empty selection as an
                // inactive layer, even when affectAllKeys is enabled.
                let visible = selected.isEmpty ? Set<Int>() :
                    layer.affectAllKeys ? Set(0..<keyCount) : Set(selected.compactMap { output[$0] })
                let outputMask = mask(visible)
                var uuid = layer.id.uuid
                let uuidBytes = withUnsafeBytes(of: &uuid) { Array($0) }
                payload += [UInt8(effectID), flags]
                payload += little16(quantize(layer.settings.speed, scale: 256))
                payload += [quantize8(layer.settings.intensity), quantize8(layer.opacity), UInt8(layer.settings.brightness)]
                payload += layer.settings.color.bytes
                payload += little16(quantize(layer.settings.musicSensitivity, scale: 256))
                payload += [UInt8(layer.settings.temperatureCold.rounded()), UInt8(layer.settings.temperatureHot.rounded())]
                payload += trigger + outputMask + uuidBytes + [UInt8(name.count)] + name
            }
        }
        let length = headerSize + payload.count
        try require(length <= maximumSize, "The on-keyboard profile exceeds its 4 KB storage slot.")
        var header = [UInt8](repeating: 0, count: headerSize)
        header.replaceSubrange(0..<4, with: magic)
        header[4] = version; header[5] = mode; header[6] = UInt8(layers.count)
        header[7] = UInt8(profile.builtInEffect)
        header.replaceSubrange(8..<10, with: little16(length))
        header[10] = UInt8(profile.settings.brightness)
        header[11] = UInt8(profile.frameRate ?? 60)
        header.replaceSubrange(16..<20, with: Array("A104".utf8))
        header[20] = sensorFlags
        let crc = crc32(payload)
        header.replaceSubrange(12..<16, with: little32(crc))
        let result = Self(bytes: header + payload)
        try result.validate()
        return result
    }

    func validate() throws {
        try require((OnboardProfile.headerSize...OnboardProfile.maximumSize).contains(bytes.count),
                    "Invalid on-keyboard profile length.")
        try require(Array(bytes[0..<4]) == Self.magic && bytes[4] == Self.version &&
                    Array(bytes[16..<20]) == Array("A104".utf8) &&
                    Int(bytes[8]) | (Int(bytes[9]) << 8) == bytes.count,
                    "Unsupported or truncated on-keyboard profile.")
        try require(bytes[5] <= 2 && bytes[6] <= LightingLayer.limit &&
                    (bytes[5] == 0 ? bytes[6] > 0 : bytes[6] == 0) &&
                    bytes[7] <= 20 && bytes[7] != 19 && bytes[10] <= 4 && [15, 30, 60, 90, 120].contains(Int(bytes[11])) &&
                    bytes[20] & ~UInt8(3) == 0 && bytes[21..<32].allSatisfy { $0 == 0 },
                    "Invalid on-keyboard profile header.")
        try require(bytes.count >= Self.headerSize + 104 + 208,
                    "The on-keyboard profile is missing its key map.")
        let payload = Array(bytes[Self.headerSize...])
        let expected = UInt32(bytes[12]) | UInt32(bytes[13]) << 8 | UInt32(bytes[14]) << 16 | UInt32(bytes[15]) << 24
        try require(Self.crc32(payload) == expected, "The on-keyboard profile checksum does not match.")
        let scanToOutput = Array(payload[0..<104])
        try require(Set(scanToOutput) == Set(UInt8(0)..<UInt8(Self.keyCount)),
                    "The on-keyboard key-to-LED map is not a permutation.")
        try require(payload[104..<312].allSatisfy { $0 < 128 },
                    "The on-keyboard key positions are out of range.")
        if bytes[5] != 0 {
            try require(bytes[20] == 0, "A built-in or manual profile cannot require Mac sensors.")
        }
        if bytes[5] == 2 {
            try require(payload.count == 104 + 208 + 312, "The manual color layout has the wrong size.")
        } else if bytes[5] == 1 {
            try require(payload.count == 104 + 208, "The built-in layout has trailing data.")
        } else {
            var at = 312
            var ids = Set<UUID>()
            var derivedSensorFlags: UInt8 = 0
            for _ in 0..<bytes[6] {
                try require(at + 57 <= payload.count, "An on-keyboard layer is truncated.")
                try require(Int(payload[at]) < Self.effectIDs.count && payload[at + 1] & ~UInt8(15) == 0,
                            "An on-keyboard layer has an unknown effect or flag.")
                let speed = Int(payload[at + 2]) | Int(payload[at + 3]) << 8
                let music = Int(payload[at + 10]) | Int(payload[at + 11]) << 8
                try require((64...768).contains(speed) && (64...1024).contains(music) &&
                            payload[at + 6] <= 4 && (10...80).contains(Int(payload[at + 12])) &&
                            (40...110).contains(Int(payload[at + 13])) &&
                            Int(payload[at + 13]) - Int(payload[at + 12]) >= 5,
                            "An on-keyboard layer has invalid settings.")
                let trigger = Array(payload[at + 14..<at + 27])
                let outputMask = Array(payload[at + 27..<at + 40])
                let allMask = [UInt8](repeating: 255, count: Self.keyMaskBytes)
                if payload[at + 1] & 8 != 0 {
                    try require(trigger == allMask, "The all-key trigger flag does not match its key mask.")
                }
                let expectedOutput: [UInt8]
                if trigger.allSatisfy({ $0 == 0 }) { expectedOutput = [UInt8](repeating: 0, count: Self.keyMaskBytes) }
                else if payload[at + 1] & 2 != 0 { expectedOutput = allMask }
                else {
                    expectedOutput = Self.mask((0..<Self.keyCount).compactMap { scan in
                        trigger[scan / 8] & UInt8(1 << (scan % 8)) != 0 ? Int(scanToOutput[scan]) : nil
                    })
                }
                try require(outputMask == expectedOutput,
                            "The output key mask does not match the physical key mapping.")
                if payload[at + 1] & 1 != 0 && payload[at + 5] > 0 {
                    if payload[at] == 7 { derivedSensorFlags |= 1 }
                    if payload[at] == 8 { derivedSensorFlags |= 2 }
                }
                let uuidStart = at + 40
                let idBytes = Array(payload[uuidStart..<uuidStart + 16])
                let id = UUID(uuid: (idBytes[0], idBytes[1], idBytes[2], idBytes[3], idBytes[4], idBytes[5],
                                     idBytes[6], idBytes[7], idBytes[8], idBytes[9], idBytes[10], idBytes[11],
                                     idBytes[12], idBytes[13], idBytes[14], idBytes[15]))
                try require(ids.insert(id).inserted, "The on-keyboard profile repeats a layer ID.")
                let nameLength = Int(payload[at + 56])
                let name = at + 57 + nameLength <= payload.count && nameLength > 0
                    ? String(bytes: payload[at + 57..<at + 57 + nameLength], encoding: .utf8) : nil
                try require(nameLength <= 80 && name != nil &&
                            !name!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            "An on-keyboard layer name is invalid.")
                at += 57 + nameLength
            }
            try require(at == payload.count, "The on-keyboard profile has trailing data.")
            try require(bytes[20] == derivedSensorFlags,
                        "The on-keyboard sensor requirements do not match its layers.")
        }
    }

    private static func mask<S: Sequence>(_ indices: S) -> [UInt8] where S.Element == Int {
        var result = [UInt8](repeating: 0, count: keyMaskBytes)
        for index in indices where (0..<keyCount).contains(index) {
            result[index / 8] |= UInt8(1 << (index % 8))
        }
        return result
    }
    private static func quantize8(_ value: Double) -> UInt8 { UInt8((value * 255).rounded()) }
    private static func quantize(_ value: Double, scale: Double) -> Int { Int((value * scale).rounded()) }
    private static func little16(_ value: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)] }
    private static func little32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc = UInt32.max
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
        }
        return ~crc
    }
}
