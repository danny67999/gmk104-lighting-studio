import Foundation

/// Host half of the wired profile-upload protocol. Persistent upload is only
/// offered when the connected firmware explicitly advertises and verifies it.
struct OnboardUploader {
    static let family: [UInt8] = [3, 7]
    static let magic: [UInt8] = Array("GMKU".utf8)
    static let version: UInt8 = 1
    static let persistentFlags: UInt8 = 0b111 // RAM staging, persistent save, readback
    static let volatileFlags: UInt8 = 0b101 // RAM staging and readback
    static let maximumChunk = 21
    static let maximumRead = 19

    struct Receipt: Equatable {
        let length: Int
        let crc32: UInt32
        let chunks: Int
        let persistent: Bool
    }
    struct SupportedModes: Equatable {
        let volatile: Bool
        let persistent: Bool
        let maximumEffectID: Int
        let activeProfileLength: Int
    }
    private struct Capabilities {
        let flags: UInt8
        let maxLength: Int
        let chunkSize: Int
        let activationPending: Bool
        let activeLength: Int
        let activeCRC: UInt32
        let maximumEffectID: Int
    }

    let transport: ReportTransport
    let session: UInt32

    init(transport: ReportTransport, session: UInt32 = UInt32.random(in: 1...UInt32.max)) {
        self.transport = transport
        self.session = session
    }

    /// Read-only availability check for the Lighting Studio preview button.
    /// A pre-v1 reply means unavailable; a disconnected transport still throws.
    func supportsVolatile() throws -> Bool {
        try supportedModes().volatile
    }

    func supportedModes() throws -> SupportedModes {
        guard transport.connectionName == "USB" && !transport.reconnectsWithoutReplug else {
            return SupportedModes(volatile: false, persistent: false, maximumEffectID: 8, activeProfileLength: 0)
        }
        try transport.checkSingleDevice()
        _ = try RGBClient(transport).read()
        guard let caps = Self.parseCapabilities(try transport.exchange([8, 3, 7, 0])) else {
            return SupportedModes(volatile: false, persistent: false, maximumEffectID: 8, activeProfileLength: 0)
        }
        let valid = (1...OnboardProfile.maximumSize).contains(caps.maxLength) &&
            (1...Self.maximumChunk).contains(caps.chunkSize) && !caps.activationPending
        return SupportedModes(volatile: valid && caps.flags & Self.volatileFlags == Self.volatileFlags,
                              persistent: valid && caps.flags & Self.persistentFlags == Self.persistentFlags,
                              maximumEffectID: caps.maximumEffectID,
                              activeProfileLength: valid && (344...OnboardProfile.maximumSize).contains(caps.activeLength) && caps.activeLength <= caps.maxLength ? caps.activeLength : 0)
    }

    func upload(_ profile: OnboardProfile, progress: ((Int, Int) -> Void)? = nil) throws -> Receipt {
        try transfer(profile, persistent: true, progress: progress)
    }

    /// Preview a profile in RAM for hardware validation. It expires when the
    /// keyboard reboots and never invokes the flash commit operation.
    func activateVolatile(_ profile: OnboardProfile, progress: ((Int, Int) -> Void)? = nil) throws -> Receipt {
        try transfer(profile, persistent: false, progress: progress)
    }

