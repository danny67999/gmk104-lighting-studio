import Foundation
import AppKit
import IOKit
import IOKit.hid
import IOKit.pwr_mgt

struct FirmwareDeviceState: Equatable {
    let otaID: UInt64
    let viaID: UInt64
    let usbID: UInt64
    let location: UInt32
    let crc: UInt32
    var description: String {
        switch crc {
        case FirmwareTarget.custom.crc: return "Custom RGB v0.2 is installed • C6342859"
        case FirmwareTarget.stock.crc: return "Stock firmware is installed • B85531A2"
        default: return "Retired v0.1 is installed • stock rollback only"
        }
    }
}
private struct FirmwareDevicePair {
    let ota: IOHIDDevice
    let via: IOHIDDevice
    let otaID: UInt64
    let viaID: UInt64
    let usbID: UInt64
    let location: UInt32
    static func locate() throws -> Self {
        func devices(_ page: Int, _ usage: Int) -> [IOHIDDevice] {
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x320F, kIOHIDProductIDKey: 0x5055,
                kIOHIDDeviceUsagePageKey: page, kIOHIDDeviceUsageKey: usage] as CFDictionary)
            return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
        }
        let ota = devices(0xFFEF, 0), via = devices(0xFF60, 0x61)
        try require(ota.count == 1 && via.count == 1, "Connect exactly one wired GMK104 with both firmware and RGB interfaces available.")
        func number(_ d: IOHIDDevice, _ key: String) -> UInt32? { (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.uint32Value }
        for d in [ota[0], via[0]] {
            try require(IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String == "ZUOYA GMK104" &&
                        IOHIDDeviceGetProperty(d, kIOHIDManufacturerKey as CFString) as? String == "RDR" &&
                        number(d, kIOHIDVersionNumberKey) == 0x0111, "USB product, manufacturer or version is not approved.")
        }
        for (d, input, output, feature) in [(ota[0], 64, 64, 64), (via[0], 32, 32, 0)] {
            try require(number(d, kIOHIDMaxInputReportSizeKey) == UInt32(input) && number(d, kIOHIDMaxOutputReportSizeKey) == UInt32(output) &&
                        number(d, kIOHIDMaxFeatureReportSizeKey) == UInt32(feature), "Unexpected firmware or RGB report sizes.")
        }
        func physicalID(_ device: IOHIDDevice) throws -> UInt64 {
            var entry = IOHIDDeviceGetService(device), owned = false
            defer { if owned { IOObjectRelease(entry) } }
            for _ in 0..<10 {
                if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0 {
                    var id: UInt64 = 0
                    try require(IORegistryEntryGetRegistryEntryID(entry, &id) == 0 && id != 0, "Cannot identify physical USB device.")
                    return id
                }
                var parent: io_registry_entry_t = 0
                try require(IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == 0, "Cannot prove both interfaces share one physical keyboard.")
                if owned { IOObjectRelease(entry) }; entry = parent; owned = true
            }
            throw ControllerError.message("No physical USB parent found.")
        }
        let physical = try physicalID(ota[0])
        try require(try physicalID(via[0]) == physical, "OTA and RGB interfaces belong to different physical keyboards.")
        guard let location = number(ota[0], kIOHIDLocationIDKey), location != 0,
              number(via[0], kIOHIDLocationIDKey) == location else { throw ControllerError.message("USB port identity is unavailable.") }
        return try Self(ota: ota[0], via: via[0], otaID: HIDTransport.registryID(of: ota[0]),
                        viaID: HIDTransport.registryID(of: via[0]), usbID: physical, location: location)
    }
    func state(crc: UInt32) -> FirmwareDeviceState { FirmwareDeviceState(otaID: otaID, viaID: viaID, usbID: usbID, location: location, crc: crc) }
}

