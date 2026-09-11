import Foundation
import CryptoKit

enum FirmwareTarget: String, CaseIterable, Identifiable {
    case custom, stock
    var id: String { rawValue }
    var name: String { self == .custom ? "Custom RGB v0.2" : "Stock firmware" }
    var file: String { self == .custom ? "GMK104-custom-RGB-v0.2-experimental.bin" : "GMK104-stock-recovery.bin" }
    var crc: UInt32 { self == .custom ? 0xC6342859 : 0xB85531A2 }
    var hash: String { self == .custom ? "96E431887F574CBE01E900FF08A803D8351EDE421A982809E294F34B1E7F0FD4" : "FD6E3E8B9D67E2E4942634FCB5C44275F1B1B4F6975F1691318C5A1D44E1661F" }
    var streamHash: String { self == .custom ? "1565181114783AB9ED0E12EE4A5CC1366DD1412A1F36FEE7628926140377C0A7" : "818CF184FCE29532363DF592AAE2ADAAAB0AFEA345D99667240E5BA96302950A" }
    var paddedHash: String { self == .custom ? "C68E839209350A16D4802533C204E49DF3201E5F59F6BB74FC1602BB2D5FCB91" : "484FA932018A18A22EA7E536D07F0B19A27DBE5D0F8F8B24E9BFD3A495F3BFD7" }
    var phrase: String { self == .custom ? "FLASH GMK104 CUSTOM C6342859" : "RESTORE GMK104 STOCK B85531A2" }
    func accepts(source: UInt32) -> Bool { self == .custom ? source == FirmwareTarget.stock.crc : [FirmwareTarget.custom.crc, 0xC077F2F5].contains(source) }
}
struct FirmwarePlan {
    let target: FirmwareTarget
    let start: [UInt8]
    let reports: [[UInt8]]
    let end: [UInt8]
    let imageHash: String
    let streamHash: String
    let paddedHash: String

    init(target: FirmwareTarget, data: Data) throws {
        self.target = target
        let bytes = [UInt8](data)
        imageHash = Self.sha(bytes)
        try require(bytes.count == 140244 && imageHash == target.hash, "The approved \(target.name) image is missing or modified.")
        try require(Self.uint32(bytes, at: 0x18) == UInt32(bytes.count) && Array(bytes[0x20..<0x24]) == Array("KNLT".utf8), "Invalid firmware header.")
        try require(Self.uint32(bytes, at: bytes.count - 4) == target.crc && Self.crc32(Array(bytes.dropLast(4))) == target.crc && Self.crc32(bytes) == 0, "Firmware CRC verification failed.")
        let chunks = (bytes.count + 15) / 16
        let padded = bytes + [UInt8](repeating: 255, count: chunks * 16 - bytes.count)
        paddedHash = Self.sha(padded)
        func packet(_ prefix: [UInt8]) -> [UInt8] { prefix + [UInt8](repeating: 255, count: 64 - prefix.count) }
        start = packet([5, 2, 2, 0, 1, 255])
        var packets: [[UInt8]] = []
        var rebuilt = [UInt8]()
        for first in stride(from: 0, to: chunks, by: 3) {
            let count = min(3, chunks - first)
            var report = packet([5, 2, UInt8(20 * count), 0])
            for slot in 0..<count {
                let index = first + slot
                let crcBytes = [UInt8(truncatingIfNeeded: index), UInt8(index >> 8)] + Array(padded[index * 16..<(index + 1) * 16])
                let crc = Self.crc16(crcBytes)
                let block = crcBytes + [UInt8(truncatingIfNeeded: crc), UInt8(crc >> 8)]
                report.replaceSubrange(4 + slot * 20..<24 + slot * 20, with: block)
                rebuilt += crcBytes.dropFirst(2)
            }
            packets.append(report)
        }
        reports = packets
        let last = UInt16(chunks - 1), inverse = UInt16(0) &- last
        end = packet([5, 2, 6, 0, 2, 255, UInt8(truncatingIfNeeded: last), UInt8(last >> 8), UInt8(truncatingIfNeeded: inverse), UInt8(inverse >> 8)])
        streamHash = Self.sha(start + packets.flatMap { $0 } + end)
        try require(chunks == 8766 && packets.count == 2922 && last == 0x223D && padded.count - bytes.count == 12 && rebuilt == padded,
                    "The OTA packet plan could not reconstruct the approved image.")
        try require(paddedHash == target.paddedHash && streamHash == target.streamHash,
                    "The Mac OTA packet stream differs from the verified Windows flasher.")
    }
    static func sha(_ data: [UInt8]) -> String { SHA256.hash(data: Data(data)).map { String(format: "%02X", $0) }.joined() }
    static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc = UInt32.max
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
        }
        return crc
    }
    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc = UInt16.max
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }
    static func version(_ first: [UInt8], _ second: [UInt8]) throws -> UInt32 {
        try require(first.count == 64 && first == second && Array(first.prefix(4)) == [5, 1, 8, 0], "The keyboard returned inconsistent or malformed firmware identity.")
        try require(uint32(first, at: 4) == 0, "The keyboard firmware version field is not approved.")
        let crc = uint32(first, at: 8)
        try require([FirmwareTarget.custom.crc, FirmwareTarget.stock.crc, 0xC077F2F5].contains(crc), String(format: "Unapproved installed firmware CRC %08X. No flashing is allowed.", crc))
        return crc
    }
    static func intermediateAck(_ response: [UInt8]) throws {
        try require(response.count == 64 && Array(response.prefix(2)) == [5, 2], "Invalid OTA acknowledgment. Transfer stopped; do not retry automatically.")
        try require(Array(response.prefix(6)) != [5, 2, 3, 0, 6, 255], "Unexpected final status during the upload. Transfer stopped.")
    }
    static func finalAck(_ response: [UInt8]) throws -> Bool {
        guard response.count == 64, Array(response.prefix(6)) == [5, 2, 3, 0, 6, 255] else { return false }
        try require(response[6] == 0, "Firmware activation failed with code \(response[6]). Do not retry automatically.")
        return true
    }
}

