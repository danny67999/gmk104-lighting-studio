import Foundation

/// Sends small sensor measurements to an already active onboard profile.
/// The keyboard renders its own LEDs; no RGB frames or audio leave the Mac.
struct OnboardTelemetry {
    let transport: ReportTransport
    let activeLength: Int
    let activeCRC: UInt32

    init(transport: ReportTransport) throws {
        try require(transport.connectionName == "USB" && !transport.reconnectsWithoutReplug,
                    "On-keyboard music and temperature updates currently require wired USB.")
        try transport.checkSingleDevice()
        _ = try RGBClient(transport).read()
        let reply = try transport.exchange([8, 3, 7, 0])
        try require(reply.count == 32 && Array(reply[0..<4]) == [8, 3, 7, 0] &&
                    Array(reply[4..<8]) == Array("GMKU".utf8) && reply[8] == 1 &&
                    reply[9] & 0b101 == 0b101 && reply[13] == 0 &&
                    (reply[20] == 0 || (9..<OnboardProfile.effectIDs.count).contains(Int(reply[20]))) &&
                    reply[21..<32].allSatisfy { $0 == 0 },
                    "This keyboard firmware cannot accept on-keyboard sensor updates.")
        let length = Int(reply[14]) | Int(reply[15]) << 8
        try require((344...OnboardProfile.maximumSize).contains(length),
                    "No on-keyboard lighting layout is active.")
        self.transport = transport
        self.activeLength = length
        self.activeCRC = Self.u32(reply, 16)
    }

    func sendMusic(bass: Double, mid: Double, treble: Double, level: Double) throws {
        let values = try [bass, mid, treble, level].map { value -> UInt8 in
            try require(value.isFinite && (0...1).contains(value), "Invalid music level for the keyboard.")
            return UInt8((value * 255).rounded())
        }
        try send(operation: 8, values: values)
    }

    func sendTemperature(celsius: Double) throws {
        try require(celsius.isFinite && (1...125).contains(celsius),
                    "Invalid CPU temperature for the keyboard.")
        let scaled = UInt16((celsius * 100).rounded())
        try send(operation: 9, values: [UInt8(truncatingIfNeeded: scaled), UInt8(truncatingIfNeeded: scaled >> 8)])
    }

    private func send(operation: UInt8, values: [UInt8]) throws {
        try transport.checkSingleDevice()
        let reply = try transport.exchange([7, 3, 7, operation] + values)
        try require(reply.count == 32 && Array(reply[0..<4]) == [7, 3, 7, operation] &&
                    Array(reply[4..<8]) == Array("GMKU".utf8) && reply[8] == 1 && reply[9] == 0 &&
                    reply[10..<14].allSatisfy { $0 == 0 } &&
                    (Int(reply[14]) | Int(reply[15]) << 8) == activeLength &&
                    Self.u32(reply, 16) == activeCRC && reply[20..<32].allSatisfy { $0 == 0 },
                    "The keyboard did not acknowledge the sensor update for its active layout.")
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
