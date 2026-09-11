import Foundation

@main struct LightingEffectsTests {
    static func main() throws {
        let keys = [key("A", x: 0), key("B", x: 2), key("C", x: 6), key("Unknown", x: 1)]
        var mapping = MappingFile(schemaVersion: 1, layoutId: "ansi-104", ledCount: 104, mappings: [
            KeyMapping(keyId: "A", ledIndex: 7, confirmed: true),
            KeyMapping(keyId: "B", ledIndex: 42, confirmed: true),
            KeyMapping(keyId: "C", ledIndex: 103, confirmed: true),
            KeyMapping(keyId: "Unknown", ledIndex: 8, confirmed: false)
        ])
        let color = RGB(r: 255, g: 80, b: 40)
        var settings = LightingSettings(effect: .ripple, color: color)
        let pulses = [KeyPulse(keyID: "A", time: 10)]
        func frame(_ time: Double, _ inputs: [KeyPulse]? = nil) -> [RGB] {
            LightingRenderer.frame(settings: settings, keys: keys, mapping: mapping, pulses: inputs ?? pulses, time: time)
        }

        let start = frame(10)
        assert(start.count == 104 && start[7] == color && start[42].r < 5)
        let expanding = frame(10.25)
        assert(expanding[42].r > 200 && expanding[7].r < 10 && expanding[103] == .black)
        let farther = frame(10.75)
        assert(farther[103].r > 120 && farther[7] == .black)
        assert(frame(13.5).allSatisfy { $0 == .black })
        assert(start[8] == .black && expanding[8] == .black && farther[8] == .black)
        print("PASS: ripple moves outward through confirmed physical centers and fades")

        assert(frame(10, [KeyPulse(keyID: "Unknown", time: 10)]).allSatisfy { $0 == .black })
        assert(frame(9).allSatisfy { $0 == .black })
        assert(frame(.infinity).allSatisfy { $0 == .black })
        assert(frame(10, [KeyPulse(keyID: "A", time: .nan)]).allSatisfy { $0 == .black })
        print("PASS: unconfirmed, future and nonfinite key events do not invent lighting")

        let two = [KeyPulse(keyID: "A", time: 10), KeyPulse(keyID: "A", time: 10)]
        assert(frame(10, two)[7] == color)
        assert(frame(10.25, two)[42].r > expanding[42].r)
        settings.speed = 2
        assert(frame(10.125) == expanding)
        settings.speed = 1
        print("PASS: overlapping pulses add without overflow and speed scales propagation")

        settings.effect = .reactive
        assert(frame(10)[7] == color && frame(10)[42] == .black)
        assert(frame(10.7)[7].r == 64 && frame(11.4).allSatisfy { $0 == .black })
        assert(frame(10.7, two)[7].r == 128)
        print("PASS: reactive lights only the pressed mapped key and decays smoothly")

        settings.effect = .wave
        let wave = frame(1)
        assert(wave[7] != wave[42] && wave[42] != wave[103])
        assert(wave[7] != frame(2)[7] && wave[8] == .black)
        mapping.mappings.append(KeyMapping(keyId: "Duplicate", ledIndex: 7, confirmed: true))
        assert(frame(1)[7] == .black)
        mapping.mappings.removeLast()
        mapping.mappings.append(KeyMapping(keyId: "A", ledIndex: 9, confirmed: true))
        assert(frame(1)[7] == .black && frame(1)[9] == .black)
        mapping.mappings.removeLast()
        print("PASS: rainbow wave follows geometry and skips ambiguous mappings")

        for effect in LightingEffect.allCases {
            settings.effect = effect
            assert(frame(0).count == 104)
            assert(frame(Double.greatestFiniteMagnitude).count == 104)
            settings.intensity = 0
            assert(frame(1).allSatisfy { $0 == .black })
            settings.intensity = 1
        }
        settings.effect = .staticColor
        settings.intensity = 0.5
        assert(frame(0).allSatisfy { $0 == RGB(r: 128, g: 40, b: 20) })
        settings.brightness = 1
        let dimHardware = frame(0)
        settings.brightness = 4
        assert(frame(0) == dimHardware)
        settings.intensity = 1
        settings.effect = .breathing
        assert(frame(0)[0].r < frame(1.5)[0].r && frame(1.5)[0] == color)
        settings.effect = .spectrum
        assert(frame(0)[0] != frame(3)[0])
        assert(Set(frame(3).map { "\($0.r),\($0.g),\($0.b)" }).count == 1)
        print("PASS: every effect produces a complete bounded frame; whole-key effects need no mapping")

        let valid = LightingSettings()
        try valid.validate()
        let restored = try JSONDecoder().decode(LightingSettings.self, from: JSONEncoder().encode(valid))
        assert(restored == valid)
        for speed in [0.0, 4, .nan, .infinity] {
            var bad = valid; bad.speed = speed
            try rejects { try bad.validate() }
            assert((0.25...3).contains(bad.normalized.speed))
        }
        for intensity in [-0.1, 1.1, .nan, .infinity] {
            var bad = valid; bad.intensity = intensity
            try rejects { try bad.validate() }
            assert((0...1).contains(bad.normalized.intensity))
        }
        for brightness in [-1, 5, Int.max] {
            var bad = valid; bad.brightness = brightness
            try rejects { try bad.validate() }
            assert((0...4).contains(bad.normalized.brightness))
        }
        print("PASS: saved settings round trip and reject invalid ranges and nonfinite values")
        try layerComposition()
        try layerTriggerReach()
        try rainbowRipple()
        print("All lighting renderer checks passed.")
    }