protocol FirmwareSession: AnyObject {
    func exchange(_ packet: [UInt8], timeout: TimeInterval) throws -> [UInt8]
    func close()
}
struct FirmwareTransfer {
    /// Exactly one send per packet. An uncertain START or data write is terminal.
    /// An uncertain END can only be resolved by a fresh post-reboot inspection.
    static func run(_ plan: FirmwarePlan, session: FirmwareSession, sourceCRC: UInt32,
                    progress: (Double, String) -> Void, log: (String) -> Void,
                    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) throws {
        defer { session.close() }
        let query: [UInt8] = [5, 1] + [UInt8](repeating: 0, count: 62)
        let source = try FirmwarePlan.version(session.exchange(query, timeout: 3), session.exchange(query, timeout: 3))
        try require(source == sourceCRC && plan.target.accepts(source: source), "Installed firmware changed before OTA START. Nothing was flashed.")
        let deadline = clock() + 12 * 60
        log("START SEND")
        try FirmwarePlan.intermediateAck(session.exchange(plan.start, timeout: 5))
        log("START ACK")
        for (index, report) in plan.reports.enumerated() {
            try require(clock() < deadline, "Transfer deadline exceeded. Do not retry automatically.")
            log("DATA SEND \(index + 1)/\(plan.reports.count)")
            try FirmwarePlan.intermediateAck(session.exchange(report, timeout: 10))
            log("DATA ACK \(index + 1)/\(plan.reports.count)")
            if index % 25 == 0 || index == plan.reports.count - 1 {
                progress(Double(index + 1) / Double(plan.reports.count) * 0.95, "Uploading firmware • \(index + 1)/\(plan.reports.count) blocks acknowledged")
            }
        }
        try require(clock() < deadline, "Transfer deadline exceeded before activation. Do not retry automatically.")
        log("END SEND")
        let response: [UInt8]?
        do { response = try session.exchange(plan.end, timeout: 10) }
        catch { response = nil; log("END uncertain: \(error.localizedDescription)") }
        if let response { log(try FirmwarePlan.finalAck(response) ? "END EXACT SUCCESS" : "END UNKNOWN; REBOOT PROOF REQUIRED") }
        progress(0.96, "Waiting for keyboard reboot and firmware verification…")
    }
}
