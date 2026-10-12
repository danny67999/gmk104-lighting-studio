import Foundation
import AppKit
import IOKit
import IOKit.hid
import IOKit.pwr_mgt

struct FirmwareDeviceState: Equatable, Codable {
    let otaID: UInt64
    let viaID: UInt64
    let usbID: UInt64
    let location: UInt32
    let crc: UInt32
    var description: String {
        switch crc {
        case FirmwareTarget.auroraLighting.crc: return "Complete lighting firmware 1.0 is installed • 7F2F4310"
        case FirmwareTarget.matrixColumns.crc: return "Spaced Matrix + key rain v1.7 is installed • 193BCBFA"
        case FirmwareTarget.matrixRainVertical.crc: return "Video-style vertical Matrix v1.6 is installed • D725D89A"
        case FirmwareTarget.matrixRainStaggered.crc: return "Staggered Matrix lighting v1.5 is installed • A86B6815"
        case FirmwareTarget.matrixRainFixed.crc: return "Vertical Matrix lighting v1.4 is installed • B27DBFBE"
        case FirmwareTarget.matrixLighting.crc: return "Matrix lighting v1.3 is installed • 9066E8DB"
        case FirmwareTarget.reactiveLighting.crc: return "Reactive lighting v1.2 is installed • 37E8F32B"
        case FirmwareTarget.performanceLighting.crc: return "Persistent lighting v1.1 is installed • 938EFC28"
        case FirmwareTarget.persistentLighting.crc: return "Persistent lighting v1.0 is installed • D51110C3"
        #if !GMK104_V08_LOCAL_TEST
        case FirmwareTarget.storageDiagnosticRollback.crc: return "Read-only storage survey v0.8 is installed • B6EA62D8"
        #endif
        #if !GMK104_V07_LOCAL_TEST
        case 0xD79CC2E1: return "RAM-only profiles v0.7 is installed • D79CC2E1"
        #endif
        case FirmwareTarget.custom.crc: return "Custom RGB v0.2 is installed • C6342859"
        case FirmwareTarget.wireless.crc: return "Experimental wireless v0.3 is installed • 060C4E9E"
        case FirmwareTarget.streaming.crc: return "Experimental faster Bluetooth v0.4 is installed • 6F0AD0C1"
        case FirmwareTarget.nativeRipple.crc: return "On-keyboard ripple v0.5 is installed (mode 20 needs repair) • 6CF41421"
        case FirmwareTarget.nativeRippleFixed.crc: return "Experimental on-keyboard ripple v0.6 is installed • 89EEE309"
        case FirmwareTarget.stock.crc: return "Stock firmware is installed • B85531A2"
        #if GMK104_V07_LOCAL_TEST
        case FirmwareTarget.onboardProfilePreview.crc: return "Unreleased RAM-only v0.7 local test is installed • D79CC2E1"
        #endif
        #if GMK104_V08_LOCAL_TEST
        case FirmwareTarget.storageSurvey.crc: return "Unreleased read-only storage survey v0.8 is installed • B6EA62D8"
        #endif
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

/// Report ID 5 shares a composite interface with keyboard/media reports. macOS
/// requires administrator privileges to seize that interface. Other reports are
/// discarded without interpreting or recording their contents.
private final class OTAHIDSession: FirmwareSession {
    private var device: IOHIDDevice?
    private let options: IOOptionBits
    private let input = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var response: [UInt8]?
    private var inputError: String?
    private var awaiting = false
    private var faulted = false
    private let loop = CFRunLoopGetCurrent()!
    private var pacing: FirmwareReportPacing
    private final class WriteRequest {
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        var result: IOReturn?
        init(_ data: [UInt8]) { bytes.initialize(from: data, count: 64) }
        deinit { bytes.deinitialize(count: 64); bytes.deallocate() }
    }
    init(_ device: IOHIDDevice, exclusive: Bool) throws {
        options = exclusive ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : 0
        pacing = FirmwareReportPacing(exclusive: exclusive)
        input.initialize(repeating: 0, count: 64)
        let result = IOHIDDeviceOpen(device, options)
        if result == kIOReturnNotPermitted {
            throw ControllerError.message("macOS denied keyboard access. Enable this installer in Input Monitoring, then restart it. If the switch is already on after an app update, use Refresh permission.")
        }
        if result == kIOReturnNotPrivileged {
            throw ControllerError.message("macOS requires administrator approval for exclusive firmware access. Use the installer’s administrator prompt.")
        }
        try require(result == kIOReturnSuccess, "Cannot open the firmware interface (\(result)). Close other keyboard utilities, then inspect again. Nothing was flashed.")
        self.device = device
        // Keep one input queue and callback alive throughout the session. Cycling
        // them between thousands of reports creates gaps in reply delivery.
        IOHIDDeviceRegisterInputReportCallback(device, input, 64, { context, result, _, type, id, data, length in
            guard let context else { return }
            let owner = Unmanaged<OTAHIDSession>.fromOpaque(context).takeUnretainedValue()
            if result != 0 {
                owner.inputError = String(format: "Firmware USB input failed (0x%08X).", UInt32(bitPattern: result))
                return
            }
            // The OTA collection shares a HID interface with keyboard/media
            // reports. A real key press must not abort an upload.
            guard owner.awaiting && id == 5 else { return }
            if type != kIOHIDReportTypeInput || length != 64 || data[0] != 5 {
                owner.inputError = "Invalid OTA input report or USB disconnect."
            } else if owner.response == nil { owner.response = Array(UnsafeBufferPointer(start: data, count: length)) }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            let owner = Unmanaged<OTAHIDSession>.fromOpaque(context).takeUnretainedValue()
            owner.faulted = true
            owner.inputError = "The keyboard disconnected during the USB operation."
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
    }
    deinit { close(); input.deinitialize(count: 64); input.deallocate() }
    func close() {
        if let device {
            awaiting = false
            IOHIDDeviceRegisterInputReportCallback(device, input, 64, nil, nil)
            IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, options)
        }
        device = nil
    }
    func exchange(_ packet: [UInt8], timeout: TimeInterval) throws -> [UInt8] {
        try require(packet.count == 64 && packet[0] == 5, "Invalid OTA output report.")
        guard let device, !faulted else { throw ControllerError.message("Firmware interface is closed or disconnected.") }
        try require(CFEqual(CFRunLoopGetCurrent(), loop), "Firmware operations must stay on their USB queue.")
        response = nil; inputError = nil; awaiting = false
        defer { awaiting = false }
        // Read-only queries keep the reference 16 ms minimum send interval.
        // Uploads additionally leave 16 ms after each successful reply, so a
        // delayed acknowledgment can never be followed immediately by a write.
        // This adds settling time; it does not establish the cause of a lost ACK.
        while !faulted {
            let remaining = pacing.delay(at: ProcessInfo.processInfo.systemUptime)
            if remaining <= 0 { break }
            CFRunLoopRunInMode(.defaultMode, min(0.005, remaining), true)
        }
        for _ in 0..<64 { if CFRunLoopRunInMode(.defaultMode, 0, true) != .handledSource { break } }
        try require(!faulted && inputError == nil, inputError ?? "The keyboard disconnected before the USB write.")
        awaiting = true
        let write = WriteRequest(packet)
        // The callback owns the output buffer until IOKit completes the write,
        // even if we time out and close the device first. Never reuse that buffer.
        let context = Unmanaged.passRetained(write).toOpaque()
        let sendTime = ProcessInfo.processInfo.systemUptime
        pacing.sent(at: sendTime)
        let sent = IOHIDDeviceSetReportWithCallback(device, kIOHIDReportTypeOutput, 5, write.bytes, 64, timeout * 1000, { context, result, _, _, _, _, _ in
            guard let context else { return }
            Unmanaged<WriteRequest>.fromOpaque(context).takeRetainedValue().result = result
        }, context)
        if sent != 0 { Unmanaged<WriteRequest>.fromOpaque(context).release() }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while sent == 0 && !faulted && inputError == nil && (write.result == nil || response == nil) && ProcessInfo.processInfo.systemUptime < deadline {
            if let result = write.result, result != 0 { break }
            CFRunLoopRunInMode(.defaultMode, 0.005, true)
        }
        guard sent == 0, write.result == 0, !faulted, inputError == nil, let response else {
            let completion = write.result.map { String(format: "0x%08X", UInt32(bitPattern: $0)) } ?? "pending"
            let detail = String(format: "send=0x%08X, completion=%@, reply=%@, elapsed=%.3fs", UInt32(bitPattern: sent), completion, response == nil ? "missing" : "received", ProcessInfo.processInfo.systemUptime - sendTime)
            let cause: String
            if let inputError { cause = inputError }
            else if write.result == kIOReturnNotReady { cause = "The keyboard's USB interface reported Not Ready during the firmware write." }
            else if ProcessInfo.processInfo.systemUptime >= deadline { cause = "Firmware USB reply timed out." }
            else { cause = "Firmware USB exchange failed." }
            faulted = true; close()
            throw ControllerError.message("\(cause) \(detail). Do not retry automatically.")
        }
        pacing.acknowledged(at: ProcessInfo.processInfo.systemUptime)
        return response
    }
}

enum FirmwareInstaller {
    static func ensureStudioClosed() throws {
        try require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.gmk104.rgbcontroller").isEmpty,
                    "Quit GMK104 RGB Controller before inspecting or updating firmware.")
    }
    static func inspect(exclusive: Bool = false) throws -> FirmwareDeviceState {
        try ensureStudioClosed()
        let pair = try FirmwareDevicePair.locate()
        let session = try OTAHIDSession(pair.ota, exclusive: exclusive)
        defer { session.close() }
        let query: [UInt8] = [5, 1] + [UInt8](repeating: 0, count: 62)
        let crc = try FirmwarePlan.version(session.exchange(query, timeout: 3), session.exchange(query, timeout: 3))
        let transport = try HIDTransport(wiredOnly: true)
        defer { transport.close() }
        try require(transport.registryEntryID == pair.viaID, "RGB interface changed during inspection.")
        let via = try transport.exchange([1])
        try require(via.count == 32 && Array(via.prefix(3)) == [1, 0, 0x0B], "VIA protocol identity did not match.")
        #if GMK104_V08_LOCAL_TEST
        let localPreview = crc == FirmwareTarget.onboardProfilePreview.crc || crc == FirmwareTarget.storageSurvey.crc
        #elseif GMK104_V07_LOCAL_TEST
        let localPreview = crc == FirmwareTarget.onboardProfilePreview.crc
        #else
        let localPreview = false
        #endif
        let persistent = crc == FirmwareTarget.persistentLighting.crc || crc == FirmwareTarget.performanceLighting.crc || crc == FirmwareTarget.reactiveLighting.crc || crc == FirmwareTarget.matrixLighting.crc || crc == FirmwareTarget.matrixRainFixed.crc || crc == FirmwareTarget.matrixRainStaggered.crc || crc == FirmwareTarget.matrixRainVertical.crc || crc == FirmwareTarget.matrixColumns.crc || crc == FirmwareTarget.auroraLighting.crc
        if persistent || crc == FirmwareTarget.custom.crc || crc == FirmwareTarget.wireless.crc || crc == FirmwareTarget.streaming.crc || crc == FirmwareTarget.nativeRipple.crc || crc == FirmwareTarget.nativeRippleFixed.crc || localPreview {
            let client = RGBClient(transport)
            _ = try client.read()
            if persistent || crc == FirmwareTarget.wireless.crc || crc == FirmwareTarget.streaming.crc || crc == FirmwareTarget.nativeRipple.crc || crc == FirmwareTarget.nativeRippleFixed.crc || localPreview { try require(try client.readSleepSettings() != nil, "Wireless firmware sleep signature is missing.") }
        }
        else if crc == 0xC077F2F5 {
            let signature = try transport.exchange([8, 3, 5])
            try require(Array(signature.prefix(11)) == [8, 3, 5, 1, 104, 9, 3, 71, 77, 75, 1], "Retired firmware signature mismatch.")
        }
        let after = try FirmwareDevicePair.locate()
        try require(pair.state(crc: crc) == after.state(crc: crc), "USB identity changed during inspection.")
        return pair.state(crc: crc)
    }
    static func checkConnection(progress: (Double, String) -> Void) throws -> FirmwareDeviceState {
        let before = try inspect()
        let pair = try FirmwareDevicePair.locate()
        try require(pair.state(crc: before.crc) == before, "Keyboard attachment changed before the connection test.")
        let session = try OTAHIDSession(pair.ota, exclusive: false)
        defer { session.close() }
        var assertion: IOPMAssertionID = 0
        try require(IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "GMK104 read-only USB test" as CFString, &assertion) == 0,
                    "macOS could not keep the connection test awake.")
        defer { IOPMAssertionRelease(assertion) }
        try FirmwareConnectionCheck.run(session: session, expectedCRC: before.crc, progress: progress)
        let after = try inspect()
        try require(after == before, "Keyboard identity changed during the connection test.")
        return after
    }
    static func surveyStorage(progress: (Double, String) -> Void) throws -> FirmwareStorageSurvey.Result {
        let before = try inspect()
        try require(before.crc == FirmwareTarget.storageDiagnosticRollback.crc,
                    "The read-only storage survey requires v0.8 diagnostic firmware. No data was read or written.")
        let transport = try HIDTransport(wiredOnly: true)
        defer { transport.close() }
        try require(transport.registryEntryID == before.viaID,
                    "The RGB interface changed before the storage survey.")
        let result = try FirmwareStorageSurvey.run(
            exchange: { try transport.exchange($0) },
            checkConnection: { try transport.checkSingleDevice() },
            progress: progress)
        let after = try inspect()
        try require(after == before, "The keyboard connection changed during the storage survey.")
        return result
    }
    static func install(plan: FirmwarePlan, expected: FirmwareDeviceState, confirmation: String,
                        log: @escaping (String) -> Void, progress: @escaping (Double, String) -> Void) throws -> FirmwareDeviceState {
        try require(geteuid() == 0, "Administrator approval is required. Use the firmware installer app.")
        #if GMK104_V08_LOCAL_TEST
        try require(Bundle.main.bundleIdentifier == "com.gmk104.firmwareinstaller.v08localtest",
                    "This local diagnostic image can run only from its separate, signed test app. Nothing was flashed.")
        #elseif GMK104_V07_LOCAL_TEST
        try require(Bundle.main.bundleIdentifier == "com.gmk104.firmwareinstaller.v07localtest",
                    "This local test image can run only from its separate, signed test app. Nothing was flashed.")
        #endif
        try require(confirmation == plan.target.phrase, "Typed confirmation does not match.")
        try ensureStudioClosed()
        // A fixed root-owned path serializes uploads across users. Never accept
        // a caller-controlled path or write user files with elevated privileges.
        let lockFD = open("/private/var/run/com.gmk104.firmware.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        try require(lockFD >= 0, "Cannot acquire firmware installer lock.")
        defer { close(lockFD) }
        var lockInfo = stat()
        try require(fstat(lockFD, &lockInfo) == 0 && lockInfo.st_uid == 0 &&
                    (lockInfo.st_mode & S_IFMT) == S_IFREG && lockInfo.st_nlink == 1,
                    "The firmware installation lock is not a trusted regular file.")
        try require(flock(lockFD, LOCK_EX | LOCK_NB) == 0, "Another firmware installation is running.")
        defer { flock(lockFD, LOCK_UN) }
        let state = try inspect()
        try require(state == expected, "Keyboard identity changed. Inspect again before installing.")
        if state.crc == plan.target.crc { return state }
        try require(plan.target.accepts(source: state.crc), "This firmware transition is not approved.")
        if plan.target == .persistentLighting && state.crc == FirmwareTarget.storageDiagnosticRollback.crc {
            progress(0, "Reading profile-storage areas before the firmware update. Nothing is being written.")
            let survey = try surveyStorage { _, _ in }
            try require(survey.jedec == 0x00146085 && survey.capacityMB == 1 &&
                        survey.sectors.count == 2 && survey.sectors.allSatisfy(\.allocationRecognized),
                        "Storage does not match the surveyed GMK104 layout or contains unfamiliar data. Nothing was flashed.")
            log("READ-ONLY STORAGE PRECHECK PASSED; no profile was saved or sector erased.")
        }
        let pair = try FirmwareDevicePair.locate()
        try require(pair.state(crc: state.crc) == state, "Keyboard attachment changed before installation.")
        let session = try OTAHIDSession(pair.ota, exclusive: true)
        defer { session.close() }
        log(String(format: "PRECHECK source=%08X target=%08X SHA256=%@ stream=%@", state.crc, plan.target.crc, plan.imageHash, plan.streamHash))
        log("USB location=\(state.location) parent=\(state.usbID) ota=\(state.otaID) via=\(state.viaID); persistent listener, minimum send interval=16ms, post-reply settling=16ms, upload reply timeout=\(Int(FirmwareTransfer.replyTimeout))s, overall limit=720s")
        var assertion: IOPMAssertionID = 0
        try require(IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "GMK104 firmware upload" as CFString, &assertion) == 0,
                    "macOS could not prevent sleep. Firmware upload was not started.")
        defer { IOPMAssertionRelease(assertion) }
        do { try FirmwareTransfer.run(plan, session: session, sourceCRC: state.crc, progress: progress, log: log) }
        catch { log("TRANSFER STOPPED: \(error.localizedDescription)"); throw error }
        var lastError = "Keyboard did not return."
        for _ in 0..<45 {
            Thread.sleep(forTimeInterval: 1)
            do {
                let after = try inspect()
                guard after.crc == plan.target.crc && after.location == state.location else { lastError = after.description; continue }
                log("POSTBOOT VERIFIED")
                progress(1, "Firmware installed and verified after reboot.")
                return after
            } catch { lastError = error.localizedDescription }
        }
        log("POSTBOOT INDETERMINATE: \(lastError)")
        throw ControllerError.message("Result indeterminate: \(lastError) Do not flash again automatically. Reconnect once, then Inspect.")
    }
}
