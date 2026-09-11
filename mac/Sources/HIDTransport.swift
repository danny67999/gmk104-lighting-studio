import Foundation
import IOKit
import IOKit.hid

final class HIDTransport: ReportTransport {
    private var device: IOHIDDevice?
    private(set) var registryEntryID: UInt64?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var response: [UInt8]?
    private var callbackError: String?
    private var awaiting = false
    private var faulted = false
    static let matching: [String: Any] = [
        kIOHIDVendorIDKey: 0x320F, kIOHIDProductIDKey: 0x5055,
        kIOHIDDeviceUsagePageKey: 0xFF60, kIOHIDDeviceUsageKey: 0x61
    ]
    static func candidates() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>).map(Array.init) ?? []
    }
    static func registryID(of device: IOHIDDevice) throws -> UInt64 {
        let service = IOHIDDeviceGetService(device)
        var entryID: UInt64 = 0
        try require(service != IO_OBJECT_NULL &&
                    IORegistryEntryGetRegistryEntryID(service, &entryID) == kIOReturnSuccess && entryID != 0,
                    "Unable to verify the keyboard’s USB identity. Reconnect and try again.")
        return entryID
    }
    init() throws {
        buffer.initialize(repeating: 0, count: 64)
        let matches = Self.candidates()
        try require(matches.count == 1, "Found \(matches.count) matching wired GMK104 interfaces. Connect exactly one keyboard by USB.")
        let d = matches[0]
        let entryID = try Self.registryID(of: d)
        for key in [kIOHIDMaxInputReportSizeKey, kIOHIDMaxOutputReportSizeKey] {
            let size = (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue
            try require(size == 32, "The GMK104 interface must expose 32-byte macOS HID reports.")
        }
        let result = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        try require(result == kIOReturnSuccess, "Unable to open GMK104 HID (\(result)). Close other keyboard-control apps and reconnect.")
        device = d
        registryEntryID = entryID
    }
    func checkSingleDevice() throws {
        let matches = Self.candidates()
        try require(matches.count == 1, "The number of matching keyboards changed. Reconnect exactly one wired GMK104.")
        guard device != nil, let registryEntryID else { throw ControllerError.message("Keyboard disconnected.") }
        // Each manager creates a new IOHIDDevice wrapper, so CFEqual compares different
        // objects even for the same keyboard. The registry entry identifies this exact
        // USB attachment and changes when the keyboard is unplugged and reconnected.
        try require(try Self.registryID(of: matches[0]) == registryEntryID,
                    "The keyboard connection changed. Reconnect in the app.")
    }
    func close() {
        if let d = device { IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        registryEntryID = nil
    }
    deinit { close(); buffer.deinitialize(count: 64); buffer.deallocate() }
    func exchange(_ payload: [UInt8]) throws -> [UInt8] {
        guard let d = device, !faulted else { throw ControllerError.message("Keyboard offline. Connect again before continuing.") }
        try require(payload.count <= 32, "HID payload is too long.")
        let loop = CFRunLoopGetCurrent()!
        response = nil; callbackError = nil; awaiting = false
        IOHIDDeviceRegisterInputReportCallback(d, buffer, 64, { context, result, _, type, reportID, report, length in
            guard let context else { return }
            let owner = Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
            guard owner.awaiting else { return }
            if result != kIOReturnSuccess || type != kIOHIDReportTypeInput || reportID != 0 || length != 32 {
                owner.callbackError = "Invalid HID input report or disconnected keyboard."
            } else if owner.response == nil {
                owner.response = Array(UnsafeBufferPointer(start: report, count: length))
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(d, loop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            awaiting = false
            IOHIDDeviceUnscheduleFromRunLoop(d, loop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(d, buffer, 64, nil, nil)
        }
        // Drain queued reports before arming the next exchange.
        for _ in 0..<64 {
            if CFRunLoopRunInMode(.defaultMode, 0, true) != .handledSource { break }
        }
        awaiting = true
        let packet = payload + Array(repeating: UInt8(0), count: 32 - payload.count)
        let result = packet.withUnsafeBufferPointer { p in
            IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0, p.baseAddress!, p.count)
        }
        let deadline = Date().addingTimeInterval(2)
        while result == kIOReturnSuccess && response == nil && callbackError == nil && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
        guard result == kIOReturnSuccess, callbackError == nil, let response else {
            faulted = true
            throw ControllerError.message(callbackError ?? "GMK104 USB exchange failed or timed out (\(result)). Reconnect the keyboard.")
        }
        return response
    }
}
