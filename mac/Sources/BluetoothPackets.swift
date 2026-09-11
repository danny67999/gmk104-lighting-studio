import Foundation

/// The dedicated v0.3 GATT characteristic uses 20-byte ATT values. RGB v0.2
/// replies use only 19 bytes; padding here preserves the existing full verifier.
enum BluetoothPackets {
    static let service = "CC731D20-572D-4CEB-91A6-856F9F2DC104"
    static let characteristic = "CC731D21-572D-4CEB-91A6-856F9F2DC104"
    static func writes(for p: [UInt8]) throws -> [[UInt8]] {
        try require(p.count >= 4 && p[1] == 3, "Unsupported Bluetooth lighting command.")
        if p[0] == 8 {
            try require(p.count == 4 && ((p[2] == 5 && p[3] < 104) || (p[2] == 6 && p[3] == 1)), "Invalid Bluetooth lighting query.")
            return [p]
        }
        try require(p[0] == 7, "Bluetooth only accepts lighting and sleep controls.")
        if p[2] == 5 {
            try require(p.count >= 5, "Incomplete RGB packet.")
            let start = Int(p[3]), count = Int(p[4])
            try require(start < 104 && count <= 9 && start + count <= 104 && p.count == 5 + count * 3,
                        "Invalid Bluetooth RGB range.")
            if count == 0 { try require(start == 0, "Invalid clear command."); return [p] }
            return stride(from: 0, to: count, by: 5).map { offset in
                let length = min(5, count - offset)
                return [7,3,5,UInt8(start + offset),UInt8(length)] + Array(p[(5 + offset * 3)..<(5 + (offset + length) * 3)])
            }
        }
        if p[2] == 6 {
            try require(p.count == 6 && p[3] == 1, "Invalid sleep command.")
            let seconds = Int(p[4]) | Int(p[5]) << 8
            try require(seconds == 0 || (60...3600).contains(seconds), "Sleep time must be 1–60 minutes or Never.")
        } else {
            try require(p.count == 4 && ((p[2] == 1 && p[3] <= 4) || (p[2] == 2 && p[3] <= 18)), "Invalid Bluetooth effect or brightness.")
        }
        return [p]
    }
    static func reply(_ value: [UInt8]) throws -> [UInt8] {
        try require(value.count == 20, "Invalid Bluetooth lighting response length.")
        return value + Array(repeating: 0, count: 12)
    }
}
