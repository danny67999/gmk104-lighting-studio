import Foundation

@main struct LightingInputsTests {
    static func main() throws {
        let keys = try JSONDecoder().decode([KeyGeometry].self, from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/layout.json")))
        let map = try JSONDecoder().decode(MappingFile.self, from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/default-led-map.json")))
        func peak(_ rgb: RGB) -> Int { Int(max(rgb.r, rgb.g, rgb.b)) }
        for effect in [LightingEffect.ripple, .rainbowRipple] {
            for originID in ["Escape", "KeyA", "NumpadEnter"] {
                let origin = keys.first { $0.id == originID }!
                for speed in [0.25, 1, 3] {
                    let settings = LightingSettings(effect: effect, color: RGB(r: 255, g: 255, b: 255), speed: speed)
                    var layer = LightingLayer(settings: settings); layer.keyIDs = [originID]; layer.affectAllKeys = true
                    let pulse = [KeyPulse(keyID: originID, time: 100)]
                    for key in keys {
                        let distance = hypot(key.x + key.width / 2 - origin.x - origin.width / 2,
                                             key.y + key.height / 2 - origin.y - origin.height / 2)
                        let time = 100 + distance / (8 * speed)
                        let frame = LayerRenderer.frame(layers: [layer], keys: keys, mapping: map, pulses: pulse, time: time)
                        let index = map.mappings.first { $0.keyId == key.id }!.ledIndex!
                        assert(peak(frame[index]) >= 200, "\(effect) from \(originID) failed at \(key.id), speed \(speed)")
                    }
                    let expired = LayerRenderer.frame(layers: [layer], keys: keys, mapping: map, pulses: pulse, time: 100 + 4.5 / speed)
                    assert(expired.allSatisfy { $0 == .black })
                    let ignored = LayerRenderer.frame(layers: [layer], keys: keys, mapping: map, pulses: [KeyPulse(keyID: originID == "Escape" ? "KeyA" : "Escape", time: 100)], time: 100)
                    assert(ignored.allSatisfy { $0 == .black })
                }
            }
        }
        print("PASS: both ripple types visibly reach all 104 keys from both keyboard edges and WASD at every speed, retain trigger masks, then expire")

        var analyzer = MusicAnalyzer()
        func tone(_ frequency: Double, amplitude: Double, block: Int) -> [Float] {
            (0..<1024).map { Float(sin(Double(block * 1024 + $0) * 2 * .pi * frequency / 48_000) * amplitude) }
        }
        var levels = MusicLevels()
        for i in 0..<100 { levels = analyzer.process(tone(80, amplitude: 0.03, block: i), sampleRate: 48_000, time: Double(i) * 1024 / 48_000) }
        assert(levels.level > 0.7 && levels.bass > levels.treble * 2)
        var treble = MusicAnalyzer()
        for i in 0..<100 { levels = treble.process(tone(8000, amplitude: 0.3, block: i), sampleRate: 48_000, time: Double(i) * 1024 / 48_000) }
        assert(levels.level > 0.7 && levels.treble > levels.bass * 2)
        for i in 0..<100 { levels = treble.process([Float](repeating: 0, count: 1024), sampleRate: 48_000, time: 3 + Double(i) * 1024 / 48_000) }
        assert(levels.level == 0 && levels.bass == 0 && levels.mid == 0 && levels.treble == 0)
        assert(treble.process([.nan, .infinity], sampleRate: 48_000, time: 10).level == 0)
        assert(levels.fresh(at: 30).level == 0)
        print("PASS: adaptive music follows real low/high frequency input, handles changing volume, silence, invalid samples and stale capture")

        var inputs = LightingInputs()
        inputs.music = MusicLevels(bass: 0.9, mid: 0.6, treble: 0.3, level: 0.8, timestamp: 100)
        var music = LightingLayer(settings: LightingSettings(effect: .adaptiveMusic)); music.keyIDs = ["KeyA"]
        let lit = LayerRenderer.frame(layers: [music], keys: keys, mapping: map, pulses: [], time: 100.1, inputs: inputs)
        assert(lit.filter { $0 != .black }.count <= 1)
        music.affectAllKeys = true
        let all = LayerRenderer.frame(layers: [music], keys: keys, mapping: map, pulses: [], time: 100.1, inputs: inputs)
        assert(all.filter { $0 != .black }.count > 50)
        let stale = LayerRenderer.frame(layers: [music], keys: keys, mapping: map, pulses: [], time: 101, inputs: inputs)
        assert(stale.allSatisfy { $0 == .black })
        print("PASS: music respects per-layer selected keys and whole-keyboard coverage; stale audio cannot leave a frozen effect")

        var settings = LightingSettings(effect: .cpuTemperature)
        func temperature(_ value: Double?, time: Double = 100) -> [RGB] {
            inputs.cpuCelsius = value; inputs.temperatureTimestamp = 100
            return LightingRenderer.frame(settings: settings, keys: keys, mapping: map, pulses: [], time: time, inputs: inputs)
        }
        assert(temperature(40).allSatisfy { $0 == RGB(r: 0, g: 0, b: 255) })
        assert(temperature(65).allSatisfy { $0 == RGB(r: 0, g: 255, b: 0) })
        assert(temperature(90).allSatisfy { $0 == RGB(r: 255, g: 0, b: 0) })
        for value: Double? in [nil, .nan, .infinity, -1, 200] { assert(temperature(value).allSatisfy { $0 == .black }) }
        assert(temperature(65, time: 106).allSatisfy { $0 == .black })
        settings.temperatureCold = 30; settings.temperatureHot = 80; settings.musicSensitivity = 2.5
        let roundtrip = try JSONDecoder().decode(LightingSettings.self, from: JSONEncoder().encode(settings))
        assert(roundtrip == settings)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        for name in ["temperatureCold", "temperatureHot", "musicSensitivity"] { legacy.removeValue(forKey: name) }
        let migrated = try JSONDecoder().decode(LightingSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(migrated.temperatureCold == 40 && migrated.temperatureHot == 90 && migrated.musicSensitivity == 1)
        print("PASS: CPU colors use real Celsius, reject stale/invalid data, and preserve old profiles with default sensor settings")
    }
}