    static func layerComposition() throws {
        let keys = [key("A", x: 0), key("B", x: 2)]
        let mapping = MappingFile(schemaVersion: 1, layoutId: "ansi-104", ledCount: 104, mappings: [
            KeyMapping(keyId: "A", ledIndex: 7, confirmed: true), KeyMapping(keyId: "B", ledIndex: 42, confirmed: true)
        ])
        let red = RGB(r: 240, g: 0, b: 0), blue = RGB(r: 0, g: 0, b: 200)
        let background = LightingLayer(settings: LightingSettings(effect: .staticColor, color: blue))
        var top = LightingLayer(settings: LightingSettings(effect: .staticColor, color: red))
        func render(_ layers: [LightingLayer], time: Double = 10, pulses: [KeyPulse] = []) -> [RGB] {
            LayerRenderer.frame(layers: layers, keys: keys, mapping: mapping, pulses: pulses, time: time)
        }
        assert(render([top, background]).allSatisfy { $0 == red })
        assert(render([background, top]).allSatisfy { $0 == blue })
        top.opacity = 0.5
        assert(render([top, background])[7] == RGB(r: 120, g: 0, b: 100))
        top.blendMode = .additive
        assert(render([top, background])[7] == RGB(r: 120, g: 0, b: 200))
        top.opacity = 1; top.settings.color = RGB(r: 240, g: 0, b: 200)
        assert(render([top, background])[7] == RGB(r: 240, g: 0, b: 255))
        top.enabled = false
        assert(render([top, background]) == render([background]))
        top.enabled = true; top.blendMode = .normal; top.settings.color = .black
        assert(render([top, background]).allSatisfy { $0 == .black })
        print("PASS: layer order, opacity, additive clipping, visibility and opaque black compose correctly")

        top.settings.color = red; top.keyIDs = ["A"]
        assert(render([top, background])[7] == red && render([top, background])[42] == blue)
        assert(render([top, background])[0] == blue)
        top.keyIDs = []
        assert(render([top, background]) == render([background]))
        top.keyIDs = ["Missing"]
        assert(render([top, background]) == render([background]))
        try rejects { try top.validate(allowedKeyIDs: Set(keys.map(\.id))) }
        print("PASS: selected-key masks preserve the background and never guess missing mappings")

        top.keyIDs = nil; top.settings.effect = .reactive
        let pulse = [KeyPulse(keyID: "A", time: 10)]
        assert(render([top, background]) == render([background]))
        assert(render([top, background], pulses: pulse)[7] == red)
        assert(render([top, background], pulses: pulse)[42] == blue)
        let fading = render([top, background], time: 10.7, pulses: pulse)[7]
        assert(fading.r == 60 && fading.b == 150)
        assert(render([top, background], time: 11.5, pulses: pulse) == render([background]))
        top.settings.effect = .ripple
        assert(render([top, background], time: 10.25, pulses: pulse)[42].r > 190)
        var second = top; second.id = UUID(); second.settings.speed = 2; second.settings.color = blue; second.blendMode = .additive
        let together = render([second, top], time: 10.125, pulses: pulse)
        assert(together[42].b > 150 && together[7].r > 0)
        print("PASS: idle and fading reactive layers reveal the background; simultaneous ripples keep independent speeds")

        for effect in LightingEffect.allCases {
            top.settings.effect = effect
            assert(render([top], pulses: pulse) == LightingRenderer.frame(settings: top.settings, keys: keys, mapping: mapping, pulses: pulse, time: 10))
        }
        print("PASS: a migrated single layer preserves every existing effect's rendered colors")
    }

