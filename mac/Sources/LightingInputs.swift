import Foundation

struct MusicLevels: Equatable {
    var bass = 0.0
    var mid = 0.0
    var treble = 0.0
    var level = 0.0
    var timestamp: TimeInterval = -.infinity

    func fresh(at time: TimeInterval) -> Self {
        guard time.isFinite, timestamp.isFinite, time >= timestamp, time - timestamp < 0.5 else { return Self() }
        func bounded(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        return Self(bass: bounded(bass), mid: bounded(mid), treble: bounded(treble),
                    level: bounded(level), timestamp: timestamp)
    }
}
struct LightingInputs: Equatable {
    var music = MusicLevels()
    var musicStatus = "Mac audio is stopped"
    var audioRunning = false
    var cpuCelsius: Double?
    var temperatureTimestamp: TimeInterval = -.infinity
    var temperatureStatus = "CPU temperature is stopped"

    func temperature(at time: TimeInterval) -> Double? {
        guard let value = cpuCelsius, value.isFinite, (1...125).contains(value),
              time.isFinite, temperatureTimestamp.isFinite, time >= temperatureTimestamp,
              time - temperatureTimestamp < 5 else { return nil }
        return value
    }
}
protocol LightingInputSource: AnyObject {
    func start(music: Bool, temperature: Bool, update: @escaping (LightingInputs) -> Void)
    func stop()
}

/// Three complementary frequency bands, adaptive gain, and time-based envelopes.
/// Samples stay in memory for one callback; only levels leave the analyzer.
struct MusicAnalyzer {
    private var low = 0.0
    private var middleLow = 0.0
    private var reference = 0.02
    private var envelopes = [0.0, 0.0, 0.0, 0.0]
    private var previousRate = 0.0

    mutating func process(_ samples: [Float], sampleRate: Double, time: TimeInterval) -> MusicLevels {
        guard sampleRate.isFinite, (8_000...384_000).contains(sampleRate), !samples.isEmpty,
              samples.count <= 65_536, time.isFinite else { return MusicLevels() }
        if sampleRate != previousRate { low = 0; middleLow = 0; previousRate = sampleRate }
        let a = 1 - exp(-2 * Double.pi * 220 / sampleRate)
        let b = 1 - exp(-2 * Double.pi * 2200 / sampleRate)
        var power = [0.0, 0.0, 0.0, 0.0]
        for sample in samples {
            let x = sample.isFinite ? min(1, max(-1, Double(sample))) : 0
            low += a * (x - low); middleLow += b * (x - middleLow)
            let bands = [low, middleLow - low, x - middleLow, x]
            for i in 0..<4 { power[i] += bands[i] * bands[i] }
        }
        let dt = Double(samples.count) / sampleRate
        let overallRMS = sqrt(power[3] / Double(samples.count))
        reference = max(0.01, overallRMS, reference * exp(-dt / 3))
        for i in 0..<4 {
            let rms = sqrt(power[i] / Double(samples.count))
            let target = rms < 0.0002 ? 0 : min(1, sqrt(rms / reference))
            let tau = target > envelopes[i] ? 0.025 : 0.16
            envelopes[i] += (target - envelopes[i]) * (1 - exp(-dt / tau))
            if envelopes[i] < 0.002 { envelopes[i] = 0 }
        }
        return MusicLevels(bass: envelopes[0], mid: envelopes[1], treble: envelopes[2], level: envelopes[3], timestamp: time)
    }
}
