import Foundation
import IOKit
import CoreAudio
import AudioToolbox

/// Owns one audio tap and one read-only SMC connection for the entire layer stack.
/// All native state and callbacks live on this queue, independently of USB writes.
final class NativeLightingInputSource: LightingInputSource {
    private let queue = DispatchQueue(label: "GMK104.LiveInputs", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var audio: AnyObject?
    private var smc: CPUTemperatureReader?
    private var update: ((LightingInputs) -> Void)?
    private var state = LightingInputs()
    private var generation = 0
    private var lastTemperature = -Double.infinity
    private var lastPublish = -Double.infinity

    func start(music: Bool, temperature: Bool, update: @escaping (LightingInputs) -> Void) {
        queue.async {
            self.stopOnQueue()
            self.update = update
            let token = self.generation
            if temperature {
                self.state.temperatureStatus = "Reading CPU sensors…"
                self.smc = try? CPUTemperatureReader()
            }
            if music {
                if #available(macOS 14.2, *) {
                    let tap = SystemAudioTap(queue: self.queue)
                    self.audio = tap
                    self.state.musicStatus = "Starting Mac audio • allow Audio Recording if macOS asks"
                    self.publish()
                    do {
                        try tap.start { [weak self] levels in
                            guard let self, token == self.generation else { return }
                            self.state.music = levels
                            self.state.audioRunning = true
                            self.state.musicStatus = levels.level > 0.01 ? "Listening to Mac audio" : "Listening • play audio on your Mac"
                            if ProcessInfo.processInfo.systemUptime - self.lastPublish >= 1.0 / 30 { self.publish() }
                        }
                        self.state.audioRunning = true
                        self.state.musicStatus = "Waiting for Mac audio • check Audio Recording permission if silent"
                    } catch {
                        tap.stop(); self.audio = nil
                        self.state.musicStatus = "Mac audio unavailable: \(error.localizedDescription)"
                    }
                } else { self.state.musicStatus = "Mac audio requires macOS 14.2 or later" }
            }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 0.5)
            timer.setEventHandler { [weak self] in
                guard let self, token == self.generation else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if temperature && now - self.lastTemperature >= 1 {
                    self.lastTemperature = now
                    if self.smc == nil { self.smc = try? CPUTemperatureReader() }
                    let readings = self.smc?.read() ?? []
                    self.state.cpuCelsius = readings.map(\.celsius).max()
                    self.state.temperatureTimestamp = now
                    self.state.temperatureStatus = self.state.cpuCelsius.map {
                        String(format: "CPU %.1f°C • hottest of %d sensors", $0, readings.count)
                    } ?? "CPU temperature unavailable on this Mac"
                }
                if music && self.state.audioRunning && now - self.state.music.timestamp > 1 {
                    self.state.music = MusicLevels()
                    self.state.musicStatus = "No audio received • play audio or check Audio Recording permission"
                }
                self.publish()
            }
            self.timer = timer; timer.resume(); self.publish()
        }
    }
    func stop() { queue.async { self.stopOnQueue() } }
    private func stopOnQueue() {
        generation += 1; timer?.cancel(); timer = nil
        if #available(macOS 14.2, *) { (audio as? SystemAudioTap)?.stop() }
        audio = nil; smc = nil; update = nil; state = LightingInputs()
        lastTemperature = -.infinity; lastPublish = -.infinity
    }
    private func publish() {
        lastPublish = ProcessInfo.processInfo.systemUptime
        let snapshot = state
        update?(snapshot)
    }
}

