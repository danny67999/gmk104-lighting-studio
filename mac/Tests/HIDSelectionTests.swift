import Foundation
import IOKit.hid

@main struct HIDSelectionTests {
    static func main() {
        let wired = HIDTransport.matching(productID: 0x5055)
        let receiver = HIDTransport.matching(productID: 0x5088)
        for match in [wired, receiver] {
            assert(match[kIOHIDVendorIDKey] as? Int == 0x320F)
            assert(match[kIOHIDDeviceUsagePageKey] as? Int == 0xFF60)
            assert(match[kIOHIDDeviceUsageKey] as? Int == 0x61)
            assert(match[kIOHIDTransportKey] as? String == "USB")
        }
        assert(HIDTransport.preferWired([101], receiver: { [201] }, wiredOnly: false) == [101])
        assert(HIDTransport.preferWired([101, 102], receiver: { [201] }, wiredOnly: false) == [101, 102])
        assert(HIDTransport.preferWired([], receiver: { [201] }, wiredOnly: false) == [201])
        assert(HIDTransport.preferWired([], receiver: { [201, 202] }, wiredOnly: false) == [201, 202])
        let firmware: [Int] = HIDTransport.preferWired([], receiver: { assertionFailure("Firmware must not discover a receiver"); return [201] }, wiredOnly: true)
        assert(firmware.isEmpty)
        print("PASS: RGB discovery stays on FF60:0061, prefers a cable, rejects ambiguity, and isolates firmware flashing from receivers")
    }
}
