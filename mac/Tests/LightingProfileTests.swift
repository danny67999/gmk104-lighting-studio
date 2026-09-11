import Foundation

@main struct LightingProfileTests {
    static func main() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("mac/.build/lighting-profile-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/lighting-profile.json")
        let missing = try LightingProfile.load(from: url)
        assert(missing == nil)
        print("PASS: missing profile returns nil without creating a file")

        let colors = (0..<104).map { RGB(r: UInt8($0), g: UInt8(255 - $0), b: UInt8($0 * 2)) }
        let settings = LightingSettings(effect: .ripple, color: RGB(r: 30, g: 160, b: 240),
                                        speed: 1.75, intensity: 0.6, brightness: 4)
        var expected = LightingProfile(mode: .studio, settings: settings)
        for mode in [LightingProfileMode.studio, .builtIn, .frame] {
            for restore in [false, true] {
                for resume in [false, true] {
                    expected = LightingProfile(mode: mode, settings: settings, builtInEffect: 18,
                                               colors: mode == .frame ? colors : nil,
                                               restoreOnReconnect: restore, resume: resume)
                    try expected.save(to: url)
                    guard let actual = try LightingProfile.load(from: url) else {
                        fatalError("Saved profile was not loaded")
                    }
                    assert(actual.version == expected.version && actual.mode == expected.mode)
                    assert(actual.settings == expected.settings && actual.builtInEffect == expected.builtInEffect)
                    assert(actual.colors == expected.colors)
                    assert(actual.restoreOnReconnect == restore && actual.resume == resume)
                }
            }
        }
        print("PASS: studio, built-in and frame profiles preserve settings, colors and both restore/resume flags")

        let validData = try Data(contentsOf: url)
        var invalid = expected
        invalid.version = 3
        try rejects("unknown profile version on save") { try invalid.save(to: url) }
        assert(tryRead(url) == validData)
        try rejectsFile(invalid, at: url, label: "unknown profile version on load")

        for badSpeed in [0.0, 3.01] {
            invalid = expected; invalid.settings.speed = badSpeed
            try rejectsFile(invalid, at: url, label: "invalid saved effect speed")
        }
        for badIntensity in [-0.01, 1.01] {
            invalid = expected; invalid.settings.intensity = badIntensity
            try rejectsFile(invalid, at: url, label: "invalid saved effect intensity")
        }
        for badBrightness in [-1, 5] {
            invalid = expected; invalid.settings.brightness = badBrightness
            try rejectsFile(invalid, at: url, label: "invalid saved brightness")
        }
        for badEffect in [-1, 19] {
            invalid = expected; invalid.builtInEffect = badEffect
            try rejectsFile(invalid, at: url, label: "invalid saved built-in effect")
        }

        for count in [0, 103, 105] {
            invalid = expected; invalid.mode = .frame
            invalid.colors = Array(repeating: .black, count: count)
            try rejectsFile(invalid, at: url, label: "saved frame with \(count) LEDs")
        }
        invalid = expected; invalid.mode = .frame; invalid.colors = nil
        try rejectsFile(invalid, at: url, label: "saved frame without colors")

        var bottom = LightingLayer(name: "Background", settings: LightingSettings(effect: .staticColor))
        bottom.enabled = false
        var top = LightingLayer(name: "WASD ripple", settings: settings)
        top.opacity = 0.65; top.blendMode = .additive; top.keyIDs = ["KeyW", "KeyA", "KeyS", "KeyD"]
        top.affectAllKeys = true
        let layered = LightingProfile(mode: .studio, settings: settings, layers: [top, bottom])
        try layered.save(to: url)
        let reloadedLayers = try LightingProfile.load(from: url)?.layers
        assert(reloadedLayers == layered.layers)
        assert(reloadedLayers?[0].affectAllKeys == true && reloadedLayers?[1].affectAllKeys == false)
        print("PASS: layer identities, trigger selections, reach, settings and order survive a file roundtrip")
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(layered)) as! [String: Any]
        var oldLayers = oldJSON["layers"] as! [[String: Any]]
        for index in oldLayers.indices { oldLayers[index].removeValue(forKey: "affectAllKeys") }
        oldJSON["layers"] = oldLayers
        let oldBytes = try JSONSerialization.data(withJSONObject: oldJSON)
        try oldBytes.write(to: url, options: .atomic)
        let oldProfile = try LightingProfile.load(from: url)!
        assert(oldProfile.layers?.allSatisfy { !$0.affectAllKeys } == true)
        assert(oldProfile.layers?[0].keyIDs == top.keyIDs && oldProfile.layers?[0].id == top.id)
        let unchanged = try Data(contentsOf: url)
        assert(unchanged == oldBytes)
        print("PASS: existing layer profiles default to selected-key reach without changing saved triggers or rewriting files")
        var rainbowLayer = top; rainbowLayer.settings.effect = .rainbowRipple
        let rainbow = LightingProfile(mode: .studio, settings: rainbowLayer.settings, layers: [rainbowLayer, bottom])
        try rainbow.save(to: url)
        let savedRainbow = try LightingProfile.load(from: url)!
        assert(savedRainbow.layers == rainbow.layers && savedRainbow.settings.effect == .rainbowRipple)
        print("PASS: Rainbow ripple saves and reloads with its trigger keys, reach, speed and layer order intact")
        invalid = layered; invalid.layers = []
        try rejectsFile(invalid, at: url, label: "empty layer stack")
        invalid = layered; invalid.layers = [top, top]
        try rejectsFile(invalid, at: url, label: "duplicate layer identifiers")
        invalid = layered; invalid.layers![0].opacity = 1.1
        try rejectsFile(invalid, at: url, label: "invalid layer opacity")
        invalid = layered; invalid.layers![0].keyIDs = ["KeyW", "KeyW"]
        try rejectsFile(invalid, at: url, label: "duplicate selected keys")
        invalid = layered; invalid.layers = (0...LightingLayer.limit).map { _ in LightingLayer() }
        try rejectsFile(invalid, at: url, label: "too many layers")

        var legacy = layered; legacy.version = 1; legacy.layers = nil
        try JSONEncoder().encode(legacy).write(to: url, options: .atomic)
        let legacyBytes = try Data(contentsOf: url)
        let migrated = try LightingProfile.load(from: url)!
        assert(migrated.studioLayers.count == 1 && migrated.studioLayers[0].settings == settings)
        assert(migrated.studioLayers == migrated.studioLayers)
        let unchangedLegacy = try Data(contentsOf: url)
        assert(unchangedLegacy == legacyBytes)
        print("PASS: version 1 effects load as one stable layer without rewriting the original profile")

        try Data("{\"version\":".utf8).write(to: url, options: .atomic)
        try rejects("truncated saved JSON") { _ = try LightingProfile.load(from: url) }
        print("All lighting profile persistence checks passed.")
    }

    private static func rejectsFile(_ profile: LightingProfile, at url: URL, label: String) throws {
        try rejects("\(label) rejected before save") { try profile.save(to: url) }
        // Encode directly to simulate a malformed or hand-edited on-disk profile.
        try JSONEncoder().encode(profile).write(to: url, options: .atomic)
        try rejects("\(label) rejected on load") { _ = try LightingProfile.load(from: url) }
    }

    private static func tryRead(_ url: URL) -> Data? { try? Data(contentsOf: url) }

    private static func rejects(_ label: String, _ action: () throws -> Void) throws {
        do { try action() } catch { print("PASS: \(label)"); return }
        fatalError("Expected rejection: \(label)")
    }
}