/// Report ID 5 is included in the 64-byte macOS OTA buffer. No keyboard input
/// interface is opened or seized. A timed-out exchange permanently faults this handle.
private final class OTAHIDSession: FirmwareSession {
    private var device: IOHIDDevice?
    private let options: IOOptionBits
    private let input = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var response: [UInt8]?
    private var inputError: String?
    private var awaiting = false
    private var faulted = false
    private final class WriteRequest {
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        var result: IOReturn?
        init(_ data: [UInt8]) { bytes.initialize(from: data, count: 64) }
        deinit { bytes.deinitialize(count: 64); bytes.deallocate() }
    }
    init(_ device: IOHIDDevice, exclusive: Bool) throws {
        options = exclusive ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0
        input.initialize(repeating: 0, count: 64)
        let result = IOHIDDeviceOpen(device, options)
        try require(result == kIOReturnSuccess, "Cannot open firmware interface (\(result)). Close all keyboard utilities.")
        self.device = device
    }
    deinit { close(); input.deinitialize(count: 64); input.deallocate() }
    func close() {
        if let device { IOHIDDeviceClose(device, options) }
        device = nil
    }
    func exchange(_ packet: [UInt8], timeout: TimeInterval) throws -> [UInt8] {
        try require(packet.count == 64 && packet[0] == 5, "Invalid OTA output report.")
        guard let device, !faulted else { throw ControllerError.message("Firmware interface is closed or faulted.") }
        let loop = CFRunLoopGetCurrent()!
        response = nil; inputError = nil; awaiting = false
        IOHIDDeviceRegisterInputReportCallback(device, input, 64, { context, result, _, type, id, data, length in
            guard let context else { return }
            let owner = Unmanaged<OTAHIDSession>.fromOpaque(context).takeUnretainedValue()
            guard owner.awaiting else { return }
            if result != 0 || type != kIOHIDReportTypeInput || id != 5 || length != 64 || data[0] != 5 {
                owner.inputError = "Invalid OTA input report or USB disconnect."
            } else if owner.response == nil { owner.response = Array(UnsafeBufferPointer(start: data, count: length)) }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            awaiting = false
            IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(device, input, 64, nil, nil)
        }
        for _ in 0..<64 { if CFRunLoopRunInMode(.defaultMode, 0, true) != .handledSource { break } }
        awaiting = true
        let write = WriteRequest(packet)
        // The callback owns the output buffer until IOKit completes the write,
        // even if we time out and close the device first. Never reuse that buffer.
        let context = Unmanaged.passRetained(write).toOpaque()
        let sent = IOHIDDeviceSetReportWithCallback(device, kIOHIDReportTypeOutput, 5, write.bytes, 64, timeout * 1000, { context, result, _, _, _, _, _ in
            guard let context else { return }
            Unmanaged<WriteRequest>.fromOpaque(context).takeRetainedValue().result = result
        }, context)
        if sent != 0 { Unmanaged<WriteRequest>.fromOpaque(context).release() }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while sent == 0 && inputError == nil && (write.result == nil || response == nil) && ProcessInfo.processInfo.systemUptime < deadline {
            if let result = write.result, result != 0 { break }
            CFRunLoopRunInMode(.defaultMode, 0.005, true)
        }
        guard sent == 0, write.result == 0, inputError == nil, let response else {
            faulted = true; close()
            throw ControllerError.message(inputError ?? "Firmware USB exchange timed out or failed. Do not retry automatically.")
        }
        return response
    }
}

enum FirmwareInstaller {
    static func ensureStudioClosed() throws {
        try require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.gmk104.rgbcontroller").isEmpty,
                    "Quit GMK104 RGB Controller before inspecting or updating firmware.")
    }
    static func inspect() throws -> FirmwareDeviceState {
        try ensureStudioClosed()
        let pair = try FirmwareDevicePair.locate()
        let session = try OTAHIDSession(pair.ota, exclusive: false)
        defer { session.close() }
        let query: [UInt8] = [5, 1] + [UInt8](repeating: 0, count: 62)
        let crc = try FirmwarePlan.version(session.exchange(query, timeout: 3), session.exchange(query, timeout: 3))
        let transport = try HIDTransport(wiredOnly: true)
        defer { transport.close() }
        try require(transport.registryEntryID == pair.viaID, "RGB interface changed during inspection.")
        let via = try transport.exchange([1])
        try require(via.count == 32 && Array(via.prefix(3)) == [1, 0, 0x0B], "VIA protocol identity did not match.")
        if crc == FirmwareTarget.custom.crc { _ = try RGBClient(transport).read() }
        else if crc == 0xC077F2F5 {
            let signature = try transport.exchange([8, 3, 5])
            try require(Array(signature.prefix(11)) == [8, 3, 5, 1, 104, 9, 3, 71, 77, 75, 1], "Retired firmware signature mismatch.")
        }
        let after = try FirmwareDevicePair.locate()
        try require(pair.state(crc: crc) == after.state(crc: crc), "USB identity changed during inspection.")
        return pair.state(crc: crc)
    }
    static func install(plan: FirmwarePlan, expected: FirmwareDeviceState, confirmation: String,
                        logURL: URL, progress: @escaping (Double, String) -> Void) throws -> FirmwareDeviceState {
        try require(confirmation == plan.target.phrase, "Typed confirmation does not match.")
        try ensureStudioClosed()
        let lockURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GMK104RgbController/firmware.lock")
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockFD = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        try require(lockFD >= 0, "Cannot acquire firmware installer lock.")
        defer { close(lockFD) }
        try require(flock(lockFD, LOCK_EX | LOCK_NB) == 0, "Another firmware installation is running.")
        defer { flock(lockFD, LOCK_UN) }
        let state = try inspect()
        try require(state == expected, "Keyboard identity changed. Inspect again before installing.")
        if state.crc == plan.target.crc { return state }
        try require(plan.target.accepts(source: state.crc), "This firmware transition is not approved.")
        let pair = try FirmwareDevicePair.locate()
        try require(pair.state(crc: state.crc) == state, "Keyboard attachment changed before installation.")
        let session = try OTAHIDSession(pair.ota, exclusive: true)
        defer { session.close() }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: logURL, options: .withoutOverwriting)
        let file = try FileHandle(forWritingTo: logURL)
        defer { try? file.close() }
        func entry(_ message: String) -> Data { Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8) }
        try file.write(contentsOf: entry(String(format: "PRECHECK source=%08X target=%08X SHA256=%@ stream=%@", state.crc, plan.target.crc, plan.imageHash, plan.streamHash)))
        try file.synchronize()
        var assertion: IOPMAssertionID = 0
        try require(IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "GMK104 firmware upload" as CFString, &assertion) == 0,
                    "macOS could not prevent sleep. Firmware upload was not started.")
        defer { IOPMAssertionRelease(assertion) }
        var loggingFailed = false
        let log: (String) -> Void = { message in
            do { try file.write(contentsOf: entry(message)); try file.synchronize() }
            catch { loggingFailed = true }
        }
        do { try FirmwareTransfer.run(plan, session: session, sourceCRC: state.crc, progress: progress, log: log) }
        catch { log("TRANSFER STOPPED: \(error.localizedDescription)"); throw error }
        var lastError = "Keyboard did not return."
        for _ in 0..<45 {
            Thread.sleep(forTimeInterval: 1)
            do {
                let after = try inspect()
                guard after.crc == plan.target.crc && after.location == state.location else { lastError = after.description; continue }
                log("POSTBOOT VERIFIED")
                progress(1, loggingFailed ? "Firmware verified. The transfer log could not be fully saved." : "Firmware installed and verified after reboot.")
                return after
            } catch { lastError = error.localizedDescription }
        }
        log("POSTBOOT INDETERMINATE: \(lastError)")
        throw ControllerError.message("Result indeterminate: \(lastError) Do not flash again automatically. Reconnect once, then Inspect.")
    }
}
