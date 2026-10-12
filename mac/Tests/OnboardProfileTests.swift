import Foundation

@main struct OnboardProfileTests {
    static func rejects(_ description: String, _ body: () throws -> Void) {
        do { try body(); fatalError("Expected rejection: \(description)") }
        catch { print("PASS: \(description)") }
    }

    static func main() throws {
        let keys = try JSONDecoder().decode([KeyGeometry].self,
                                            from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/layout.json")))
        let factory = try JSONDecoder().decode(MappingFile.self,
                                               from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/default-led-map.json")))
        try factory.validate(keys: keys)
        var layers = [LightingLayer]()
        for (index, effect) in OnboardProfile.effectIDs.prefix(9).enumerated() {
            var settings = LightingSettings(effect: effect, color: RGB(r: UInt8(index * 20), g: 72, b: 183),
                                            speed: 0.25 + Double(index) * 0.2, intensity: 0.8, brightness: 3)
            settings.musicSensitivity = 1.75
            settings.temperatureCold = 40
            settings.temperatureHot = 90
            var layer = LightingLayer(name: "Layer \(index) · \(effect.displayName)", settings: settings)
            layer.id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", index + 1))!
            layer.opacity = Double(index + 1) / 10
            layer.blendMode = index.isMultiple(of: 2) ? .additive : .normal
            layer.affectAllKeys = index.isMultiple(of: 3)
            layer.keyIDs = index.isMultiple(of: 2) ? ["KeyW", "KeyA", "KeyS", "KeyD"] : nil
            layers.append(layer)
        }
        for index in layers.count..<LightingLayer.limit {
            var extra = layers[0]
            extra.id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", index + 1))!
            extra.name = "Extra \(layers.count)"
            layers.append(extra)
        }
        var profile = LightingProfile(mode: .studio, settings: layers[0].settings, layers: layers, frameRate: 120)
        let binary = try OnboardProfile.compile(profile, keys: keys, mapping: factory, factoryMapping: factory)
        assert(binary.bytes.count < 4096 && binary.bytes[6] == 16 && binary.needsMacAudio && binary.needsMacTemperature)
        assert(Array(binary.bytes[32..<136]) == Array(0..<104).map(UInt8.init))
        let firstSpeedOffset = OnboardProfile.headerSize + 104 + 208 + 2
        let secondSpeedOffset = firstSpeedOffset + 57 + layers[0].name.utf8.count
        assert(binary.bytes[firstSpeedOffset] == 64 && binary.bytes[firstSpeedOffset + 1] == 0)
        assert(binary.bytes[secondSpeedOffset] == 115 && binary.bytes[secondSpeedOffset + 1] == 0,
               "Each layer must encode its own animation speed")
        try binary.validate()
        let fixtureURL = URL(fileURLWithPath: "mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin")
        if CommandLine.arguments.contains("--emit-fixture") {
            try FileManager.default.createDirectory(at: fixtureURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(binary.bytes).write(to: fixtureURL, options: .atomic)
        }
        let fixture = try Data(contentsOf: fixtureURL)
        assert(fixture == Data(binary.bytes), "Cross-platform profile fixture changed unexpectedly.")
        print("PASS: all nine Lighting Studio effects, sixteen layers, masks, names, settings and sensor flags compile into \(binary.bytes.count) bytes")

        var reactiveLayers = [LightingLayer]()
        for (index, effect) in OnboardProfile.effectIDs.dropFirst(18).prefix(6).enumerated() {
            var layer = layers[0]; layer.id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", index + 1))!
            layer.name = "Reactive \(index)"; layer.settings.effect = effect
            reactiveLayers.append(layer)
        }
        let reactiveProfile = LightingProfile(mode: .studio, settings: layers[0].settings, layers: reactiveLayers, frameRate: 60)
        let reactiveBinary = try OnboardProfile.compile(reactiveProfile, keys: keys, mapping: factory, factoryMapping: factory)
        let reactiveURL = URL(fileURLWithPath: "mac/Tests/Fixtures/onboard-profile-reactive-v1.2.bin")
        if CommandLine.arguments.contains("--emit-reactive-fixture") { try Data(reactiveBinary.bytes).write(to: reactiveURL, options: .atomic) }
        let reactiveGolden = try Data(contentsOf: reactiveURL)
        assert(reactiveGolden == Data(reactiveBinary.bytes))
        assert(reactiveBinary.maximumEffectID == 23 && !reactiveBinary.needsMacAudio && !reactiveBinary.needsMacTemperature)
        print("PASS: six native reactive effect IDs match the cross-platform golden profile")

        var matrixLayer = layers[0]
        matrixLayer.name = "Matrix rain"; matrixLayer.keyIDs = nil; matrixLayer.affectAllKeys = false
        matrixLayer.opacity = 1; matrixLayer.blendMode = .normal
        matrixLayer.settings = LightingSettings(effect: .matrixRain, color: RGB(r: 0, g: 255, b: 32))
        let matrixProfile = LightingProfile(mode: .studio, settings: matrixLayer.settings, layers: [matrixLayer], frameRate: 60)
        let matrixBinary = try OnboardProfile.compile(matrixProfile, keys: keys, mapping: factory, factoryMapping: factory)
        let matrixURL = URL(fileURLWithPath: "mac/Tests/Fixtures/onboard-profile-matrix-v1.3.bin")
        if CommandLine.arguments.contains("--emit-matrix-fixture") { try Data(matrixBinary.bytes).write(to: matrixURL, options: .atomic) }
        let savedMatrix = try Data(contentsOf: matrixURL)
        assert(savedMatrix == Data(matrixBinary.bytes))
        assert(matrixBinary.maximumEffectID == 24 && !matrixBinary.needsMacAudio && !matrixBinary.needsMacTemperature)
        print("PASS: Matrix rain uses stable effect ID24 and a portable persistent layer profile")

        // Trigger W/A/S/D while drawing across all keys remains separate in
        // the encoded record, even when the LED mapping is rearranged.
        var swapped = factory
        swapped.assign(key: "KeyW", index: 59)
        swapped.assign(key: "KeyS", index: 39)
        try swapped.validate(keys: keys)
        profile.layers = [layers[0]]
        for effect: LightingEffect in [.keyHold, .starlight, .rainbowStarlight, .fire,
                                       .colorWheel, .scanner, .comet, .rain, .aurora, .keyToggle, .rainbowReactive, .splash, .crossRipple, .rowWave, .columnWave] {
            var extended = layers[0]
            extended.settings.effect = effect
            profile.layers = [extended]
            let encoded = try OnboardProfile.compile(profile, keys: keys, mapping: factory, factoryMapping: factory)
            try encoded.validate()
            assert(encoded.bytes[344] == UInt8(OnboardProfile.effectIDs.firstIndex(of: effect)!))
        }
        print("PASS: fifteen extended effect IDs compile into valid versioned on-keyboard profiles")
        profile.layers = [layers[0]]
        let remapped = try OnboardProfile.compile(profile, keys: keys, mapping: swapped, factoryMapping: factory)
        let firstLayer = OnboardProfile.headerSize + 104 + 208
        let factoryW = factory.mappings.first { $0.keyId == "KeyW" }!.ledIndex!
        assert(remapped.bytes[32 + factoryW] == 59)
        assert(remapped.bytes[firstLayer + 14 + factoryW / 8] & UInt8(1 << (factoryW % 8)) != 0)
        assert(remapped.bytes[firstLayer + 27 + 59 / 8] & UInt8(1 << (59 % 8)) != 0)
        print("PASS: physical trigger mapping and custom LED output mapping remain independent")

        var empty = layers[0]
        empty.keyIDs = []
        empty.affectAllKeys = true
        profile.layers = [empty]
        let inactive = try OnboardProfile.compile(profile, keys: keys, mapping: factory, factoryMapping: factory)
        assert(inactive.bytes[(firstLayer + 14)..<(firstLayer + 40)].allSatisfy { $0 == 0 })
        print("PASS: an empty per-key selection stays inactive when affect-all-keys is enabled")

        empty.name = String(repeating: "🎨", count: 21) // 84 UTF-8 bytes, 21 characters.
        profile.layers = [empty]
        rejects("on-keyboard layer names must fit their encoded field") {
            _ = try OnboardProfile.compile(profile, keys: keys, mapping: factory, factoryMapping: factory)
        }
        profile.layers = [layers[0]]

        let colors = (0..<104).map { RGB(r: UInt8($0), g: UInt8(103 - $0), b: 40) }
        let manual = LightingProfile(mode: .frame, settings: LightingSettings(), colors: colors)
        let frame = try OnboardProfile.compile(manual, keys: keys, mapping: factory, factoryMapping: factory)
        assert(frame.bytes.count == 32 + 104 + 208 + 312 && frame.bytes[5] == 2)
        assert(Array(frame.bytes.suffix(312)) == colors.flatMap(\.bytes))
        let builtIn = LightingProfile(mode: .builtIn, settings: LightingSettings(), builtInEffect: 20)
        let native = try OnboardProfile.compile(builtIn, keys: keys, mapping: factory, factoryMapping: factory)
        assert(native.bytes[5] == 1 && native.bytes[7] == 20)
        var invalidBuiltIn = native.bytes; invalidBuiltIn[20] = 1
        rejects("built-in mode cannot claim a music sensor layer") {
            try OnboardProfile(bytes: invalidBuiltIn).validate()
        }
        print("PASS: manual 104-key colors and built-in modes compile without losing their mode")

        var broken = binary.bytes; broken[400] ^= 1
        rejects("single-bit corruption is caught by the profile checksum") { try OnboardProfile(bytes: broken).validate() }
        broken = binary.bytes; broken[8] = 0
        rejects("truncated or altered length is rejected") { try OnboardProfile(bytes: broken).validate() }
        var partial = factory; partial.mappings[0].confirmed = false
        rejects("unconfirmed key mappings cannot silently upload") {
            _ = try OnboardProfile.compile(profile, keys: keys, mapping: partial, factoryMapping: factory)
        }
        print("All offline on-keyboard profile encoding checks passed; v0.6 has no upload handler.")
    }
}