    static func key(_ id: String, x: Double) -> KeyGeometry {
        KeyGeometry(id: id, label: id, x: x, y: 0, width: 1, height: 1)
    }
    static func rainbowRipple() throws {
        let keys = [key("Origin", x: 0), key("East", x: 2), key("West", x: -2),
                    KeyGeometry(id: "North", label: "N", x: 0, y: -2, width: 1, height: 1),
                    KeyGeometry(id: "South", label: "S", x: 0, y: 2, width: 1, height: 1),
                    key("Far", x: 6)]
        let mapping = MappingFile(schemaVersion: 1, layoutId: "ansi-104", ledCount: 104,
                                  mappings: keys.enumerated().map { KeyMapping(keyId: $0.element.id, ledIndex: $0.offset, confirmed: true) })
        var settings = LightingSettings(effect: .rainbowRipple)
        let pulse = [KeyPulse(keyID: "Origin", time: 10)]
        func frame(_ time: Double, pulses: [KeyPulse]? = nil) -> [RGB] {
            LightingRenderer.frame(settings: settings, keys: keys, mapping: mapping, pulses: pulses ?? pulse, time: time)
        }
        func peak(_ color: RGB) -> UInt8 { max(color.r, color.g, color.b) }
        assert(settings.effect.requiresKeyPresses && settings.effect.requiresMapping && !settings.effect.usesSelectedColor)
        assert(frame(10)[0] == RGB(r: 255, g: 0, b: 0))
        assert(frame(10)[1...4].allSatisfy { peak($0) < 5 })
        let ring = frame(10.25)
        assert(ring[1...4].allSatisfy { peak($0) > 200 })
        assert(Set(ring[1...4].map { "\($0.r),\($0.g),\($0.b)" }).count == 4)
        assert(peak(ring[0]) < 10 && ring[5] == .black)
        assert(peak(frame(10.75)[5]) > 120)
        assert(frame(13.5).allSatisfy { $0 == .black })
        assert(frame(10.25, pulses: []).allSatisfy { $0 == .black })
        assert(frame(9).allSatisfy { $0 == .black })
        assert(frame(.infinity).allSatisfy { $0 == .black })
        assert(frame(10, pulses: [KeyPulse(keyID: "Unknown", time: 10)]).allSatisfy { $0 == .black })
        print("PASS: Rainbow ripple has simultaneous distinct hues around an expanding ring and fades fully")

        settings.speed = 2
        assert(frame(10.125) == ring)
        settings.speed = 1; settings.color = RGB(r: 0, g: 0, b: 0)
        assert(frame(10.25) == ring)
        let many = frame(10.25, pulses: Array(repeating: pulse[0], count: 48))
        assert(many[1].r == 255 && many[1].g > 0 && many[1].b == 0)
        let other = KeyPulse(keyID: "East", time: 10.1)
        let mixed = frame(10.25, pulses: pulse + [other])
        assert(mixed == frame(10.25, pulses: [other] + pulse))
        print("PASS: Rainbow ripple keeps independent speed, ignores fixed color and mixes overlapping presses without overflow")

        let blue = RGB(r: 0, g: 0, b: 180)
        let background = LightingLayer(settings: LightingSettings(effect: .staticColor, color: blue))
        var layer = LightingLayer(settings: settings); layer.keyIDs = ["Origin"]; layer.affectAllKeys = true
        func composed(_ inputs: [KeyPulse]) -> [RGB] {
            LayerRenderer.frame(layers: [layer, background], keys: keys, mapping: mapping, pulses: inputs, time: 10.25)
        }
        let reach = composed(pulse)
        assert(reach[1].r > 200 && reach[5] == blue)
        assert(composed([KeyPulse(keyID: "East", time: 10)]).allSatisfy { $0 == blue })
        // The background contribution must follow the white ripple envelope,
        // even when overlaps mix different hues with lower channel maxima.
        layer.keyIDs = nil
        let inputs = pulse + [other]
        let rgb = frame(10.25, pulses: inputs)
        var white = settings; white.effect = .ripple; white.color = RGB(r: 255, g: 255, b: 255)
        let coverage = LightingRenderer.frame(settings: white, keys: keys, mapping: mapping, pulses: inputs, time: 10.25)
        let result = composed(inputs)
        for i in result.indices {
            let expectedBlue = UInt8(min(255, (Double(blue.b) * (1 - Double(coverage[i].r) / 255) + Double(rgb[i].b)).rounded()))
            assert(result[i] == RGB(r: rgb[i].r, g: rgb[i].g, b: expectedBlue))
        }
        layer.keyIDs = ["Origin"]; layer.affectAllKeys = false
        assert(composed(pulse)[1] == blue)
        print("PASS: Rainbow ripple preserves per-layer triggers, reach and correct transparent blending over a background")
    }
    static func layerTriggerReach() throws {
        let keys = [key("A", x: 0), key("B", x: 2), key("C", x: 6)]
        let mapping = MappingFile(schemaVersion: 1, layoutId: "ansi-104", ledCount: 104, mappings: [
            KeyMapping(keyId: "A", ledIndex: 7, confirmed: true),
            KeyMapping(keyId: "B", ledIndex: 42, confirmed: true),
            KeyMapping(keyId: "C", ledIndex: 103, confirmed: true)
        ])
        let red = RGB(r: 240, g: 0, b: 0), blue = RGB(r: 0, g: 0, b: 200)
        let background = LightingLayer(settings: LightingSettings(effect: .staticColor, color: blue))
        var ripple = LightingLayer(settings: LightingSettings(effect: .ripple, color: red))
        ripple.keyIDs = ["A"]
        let pressA = [KeyPulse(keyID: "A", time: 10)], pressB = [KeyPulse(keyID: "B", time: 10)]
        func render(_ layer: LightingLayer, pulses: [KeyPulse], time: Double = 10.25) -> [RGB] {
            LayerRenderer.frame(layers: [layer, background], keys: keys, mapping: mapping, pulses: pulses, time: time)
        }
        assert(render(ripple, pulses: pressA)[42] == blue)
        assert(render(ripple, pulses: pressB).allSatisfy { $0 == blue })
        ripple.affectAllKeys = true
        assert(render(ripple, pulses: pressA)[42].r > 190)
        assert(render(ripple, pulses: pressA, time: 10.75)[103].r > 120)
        assert(render(ripple, pulses: pressB).allSatisfy { $0 == blue })
        assert(render(ripple, pulses: pressA + pressB) == render(ripple, pulses: pressA))
        assert(ripple.keyIDs == ["A"])
        print("PASS: Affect all keys expands ripple reach without admitting unselected trigger keys or dimming the background")

        var second = ripple; second.id = UUID(); second.keyIDs = ["B"]
        second.settings.color = RGB(r: 0, g: 240, b: 0); second.blendMode = .additive
        let onlyA = LayerRenderer.frame(layers: [second, ripple], keys: keys, mapping: mapping, pulses: pressA, time: 10.25)
        let onlyB = LayerRenderer.frame(layers: [second, ripple], keys: keys, mapping: mapping, pulses: pressB, time: 10.25)
        assert(onlyA[42].r > 190 && onlyA.allSatisfy { $0.g == 0 })
        assert(onlyB[7].g > 190 && onlyB.allSatisfy { $0.r == 0 })
        print("PASS: each layer independently filters its own trigger keys")

        ripple.keyIDs = []
        assert(render(ripple, pulses: pressA + pressB).allSatisfy { $0 == blue })
        ripple.keyIDs = nil
        assert(render(ripple, pulses: pressB)[7].r > 190)
        ripple.keyIDs = ["Missing"]
        assert(render(ripple, pulses: [KeyPulse(keyID: "Missing", time: 10)]).allSatisfy { $0 == blue })
        print("PASS: empty and unmapped triggers remain inactive; All permits every mapped key")

        ripple.keyIDs = ["A"]; ripple.settings.effect = .reactive
        let flash = render(ripple, pulses: pressA, time: 10)
        assert([7, 42, 103].allSatisfy { flash[$0] == red })
        assert(flash[0] == blue)
        assert(render(ripple, pulses: pressB, time: 10).allSatisfy { $0 == blue })
        assert(render(ripple, pulses: pressA, time: 10.7)[42] == RGB(r: 60, g: 0, b: 150))
        ripple.affectAllKeys = false
        assert(render(ripple, pulses: pressA, time: 10)[42] == blue)
        ripple.settings.effect = .staticColor; ripple.affectAllKeys = true
        assert(render(ripple, pulses: []).allSatisfy { $0 == red })
        ripple.affectAllKeys = false
        assert(render(ripple, pulses: [])[42] == blue)
        print("PASS: Reactive can flash all mapped keys; continuous effects can expand coverage without changing the selection")
    }
    static func rejects(_ action: () throws -> Void) throws {
        do { try action() } catch { return }
        fatalError("Expected invalid settings to be rejected")
    }
}
