import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

/// Observes physical key-down transitions only, from the connected GMK104.
/// Does not seize the keyboard, interpret text, retain a typing history, or post events.
final class KeyboardEvents {
    enum Permission: String {
        case granted, denied, unknown

        var message: String {
            switch self {
            case .granted: return "Input Monitoring is enabled."
            case .denied: return "Enable GMK104 RGB Controller in System Settings → Privacy & Security → Input Monitoring, then restart the app."
            case .unknown: return "Allow Input Monitoring to react to this keyboard while you use other apps."
            }
        }
    }

    static var permission: Permission {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .unknown
        }
    }

    /// Call only from an explicit permission button. `start` never requests access.
    @discardableResult static func requestPermission() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    private enum MonitorError: LocalizedError {
        case message(String)
        var errorDescription: String? { switch self { case .message(let message): return message } }
    }

    private let onPress: (String) -> Void
    private let lock = NSLock()
    private var session: Session?

    init(onPress: @escaping (String) -> Void) { self.onPress = onPress }

    /// The registry ID must be the current vendor HID interface (FF60:0061).
    /// Its USB ancestor ties all input interfaces to this exact physical attachment.
    func start(registryID: UInt64?) throws {
        stop()
        let access = Self.permission
        guard access == .granted else { throw MonitorError.message(access.message) }
        guard let registryID, let target = Self.usbAncestor(registryID: registryID) else {
            throw MonitorError.message("Connect the wired GMK104 before enabling keypress effects.")
        }
        let next = Session(usbID: target) { [weak self] source, key in
            DispatchQueue.main.async { [weak self, weak source] in
                guard let self, let source else { return }
                self.lock.lock()
                let isCurrent = self.session === source
                self.lock.unlock()
                if isCurrent && source.isActive { self.onPress(key) }
            }
        }
        lock.lock(); session = next; lock.unlock()
        do { try next.start() }
        catch {
            next.stop()
            lock.lock()
            if session === next { session = nil }
            lock.unlock()
            throw error
        }
    }

    func stop() {
        lock.lock(); let old = session; session = nil; lock.unlock()
        old?.stop()
    }

    deinit { stop() }

    /// USB HID keyboard usages map to physical positions, independent of macOS layout.
    static func keyID(forUsage usage: UInt32) -> String? {
        if (0x04...0x1D).contains(usage) {
            return "Key" + String(UnicodeScalar(65 + usage - 0x04)!)
        }
        if (0x1E...0x26).contains(usage) { return "Digit\(usage - 0x1D)" }
        if (0x3A...0x45).contains(usage) { return "F\(usage - 0x39)" }
        if (0x59...0x61).contains(usage) { return "Numpad\(usage - 0x58)" }
        return [
            0x27: "Digit0", 0x28: "Enter", 0x29: "Escape", 0x2A: "Backspace",
            0x2B: "Tab", 0x2C: "Space", 0x2D: "Minus", 0x2E: "Equal",
            0x2F: "BracketLeft", 0x30: "BracketRight", 0x31: "Backslash",
            0x33: "Semicolon", 0x34: "Quote", 0x35: "Backquote", 0x36: "Comma",
            0x37: "Period", 0x38: "Slash", 0x39: "CapsLock",
            0x46: "PrintScreen", 0x47: "ScrollLock", 0x48: "Pause",
            0x49: "Insert", 0x4A: "Home", 0x4B: "PageUp", 0x4C: "Delete",
            0x4D: "End", 0x4E: "PageDown", 0x4F: "ArrowRight", 0x50: "ArrowLeft",
            0x51: "ArrowDown", 0x52: "ArrowUp", 0x53: "NumLock",
            0x54: "NumpadDivide", 0x55: "NumpadMultiply", 0x56: "NumpadSubtract",
            0x57: "NumpadAdd", 0x58: "NumpadEnter", 0x62: "Numpad0",
            0x63: "NumpadDecimal", 0x65: "ContextMenu",
            0xE0: "ControlLeft", 0xE1: "ShiftLeft", 0xE2: "AltLeft", 0xE3: "MetaLeft",
            0xE4: "ControlRight", 0xE5: "ShiftRight", 0xE6: "AltRight", 0xE7: "MetaRight"
        ][usage]
    }

    private static func registryID(of device: IOHIDDevice) -> UInt64? {
        var id: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        guard service != IO_OBJECT_NULL,
              IORegistryEntryGetRegistryEntryID(service, &id) == kIOReturnSuccess else { return nil }
        return id
    }

    private static func usbAncestor(registryID: UInt64) -> UInt64? {
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        guard entry != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(entry) }
        for _ in 0..<64 {
            if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0 || IOObjectConformsTo(entry, "IOUSBDevice") != 0 {
                var id: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(entry, &id) == kIOReturnSuccess else { return nil }
                return id
            }
            var parent: io_registry_entry_t = IO_OBJECT_NULL
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == kIOReturnSuccess else { return nil }
            IOObjectRelease(entry)
            entry = parent
        }
        return nil
    }

    /// HID scheduling is isolated from the serial vendor-report exchange run loop.
    /// The thread retains this session until every callback is unregistered and device closed.
    private final class Session {
        let usbID: UInt64
        let onPress: (Session, String) -> Void
        private let stateLock = NSLock()
        private let ready = DispatchSemaphore(value: 0)
        private var runLoop: CFRunLoop?
        private var cancelled = false
        private var startupError: Error?
        // These fields are used only on this session's HID thread.
        private var devices: [IOHIDDevice] = []
        private var pressedByDevice: [UInt64: Set<UInt32>] = [:]

        init(usbID: UInt64, onPress: @escaping (Session, String) -> Void) {
            self.usbID = usbID; self.onPress = onPress
        }

        var isActive: Bool {
            stateLock.lock(); defer { stateLock.unlock() }
            return !cancelled
        }

        func start() throws {
            let worker = Thread { [self] in run() }
            worker.name = "GMK104 physical key input"
            worker.qualityOfService = .userInteractive
            worker.start()
            guard ready.wait(timeout: .now() + 3) == .success else {
                stop()
                throw MonitorError.message("Timed out while starting GMK104 key input. Reconnect and try again.")
            }
            stateLock.lock(); let error = startupError; stateLock.unlock()
            if let error { throw error }
        }

        func stop() {
            stateLock.lock()
            cancelled = true
            let loop = runLoop
            stateLock.unlock()
            if let loop {
                // A queued stop also handles cancellation just before CFRunLoopRun begins.
                CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(loop) }
                CFRunLoopWakeUp(loop)
            }
        }

        private func run() {
            let loop = CFRunLoopGetCurrent()!
            do {
                guard isActive else { throw MonitorError.message("Key input stopped.") }
                let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
                IOHIDManagerSetDeviceMatching(manager, [
                    kIOHIDVendorIDKey: 0x320F, kIOHIDProductIDKey: 0x5055,
                    kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6
                ] as CFDictionary)
                // Enumeration alone does not open or subscribe to any device.
                let candidates = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
                let selected = candidates.filter {
                    guard let id = KeyboardEvents.registryID(of: $0) else { return false }
                    return KeyboardEvents.usbAncestor(registryID: id) == usbID
                }
                guard !selected.isEmpty else {
                    throw MonitorError.message("No keyboard input interface was found for this GMK104 USB connection.")
                }
                // Check before every open: IOHIDDeviceOpen can otherwise prompt automatically.
                for device in selected {
                    guard isActive else { throw MonitorError.message("Key input stopped.") }
                    guard KeyboardEvents.permission == .granted else {
                        throw MonitorError.message(KeyboardEvents.permission.message)
                    }
                    let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                    guard result == kIOReturnSuccess else {
                        throw MonitorError.message("Unable to observe GMK104 key input (\(result)). Check Input Monitoring and reconnect.")
                    }
                    devices.append(device)
                    IOHIDDeviceSetInputValueMatching(device, [kIOHIDElementUsagePageKey: 7] as CFDictionary)
                    let context = Unmanaged.passUnretained(self).toOpaque()
                    IOHIDDeviceRegisterInputValueCallback(device, { context, result, _, value in
                        guard let context, result == kIOReturnSuccess else { return }
                        Unmanaged<Session>.fromOpaque(context).takeUnretainedValue().received(value)
                    }, context)
                    IOHIDDeviceRegisterRemovalCallback(device, { context, _, sender in
                        guard let context, let sender else { return }
                        let owner = Unmanaged<Session>.fromOpaque(context).takeUnretainedValue()
                        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
                        if let id = KeyboardEvents.registryID(of: device) { owner.pressedByDevice.removeValue(forKey: id) }
                    }, context)
                    IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
                }
                stateLock.lock(); runLoop = loop; let shouldRun = !cancelled; stateLock.unlock()
                ready.signal()
                if shouldRun { CFRunLoopRun() }
            } catch {
                stateLock.lock(); startupError = error; stateLock.unlock()
                ready.signal()
            }
            for device in devices {
                IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
                IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
                IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            devices.removeAll(); pressedByDevice.removeAll()
            stateLock.lock(); cancelled = true; runLoop = nil; stateLock.unlock()
        }

        private func received(_ value: IOHIDValue) {
            guard isActive, (1...MemoryLayout<Int>.size).contains(IOHIDValueGetLength(value)) else { return }
            let element = IOHIDValueGetElement(value)
            let device = IOHIDElementGetDevice(element)
            guard IOHIDElementGetUsagePage(element) == 7,
                  let id = KeyboardEvents.registryID(of: device) else { return }
            let usage = IOHIDElementGetUsage(element)
            guard let key = KeyboardEvents.keyID(forUsage: usage) else { return }
            let wasDown = pressedByDevice.values.contains { $0.contains(usage) }
            if IOHIDValueGetIntegerValue(value) != 0 {
                pressedByDevice[id, default: []].insert(usage)
                if !wasDown { onPress(self, key) }
            } else {
                pressedByDevice[id]?.remove(usage)
            }
        }
    }
}
