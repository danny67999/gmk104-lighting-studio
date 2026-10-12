import Foundation

@main struct KeyboardEventTests {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "mac/Resources/layout.json"))
        let layout = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let expected = Set(layout.compactMap { $0["id"] as? String })
        let supported = (UInt32(0)...UInt32(255)).compactMap(KeyboardEvents.keyID(forUsage:))
        assert(supported.count == 104 && Set(supported) == expected)
        print("PASS: physical HID usages cover all 104 layout keys exactly once")
        assert(KeyboardEvents.keyID(forUsage: 0) == nil)
        assert(KeyboardEvents.keyID(forUsage: 1) == nil) // HID ErrorRollOver is not a key.
        assert(KeyboardEvents.keyID(forUsage: 0x32) == nil) // Non-US key absent from ANSI-104.
        assert(KeyboardEvents.keyID(forUsage: 0x66) == nil) // Power is outside this layout.
        assert(KeyboardEvents.keyID(forUsage: 0x35) == "Backquote")
        assert(KeyboardEvents.keyID(forUsage: 0x28) == "Enter")
        assert(KeyboardEvents.keyID(forUsage: 0x58) == "NumpadEnter")
        assert(KeyboardEvents.keyID(forUsage: 0xE1) == "ShiftLeft")
        assert(KeyboardEvents.keyID(forUsage: 0xE5) == "ShiftRight")
        print("PASS: unsupported usages are ignored; physical key variants remain distinct")
        for name in BluetoothKeyboardIdentity.names {
            assert(BluetoothKeyboardIdentity.matches(name: name, transport: "Bluetooth Low Energy"))
            assert(BluetoothKeyboardIdentity.matches(name: name, transport: "BluetoothLowEnergy"))
            assert(!BluetoothKeyboardIdentity.matches(name: name, transport: "USB"))
            assert(!BluetoothKeyboardIdentity.matches(name: name, transport: "Bluetooth"))
        }
        assert(!BluetoothKeyboardIdentity.matches(name: "Other keyboard", transport: "Bluetooth Low Energy"))
        print("PASS: both macOS BLE transport labels match the three GMK104 slots; other names and transports are rejected")
        // No monitor is started and no Input Monitoring permission is requested.
    }
}
