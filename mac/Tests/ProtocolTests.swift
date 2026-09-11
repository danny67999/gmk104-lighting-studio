import Foundation
final class MockTransport: ReportTransport {
    var frame = Array(repeating: RGB.black, count: 104)
    var brightness = 3; var effect = 1; var writes = [[UInt8]]()
    var reads = [Int]()
    var firmwareColors: [Int: RGB] = [:]
    var badSignature = false; var multiple = false; var corruptIndex: Int?; var wrongIndex = false
    func checkSingleDevice() throws { try require(!multiple, "Multiple devices") }
    func close() {}
    func exchange(_ p: [UInt8]) throws -> [UInt8] {
        if p[0] == 7 {
            writes.append(p)
            if p[2] == 1 { brightness = Int(p[3]) }
            if p[2] == 2 { effect = Int(p[3]) }
            if p[2] == 5 {
                if effect != 19 || p[4] == 0 { frame = Array(repeating: .black, count: 104) }
                effect = 19
                for i in 0..<Int(p[4]) { frame[Int(p[3]) + i] = RGB(r: p[5 + i*3], g: p[6 + i*3], b: p[7 + i*3]) }
            }
            return p + Array(repeating: 0, count: 32-p.count)
        }
        for (index, color) in firmwareColors { frame[index] = color }
        let index = Int(p[3]); reads.append(index)
        let c = frame[index]; let sum = RGBClient.sum(frame)
        var r = RGBClient.signature + [UInt8(index), c.r, c.g, c.b, UInt8(effect), UInt8(brightness), UInt8(sum & 255), UInt8(sum >> 8)]
        r += Array(repeating: 0, count: 32-r.count)
        if badSignature { r[10] = 1 }
        if wrongIndex { r[11] = 255 }
        if index == corruptIndex { r[12] ^= 1 }
        return r
    }
}
func rejects(_ label: String, _ action: () throws -> Void) throws {
    do { try action() } catch { print("PASS: \(label)"); return }
    fatalError("Expected rejection: \(label)")
}
@main struct Tests {
    static func main() throws {
        let t = MockTransport(); let c = RGBClient(t)
        _ = try c.read(); assert(t.writes.isEmpty)
        print("PASS: startup/read sends no lighting writes")
        t.badSignature = true
        try rejects("v0.1 signature blocks writes") { try c.brightness(4) }; assert(t.writes.isEmpty)
        t.badSignature = false; t.multiple = true
        try rejects("multiple devices block writes") { try c.clear() }; assert(t.writes.isEmpty)
        t.multiple = false; t.wrongIndex = true
        try rejects("invalid indexed response") { _ = try c.read() }
        t.wrongIndex = false
        try rejects("partial update without known frame") { try c.setLED(0, color: RGB(r: 2, g: 3, b: 4)) }; assert(t.writes.isEmpty)
        t.brightness = 0
        try rejects("zero brightness blocks RGB") { try c.setFrame(Array(repeating: .black, count: 104)) }; assert(t.writes.isEmpty)
        t.brightness = 3
        let base = Array(repeating: RGB(r: 7, g: 11, b: 13), count: 104)
        try c.setFrame(base); assert(t.writes.count == 12 && t.writes.last?[4] == 5 && c.shadow == base)
        print("PASS: full frame uses 12 bounded batches and verifies every sample")
        try c.effect(3)
        try c.setLED(0, color: RGB(r: 20, g: 0, b: 0))
        assert(t.frame[1] == base[1] && t.frame[0].r == 20 && t.effect == 19)
        print("PASS: partial update restores full frame after built-in effect")
        // Same-checksum external edit must not be overwritten from a stale cache.
        t.frame[4] = RGB(r: 8, g: 10, b: 13)
        try c.setLED(0, color: .black); assert(t.frame[4] == RGB(r: 8, g: 10, b: 13))
        print("PASS: checksum-collision external change preserved")
        t.corruptIndex = 57
        try rejects("bad indexed color rejected") { _ = try c.readFrame() }; assert(c.shadow == nil)
        t.corruptIndex = nil
        try c.clear(); assert(t.frame.allSatisfy { $0 == .black })
        try c.brightness(4); assert(t.brightness == 4)
        try rejects("short report rejected") { _ = try RGBClient.parse([8,3,5], index: 0) }
        let animationTransport = MockTransport(); let animation = RGBClient(animationTransport)
        _ = try animation.setAnimationFrame(base)
        assert(animationTransport.reads.count == 107 && animation.shadow == nil)
        animationTransport.reads = []
        _ = try animation.setAnimationFrame(base)
        assert(animationTransport.reads == [0, 1, 14, 33, 53, 57, 91, 1, 0] && animation.shadow == nil)
        print("PASS: animation begins with full audit, then rotates samples without trusting partial shadow")
        animationTransport.corruptIndex = 2
        try rejects("animation corrupt sample stops playback") { _ = try animation.setAnimationFrame(base) }
        animationTransport.corruptIndex = 57
        try rejects("periodic full animation audit rejects corruption outside sampled LEDs") {
            _ = try animation.setAnimationFrame(base, fullVerification: true)
        }
        animationTransport.corruptIndex = nil; animationTransport.multiple = true
        let priorWrites = animationTransport.writes.count
        try rejects("animation still blocks multiple devices") { _ = try animation.setAnimationFrame(base) }
        assert(animationTransport.writes.count == priorWrites)
        let indicators = MockTransport(), indicatorClient = RGBClient(indicators)
        let white = RGB(r: 255, g: 255, b: 255)
        indicators.firmwareColors = Dictionary(uniqueKeysWithValues: RGBClient.indicatorIndices.map { ($0, white) })
        try indicatorClient.setFrame(base)
        assert(indicatorClient.indicatorOverrides == RGBClient.indicatorIndices)
        assert(indicatorClient.shadow?[57] == white)
        _ = try indicatorClient.setAnimationFrame(base)
        _ = try indicatorClient.setAnimationFrame(base)
        assert(indicatorClient.indicatorOverrides == RGBClient.indicatorIndices)
        try indicatorClient.clear()
        assert(indicatorClient.shadow?.enumerated().allSatisfy { RGBClient.indicatorIndices.contains($0.offset) ? $0.element == white : $0.element == .black } == true)
        print("PASS: exact firmware status-white overlays verify for static frames, clear and sampled animation")
        indicators.firmwareColors[57] = RGB(r: 1, g: 2, b: 3)
        try rejects("non-white indicator corruption is rejected") { try indicatorClient.setFrame(base) }
        indicators.firmwareColors[57] = white; indicators.firmwareColors[58] = white
        try rejects("white corruption outside the four firmware slots is rejected") { try indicatorClient.setFrame(base) }
        let keys = try JSONDecoder().decode([KeyGeometry].self, from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/layout.json")))
        var map = try JSONDecoder().decode(MappingFile.self, from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/default-led-map.json")))
        try map.validate(keys: keys); assert(keys.count == 104)
        let preset = try MappingFile.rowOrder(keys: keys)
        func led(_ key: String) -> Int? { preset.mappings.first { $0.keyId == key }?.ledIndex }
        assert(led("Escape") == 0 && led("F1") == 1 && led("Pause") == 15)
        assert(led("Backquote") == 16 && led("NumLock") == 33 && led("Tab") == 37)
        assert(led("CapsLock") == 57 && led("NumpadAdd") == 73 && led("ShiftLeft") == 74)
        assert(led("ControlLeft") == 90 && led("MetaLeft") == 91 && led("NumpadEnter") == 103)
        assert(preset.mappings.allSatisfy { m in map.mappings.contains { $0.keyId == m.keyId && $0.ledIndex == m.ledIndex && $0.confirmed } })
        print("PASS: all 104 bundled row mappings match, including row boundaries and tall numpad keys")
        map.assign(key: "KeyA", index: 0); try map.validate(keys: keys)
        assert(map.mappings.first { $0.keyId == "Escape" }?.ledIndex == nil)
        map.mappings[0].ledIndex = 0
        try rejects("duplicate mapping rejected") { try map.validate(keys: keys) }
        print("All protocol and mapping checks passed.")
    }
}
