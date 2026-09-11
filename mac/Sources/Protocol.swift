import Foundation

struct RGB: Equatable, Codable {
    var r: UInt8; var g: UInt8; var b: UInt8
    static let black = RGB(r: 0, g: 0, b: 0)
    var bytes: [UInt8] { [r, g, b] }
}
struct RGBState: Equatable {
    let index: Int; let color: RGB; let effect: Int; let brightness: Int; let checksum: UInt16
}
enum ControllerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
struct LightingVerificationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
private func verifyLighting(_ condition: Bool, _ message: String) throws {
    if !condition { throw LightingVerificationError(message: message) }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ControllerError.message(message) }
}
protocol ReportTransport: AnyObject {
    func exchange(_ payload: [UInt8]) throws -> [UInt8]
    func checkSingleDevice() throws
    func close()
}
final class RGBClient {
    let transport: ReportTransport
    private(set) var shadow: [RGB]?
    private(set) var indicatorOverrides = Set<Int>()
    private var animationSequence = 0
    init(_ transport: ReportTransport) { self.transport = transport }
    static let signature: [UInt8] = [8, 3, 5, 2, 104, 9, 15, 71, 77, 75, 2]
    // The exact v0.2 firmware retains the stock status-light tail. It can force
    // these four framebuffer slots to white (GP+13FE,1437,147F,14E5).
    // No other index or differing color is exempted from verification.
    static let indicatorIndices: Set<Int> = [14, 33, 57, 91]
    static func isIndicatorOverride(index: Int, actual: RGB, expected: RGB) -> Bool {
        actual != expected && indicatorIndices.contains(index) && actual == RGB(r: 255, g: 255, b: 255)
    }
    static func sum(_ frame: [RGB]) -> UInt16 {
        UInt16(truncatingIfNeeded: frame.reduce(0) { $0 + Int($1.r) + Int($1.g) + Int($1.b) })
    }
    static func parse(_ p: [UInt8], index: Int) throws -> RGBState {
        try require(p.count == 32, "Invalid HID response length; reconnect the keyboard.")
        try require(Array(p.prefix(11)) == signature, "Exact custom firmware v0.2 signature not found. Lighting controls are locked.")
        try require(Int(p[11]) == index, "The keyboard returned the wrong LED index.")
        try require(p[15] <= 19 && p[16] <= 4, "The keyboard returned invalid effect or brightness values.")
        return RGBState(index: index, color: RGB(r: p[12], g: p[13], b: p[14]), effect: Int(p[15]), brightness: Int(p[16]), checksum: UInt16(p[17]) | UInt16(p[18]) << 8)
    }
    func read(_ index: Int = 0) throws -> RGBState {
        try require((0..<104).contains(index), "LED index must be 0–103.")
        return try Self.parse(transport.exchange([8, 3, 5, UInt8(index)]), index: index)
    }
    func readFrame(expected: [RGB]? = nil) throws -> [RGB] {
        shadow = nil
        let first = try read()
        try verifyLighting(first.effect == 19, "A stable direct RGB frame is required.")
        var frame = [first.color]
        for index in 1..<104 {
            let s = try read(index)
            try verifyLighting(s.effect == 19 && s.brightness == first.brightness && s.checksum == first.checksum, "The lighting changed during readback. Try the lighting action again.")
            frame.append(s.color)
        }
        try verifyLighting(try read() == first, "The lighting was not stable during readback.")
        try verifyLighting(Self.sum(frame) == first.checksum, "The framebuffer checksum did not match the 104 LED samples.")
        if let expected {
            try require(expected.count == 104, "Expected frame must contain 104 colors.")
            var overrides = Set<Int>()
            for i in frame.indices where frame[i] != expected[i] {
                try verifyLighting(Self.isIndicatorOverride(index: i, actual: frame[i], expected: expected[i]),
                                   "LED \(i) did not match the requested color (received \(frame[i].bytes), expected \(expected[i].bytes)).")
                overrides.insert(i)
            }
            indicatorOverrides = overrides
        }
        shadow = frame
        return frame
    }
    private func gate(visible: Bool = false) throws -> RGBState {
        try transport.checkSingleDevice()
        let state = try read()
        try require(!visible || state.brightness > 0, "Brightness is zero. Apply brightness 1–4 before changing colors.")
        return state
    }
    private func sendFramePackets(_ frame: [RGB]) throws {
        shadow = nil
        for start in stride(from: 0, to: 104, by: 9) {
            let colors = Array(frame[start..<min(start + 9, 104)])
            _ = try transport.exchange([7, 3, 5, UInt8(start), UInt8(colors.count)] + colors.flatMap(\.bytes))
        }
    }
    private func sendFrame(_ frame: [RGB]) throws {
        try sendFramePackets(frame)
        _ = try readFrame(expected: frame)
    }
    /// Animation uses bounded sample/checksum checks between complete frame audits.
    /// Sampled frames never become a trusted shadow for a later per-key edit.
    func setAnimationFrame(_ frame: [RGB], fullVerification: Bool = false) throws -> RGBState {
        try require(frame.count == 104, "An animation frame requires exactly 104 colors.")
        let before = try gate(visible: true)
        try sendFramePackets(frame)
        if fullVerification || animationSequence % 30 == 0 || before.effect != 19 {
            _ = try readFrame(expected: frame)
        } else {
            let index = animationSequence % 104
            let indices = Self.indicatorIndices.union([index, (index + 52) % 104]).sorted()
            var verifiedFrame = frame
            var samples = [RGBState]()
            var overrides = Set<Int>()
            for i in indices {
                let sample = try read(i)
                let overridden = Self.isIndicatorOverride(index: i, actual: sample.color, expected: frame[i])
                try verifyLighting(sample.effect == 19 && sample.brightness == before.brightness &&
                                   (sample.color == frame[i] || overridden), "Animation LED \(i) did not match. Playback stopped.")
                if overridden { verifiedFrame[i] = sample.color; overrides.insert(i) }
                samples.append(sample)
            }
            try verifyLighting(samples.allSatisfy { $0.checksum == Self.sum(verifiedFrame) },
                               "Animation checksum did not match. Playback stopped.")
            try verifyLighting(try read(samples[0].index) == samples[0], "Animation frame changed during verification.")
            indicatorOverrides = overrides
        }
        animationSequence = (animationSequence + 1) % 3120
        shadow = nil
        let final = try read()
        var verifiedFrame = frame
        for i in indicatorOverrides { verifiedFrame[i] = RGB(r: 255, g: 255, b: 255) }
        try verifyLighting(final.effect == 19 && final.brightness == before.brightness &&
                    final.color == frame[0] && final.checksum == Self.sum(verifiedFrame),
                    "Animation frame changed before completion. Playback stopped.")
        return final
    }
    func setFrame(_ frame: [RGB]) throws {
        try require(frame.count == 104, "A full frame requires exactly 104 colors.")
        _ = try gate(visible: true)
        try sendFrame(frame)
    }
    func setLED(_ index: Int, color: RGB) throws {
        try require((0..<104).contains(index), "LED index must be 0–103.")
        let state = try gate(visible: true)
        // Read every LED before a partial update; an additive checksum alone can collide.
        if state.effect == 19 { _ = try readFrame() }
        guard var desired = shadow else { throw ControllerError.message("Choose Set all keys first to establish a complete direct RGB frame.") }
        desired[index] = color
        if state.effect != 19 { try sendFrame(desired); return }
        shadow = nil
        _ = try transport.exchange([7, 3, 5, UInt8(index), 1] + color.bytes)
        _ = try readFrame(expected: desired)
    }
    func clear() throws {
        _ = try gate()
        shadow = nil
        _ = try transport.exchange([7, 3, 5, 0, 0])
        _ = try readFrame(expected: Array(repeating: .black, count: 104))
    }
    func brightness(_ value: Int) throws {
        try require((0...4).contains(value), "Brightness must be 0–4.")
        _ = try gate()
        _ = try transport.exchange([7, 3, 1, UInt8(value)])
        try require(try read().brightness == value, "Brightness readback did not match.")
    }
    func effect(_ value: Int) throws {
        try require((0...18).contains(value), "Built-in effect must be 0–18.")
        _ = try gate()
        _ = try transport.exchange([7, 3, 2, UInt8(value)])
        try require(try read().effect == value, "Effect readback did not match.")
    }
}