/// AppleSMC's 80-byte request ABI. Only key-info, index and read operations exist
/// here; no fan, voltage, power-limit or other SMC write operation is implemented.
final class CPUTemperatureReader {
    struct Reading { let key: String; let celsius: Double }
    private var connection: io_connect_t = 0
    private var sensors: [(key: String, size: UInt32, type: UInt32)] = []
    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw ControllerError.message("AppleSMC is unavailable.") }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw ControllerError.message("CPU sensors could not be opened (\(result)).") }
        var names = Set<String>()
        if let info = call(key: Self.four("#KEY"), command: 9), Self.uint(info, at: 28) == 4,
           let data = call(key: Self.four("#KEY"), command: 5, size: 4) {
            let count = data[48..<52].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if (1...16_384).contains(count) {
                for index in 0..<count {
                    guard let entry = call(key: 0, command: 8, index: index) else { continue }
                    let key = Self.uint(entry, at: 0)
                    let name = String(bytes: (0..<4).map { UInt8(truncatingIfNeeded: key >> ((3 - $0) * 8)) }, encoding: .ascii) ?? ""
                    if name.hasPrefix("Tp") || name.hasPrefix("Te") || ["TC0D", "TCAD", "TC0E", "TC0F"].contains(name) { names.insert(name) }
                }
            }
        }
        for name in names.sorted() {
            guard let info = call(key: Self.four(name), command: 9) else { continue }
            let size = Self.uint(info, at: 28), type = Self.uint(info, at: 32)
            if (size == 4 && type == Self.four("flt ")) || (size == 2 && type == Self.four("sp78")) {
                sensors.append((name, size, type))
            }
        }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    func read() -> [Reading] {
        sensors.compactMap { sensor in
            guard let data = call(key: Self.four(sensor.key), command: 5, size: sensor.size) else { return nil }
            let value: Double
            if sensor.type == Self.four("flt ") { value = Double(Float(bitPattern: Self.uint(data, at: 48))) }
            else { value = Double(Int16(bitPattern: UInt16(data[48]) << 8 | UInt16(data[49]))) / 256 }
            guard value.isFinite && (1...125).contains(value) else { return nil }
            return Reading(key: sensor.key, celsius: value)
        }
    }
    private func call(key: UInt32, command: UInt8, size: UInt32 = 0, index: UInt32 = 0) -> [UInt8]? {
        guard [5, 8, 9].contains(command), connection != 0 else { return nil }
        var input = [UInt8](repeating: 0, count: 80), output = input
        Self.put(key, into: &input, at: 0); Self.put(size, into: &input, at: 28)
        input[42] = command; Self.put(index, into: &input, at: 44)
        var length = 80
        let result = input.withUnsafeBytes { i in output.withUnsafeMutableBytes { o in
            IOConnectCallStructMethod(connection, 2, i.baseAddress, 80, o.baseAddress, &length)
        } }
        guard result == kIOReturnSuccess && length == 80 && output[40] == 0 else { return nil }
        return output
    }
    private static func four(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private static func uint(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
    private static func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
    }
}

@available(macOS 14.2, *)
private final class SystemAudioTap {
    private let queue: DispatchQueue
    private var tap: AudioObjectID = kAudioObjectUnknown
    private var device: AudioObjectID = kAudioObjectUnknown
    private var ioProc: AudioDeviceIOProcID?
    private var analyzer = MusicAnalyzer()
    init(queue: DispatchQueue) { self.queue = queue }
    func start(receive: @escaping (MusicLevels) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "GMK104 Music Lighting"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap), "Create audio tap")
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "Read audio format")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate >= 8_000 else {
            throw ControllerError.message("The Mac audio format is unsupported.")
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "GMK104 Music Lighting",
            kAudioAggregateDeviceUIDKey: "com.gmk104.audio.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]]
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), "Create audio capture device")
        let sampleRate = format.mSampleRate
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, queue) { [weak self] _, input, _, _, _ in
            guard let self else { return }
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let valid = buffers.filter { $0.mData != nil && $0.mNumberChannels > 0 }
            guard !valid.isEmpty else { return }
            let count = valid.map { Int($0.mDataByteSize) / 4 / Int($0.mNumberChannels) }.min() ?? 0
            guard (1...65_536).contains(count) else { return }
            // Use the strongest channel so opposite-phase stereo never cancels
            // into false silence, and audio on either channel remains visible.
            var samples = [Float](repeating: 0, count: count)
            var strongest = -Double.infinity
            for buffer in valid {
                let values = buffer.mData!.assumingMemoryBound(to: Float.self)
                let n = Int(buffer.mNumberChannels)
                for channel in 0..<n {
                    var energy = 0.0
                    for frame in 0..<count {
                        let sample = Double(values[frame * n + channel])
                        if sample.isFinite { energy += sample * sample }
                    }
                    if energy > strongest {
                        strongest = energy
                        for frame in 0..<count { samples[frame] = values[frame * n + channel] }
                    }
                }
            }
            receive(self.analyzer.process(samples, sampleRate: sampleRate, time: ProcessInfo.processInfo.systemUptime))
        }, "Start audio processing")
        try check(AudioDeviceStart(device, ioProc), "Start system audio capture")
    }
    func stop() {
        if device != kAudioObjectUnknown {
            if let ioProc { AudioDeviceStop(device, ioProc); AudioDeviceDestroyIOProcID(device, ioProc) }
            AudioHardwareDestroyAggregateDevice(device)
        }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        ioProc = nil; device = kAudioObjectUnknown; tap = kAudioObjectUnknown
    }
    deinit { stop() }
    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw ControllerError.message("\(operation) failed (\(status)). Allow System Audio Recording in Privacy & Security, then retry audio.")
        }
    }
}
