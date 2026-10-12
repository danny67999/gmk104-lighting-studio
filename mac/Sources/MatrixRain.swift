import Foundation

/// Matches the bounded integer firmware raster; no random state or key events.
enum MatrixRainRaster {
    private static func noise(_ seed: UInt32) -> Int {
        var s = seed
        s ^= s >> 16; s = s &* 0x7feb352d
        s ^= s >> 15; s = s &* 0x846ca68b
        s ^= s >> 16
        return Int(s >> 24)
    }
    private static func mul(_ a: Int, _ b: Int) -> Int { (a * b + 127) / 255 }
    static func pixel(x: Int, y: Int, minY: Int, maxY: Int, time: Double, settings: LightingSettings) -> RGB {
        let wrap = 4294967296.0
        let seconds = time.isFinite ? time : 0
        var milliseconds = (seconds.truncatingRemainder(dividingBy: wrap / 1000) * 1000).rounded(.down)
        if milliseconds < 0 { milliseconds += wrap }
        let t = UInt32(milliseconds), column = max(0, x) / 2
        let rows = max(0, maxY - minY) / 2 + 1, speed = Int((settings.speed * 256).rounded())
        let period = UInt32(1800 * 256 / speed)
        let phase = Int(UInt64(t % period) * 65536 / UInt64(period)), cycle = t / period
        let offset = column == 0 ? 0 : noise(UInt32(column * 811)) * 257
        let head = (phase - offset) & 65535, row = max(0, y - minY) / 2
        let position = row * 65536 / rows, distance = (head - position) & 65535
        guard !(cycle == 0 && phase < offset) else { return .black }
        guard !((cycle == 0 || (cycle == 1 && phase < offset)) && position > head) else { return .black }
        guard distance < 49152 else { return .black }
        let white: Int, glow: Int
        if distance < 8192 {
            white = 255 - distance * 255 / 8192
            glow = 255 - distance * 32 / 8192
        } else {
            white = 0
            glow = 220 * (49152 - distance) / 40960
        }
        let coverage = mul(glow, Int((settings.intensity * 255).rounded()))
        func channel(_ value: UInt8) -> UInt8 { UInt8(mul(Int(value) + mul(255 - Int(value), white), coverage)) }
        return RGB(r: channel(settings.color.r), g: channel(settings.color.g), b: channel(settings.color.b))
    }
}
