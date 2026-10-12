import Foundation

/// A deliberately read-only client for the local v0.8 diagnostic command.
/// It never sends a profile, OTA, flash erase, or flash program request.
struct FirmwareStorageSurvey {
    struct Sector: Equatable {
        let address: UInt32
        let erased: Bool
        let sha256: String
        let allocationRecognized: Bool
    }
    struct Result: Equatable {
        let jedec: UInt32
        let capacityMB: Int
        let sectors: [Sector]
        var description: String {
            let state = sectors.map { $0.erased ? "blank" : "contains data" }.joined(separator: ", ")
            return "Flash read completed (\(capacityMB) MB). Proposed sectors: \(state). A blank read alone does not prove that storage is safe to use."
        }
    }

    static func run(exchange: ([UInt8]) throws -> [UInt8],
                    checkConnection: () throws -> Void,
                    progress: (Double, String) -> Void) throws -> Result {
        let prefix: [UInt8] = [8, 3, 7, 6]
        func response(slot: UInt8, offset: Int, count: Int) throws -> [UInt8] {
            try require(offset >= 0 && offset < 4096 && count >= 0 && count <= 18 && offset + count <= 4096,
                        "Storage read request is outside the two proposed sectors.")
            let request = prefix + [slot, UInt8(truncatingIfNeeded: offset), UInt8(truncatingIfNeeded: offset >> 8), UInt8(count)]
            let reply = try exchange(request)
            try require(reply.count == 32 && Array(reply.prefix(8)) == prefix + Array("GMKD".utf8) &&
                        reply[8] == 1 && reply[9] == 0 && reply[10] == slot &&
                        reply[11] == request[5] && reply[12] == request[6] && reply[13] == request[7],
                        "Storage diagnostic returned a missing or mismatched reply. No data was saved.")
            return reply
        }

        try checkConnection()
        let info = try response(slot: 0, offset: 0, count: 0)
        let jedec = FirmwarePlan.uint32(info, at: 14)
        let capacityCode = Int(info[18])
        try require(capacityCode == Int((jedec >> 16) & 0xff) && (0x14...0x16).contains(capacityCode),
                    "The keyboard reported an unsupported flash capacity.")
        let addresses: [UInt32] = [0x8C000, 0x8D000]
        for (index, address) in addresses.enumerated() {
            let start = 19 + index * 3
            let reported = UInt32(info[start]) | UInt32(info[start + 1]) << 8 | UInt32(info[start + 2]) << 16
            try require(reported == address, "Diagnostic sector addresses do not match the reviewed firmware.")
        }
        try require(info[25...31].allSatisfy { $0 == 0 }, "Unexpected diagnostic metadata.")
        let capacityMB = 1 << (capacityCode - 0x14)
        var sectors: [Sector] = []
        for (index, address) in addresses.enumerated() {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(4096)
            for offset in stride(from: 0, to: 4096, by: 18) {
                if offset % (18 * 16) == 0 { try checkConnection() }
                let count = min(18, 4096 - offset)
                let reply = try response(slot: UInt8(index + 1), offset: offset, count: count)
                try require(reply[(14 + count)..<32].allSatisfy { $0 == 0 },
                            "Storage diagnostic returned unexpected trailing data.")
                bytes += reply[14..<(14 + count)]
                if offset % (18 * 16) == 0 {
                    progress(Double(index * 4096 + offset) / 8192,
                             "Reading proposed storage sector \(index + 1) of 2. Nothing is being written.")
                }
            }
            try require(bytes.count == 4096, "Storage diagnostic returned an incomplete sector.")
            let reservation: [UInt8] = Array("GMK104-PROFILE-1".utf8) +
                [0, 0xc0, 8, 0, 0, 0xd0, 8, 0, 0x85, 0x60, 0x14, 0, 0x47, 0x4d, 0x4b, 0x4f]
            let erased = bytes.allSatisfy { $0 == 0xff }
            let marker = Array(bytes[3968..<4000])
            let complete = marker == reservation
            let partial = zip(marker, reservation).allSatisfy { ($0 & $1) == $1 } &&
                bytes[0..<3968].allSatisfy { $0 == 0xff } && bytes[4000..<4096].allSatisfy { $0 == 0xff }
            sectors.append(Sector(address: address, erased: erased,
                                  sha256: FirmwarePlan.sha(bytes),
                                  allocationRecognized: erased || complete || partial))
        }
        try checkConnection()
        progress(1, "Read-only storage survey complete.")
        return Result(jedec: jedec, capacityMB: capacityMB, sectors: sectors)
    }
}
