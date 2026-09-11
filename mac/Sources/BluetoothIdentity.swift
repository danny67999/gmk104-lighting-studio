import Foundation
import IOKit
import IOKit.hid

struct BluetoothKeyboardIdentity {
    let registryID: UInt64
    let name: String
    static let names: Set<String> = ["ZUOYA GMK104-1", "ZUOYA GMK104-2", "ZUOYA GMK104-3"]
    static var matching: [String: Any] { [
        kIOHIDVendorIDKey: 0x245A, kIOHIDProductIDKey: 0x8276,
        kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6,
        kIOHIDTransportKey: "BluetoothLowEnergy"
    ] }
    static func candidates() -> [Self] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        return devices.compactMap { device in
            guard let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
                  names.contains(name) else { return nil }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id) == kIOReturnSuccess, id != 0 else { return nil }
            return Self(registryID: id, name: name)
        }
    }
}