    private func transfer(_ profile: OnboardProfile, persistent: Bool,
                          progress: ((Int, Int) -> Void)?) throws -> Receipt {
        try profile.validate()
        try require(transport.connectionName == "USB" && !transport.reconnectsWithoutReplug,
                    "Connect the GMK104 directly by USB to save a layout on the keyboard.")
        try transport.checkSingleDevice()
        _ = try RGBClient(transport).read() // Existing custom-firmware identity gate.
        let caps = try capabilities()
        try require(!caps.activationPending,
                    "The keyboard is still activating its previous layout. Try again shortly.")
        let needed = persistent ? Self.persistentFlags : Self.volatileFlags
        try require(caps.flags & needed == needed &&
                    (1...OnboardProfile.maximumSize).contains(caps.maxLength) &&
                    (1...Self.maximumChunk).contains(caps.chunkSize),
                    "This keyboard firmware cannot safely save and read back lighting layouts.")
        try require(profile.maximumEffectID <= caps.maximumEffectID,
                    "This keyboard firmware does not support one or more effects in this profile. Install compatible firmware before sending it.")
        let data = profile.bytes
        try require(data.count <= caps.maxLength, "This layout is too large for the keyboard firmware.")
        let digest = OnboardProfile.crc32(data)
        let start = [UInt8(7), 3, 7, 1] + Self.le32(session) + Self.le16(data.count) + Self.le32(digest)
        try expectAcknowledgment(try transport.exchange(start), operation: 1, nextOffset: 0)

        var offset = 0
        var chunks = 0
        while offset < data.count {
            let count = min(caps.chunkSize, data.count - offset)
            let request = [UInt8(7), 3, 7, 2] + Self.le32(session) + Self.le16(offset) +
                [UInt8(count)] + Array(data[offset..<(offset + count)])
            let next = offset + count
            try expectAcknowledgment(try transport.exchange(request), operation: 2, nextOffset: next)
            offset = next; chunks += 1
            progress?(offset, data.count)
        }
        try transport.checkSingleDevice()
        try expectAcknowledgment(try transport.exchange([7, 3, 7, 3] + Self.le32(session)),
                                 operation: 3, nextOffset: data.count, digest: digest)
        try transport.checkSingleDevice()
        // The vendor effect scheduler invokes the profile renderer only while
        // effect 20 is selected. Change it after full validation, immediately
        // before activation, so a transfer error preserves current lighting.
        let lighting = RGBClient(transport)
        if try lighting.read().effect != 20 { try lighting.effect(20) }
        // A lost persistent commit reply is indeterminate; never resend it.
        let finish: UInt8 = persistent ? 4 : 7
        try expectAcknowledgment(try transport.exchange([7, 3, 7, finish] + Self.le32(session)),
                                 operation: finish, nextOffset: data.count, digest: digest)

        var after: Capabilities? = nil
        for attempt in 0..<25 {
            try transport.checkSingleDevice()
            let latest = try capabilities()
            after = latest
            if !latest.activationPending { break }
            if attempt < 24 { Thread.sleep(forTimeInterval: 0.02) }
        }
        try require(after?.activationPending == false,
                    "The layout transferred, but the keyboard has not confirmed that it started playing it. Reconnect and inspect before retrying.")
        try require(after?.activeLength == data.count && after?.activeCRC == digest,
                    "The keyboard did not report the saved layout after the upload.")
        var readback = [UInt8](); readback.reserveCapacity(data.count)
        while readback.count < data.count {
            let start = readback.count
            let count = min(Self.maximumRead, data.count - start)
            let reply = try transport.exchange([8, 3, 7, 5] + Self.le16(start) + [UInt8(count)])
            try require(reply.count == 32 && Array(reply[0..<4]) == [8, 3, 7, 5] &&
                        Array(reply[4..<8]) == Self.magic && reply[8] == Self.version && reply[9] == 0 &&
                        Self.u16(reply, 10) == start && Int(reply[12]) == count,
                        "The keyboard returned an invalid saved-layout readback.")
            readback += reply[13..<(13 + count)]
        }
        try require(readback == data, "The saved keyboard layout differs from the one sent.")
        return Receipt(length: data.count, crc32: digest, chunks: chunks, persistent: persistent)
    }

    private func capabilities() throws -> Capabilities {
        let reply = try transport.exchange([8, 3, 7, 0])
        guard let result = Self.parseCapabilities(reply) else {
            throw ControllerError.message("Custom-layout upload requires newer GMK104 firmware; v0.6 does not support it.")
        }
        return result
    }

    private static func parseCapabilities(_ reply: [UInt8]) -> Capabilities? {
        guard reply.count == 32 && Array(reply[0..<4]) == [8, 3, 7, 0] &&
            Array(reply[4..<8]) == magic && reply[8] == version &&
            reply[13] <= 1 && (reply[20] == 0 || ((9...24).contains(Int(reply[20])) || reply[20] == 26)) &&
            reply[21..<32].allSatisfy({ $0 == 0 }) else { return nil }
        return Capabilities(flags: reply[9], maxLength: Self.u16(reply, 10), chunkSize: Int(reply[12]),
                            activationPending: reply[13] != 0,
                            activeLength: Self.u16(reply, 14), activeCRC: Self.u32(reply, 16),
                            maximumEffectID: reply[20] == 0 ? 8 : Int(reply[20]))
    }

    private func expectAcknowledgment(_ reply: [UInt8], operation: UInt8, nextOffset: Int,
                                      digest: UInt32? = nil) throws {
        try require(reply.count == 32 && Array(reply[0..<4]) == [7, 3, 7, operation] &&
                    Array(reply[4..<8]) == Self.magic && reply[8] == Self.version && reply[9] == 0 &&
                    Self.u32(reply, 10) == session && Self.u16(reply, 14) == nextOffset &&
                    (digest == nil || Self.u32(reply, 16) == digest),
                    "The keyboard did not acknowledge the lighting-layout transfer exactly.")
    }

    private static func le16(_ value: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }
    private static func le32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    private static func u16(_ p: [UInt8], _ offset: Int) -> Int {
        Int(p[offset]) | Int(p[offset + 1]) << 8
    }
    private static func u32(_ p: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(p[offset]) | UInt32(p[offset + 1]) << 8 | UInt32(p[offset + 2]) << 16 |
            UInt32(p[offset + 3]) << 24
    }
}
