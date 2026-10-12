import Foundation

@main struct FirmwareStorageSurveyTests {
    static func rejects(_ action: () throws -> Void) {
        do { try action(); fatalError("Expected a rejected diagnostic reply") } catch {}
    }
    static func main() throws {
        let blank = [UInt8](repeating: 0xff, count: 4096)
        var used = blank
        used[2048] = 0x31
        var source = [blank, used]
        var requests: [[UInt8]] = []
        var checks = 0
        func answer(_ request: [UInt8]) -> [UInt8] {
            requests.append(request)
            precondition(request.count == 8 && Array(request.prefix(4)) == [8, 3, 7, 6])
            let slot = Int(request[4]), offset = Int(request[5]) | Int(request[6]) << 8
            let count = Int(request[7])
            var reply = [UInt8](repeating: 0, count: 32)
            reply.replaceSubrange(0..<8, with: [8, 3, 7, 6] + Array("GMKD".utf8))
            reply[8] = 1; reply[10] = request[4]; reply[11] = request[5]
            reply[12] = request[6]; reply[13] = request[7]
            if slot == 0 {
                reply.replaceSubrange(14..<25, with: [0xef, 0x40, 0x14, 0, 0x14, 0, 0xc0, 8, 0, 0xd0, 8])
            } else {
                reply.replaceSubrange(14..<(14 + count), with: source[slot - 1][offset..<(offset + count)])
            }
            return reply
        }
        let result = try FirmwareStorageSurvey.run(
            exchange: { answer($0) }, checkConnection: { checks += 1 }, progress: { _, _ in })
        assert(result.jedec == 0x001440ef && result.capacityMB == 1)
        assert(result.sectors.map(\.address) == [0x8c000, 0x8d000])
        assert(result.sectors.map(\.erased) == [true, false])
        assert(result.sectors.map(\.allocationRecognized) == [true, false])
        assert(result.sectors.map(\.sha256) == source.map(FirmwarePlan.sha))
        assert(requests.count == 457 && requests.allSatisfy { Array($0.prefix(4)) == [8, 3, 7, 6] })
        assert(checks >= 3)
        rejects {
            _ = try FirmwareStorageSurvey.run(exchange: { request in
                var reply = answer(request)
                reply[9] = 1
                return reply
            }, checkConnection: {}, progress: { _, _ in })
        }
        rejects {
            _ = try FirmwareStorageSurvey.run(exchange: { request in
                var reply = answer(request)
                reply[19] = 1
                return reply
            }, checkConnection: {}, progress: { _, _ in })
        }
        rejects {
            _ = try FirmwareStorageSurvey.run(exchange: { request in
                var reply = answer(request)
                if request[4] == 1 { reply[11] ^= 1 }
                return reply
            }, checkConnection: {}, progress: { _, _ in })
        }
        let owner: [UInt8] = Array("GMK104-PROFILE-1".utf8) +
            [0, 0xc0, 8, 0, 0, 0xd0, 8, 0, 0x85, 0x60, 0x14, 0, 0x47, 0x4d, 0x4b, 0x4f]
        var owned = used
        owned.replaceSubrange(3968..<4000, with: owner)
        var interrupted = blank
        interrupted.replaceSubrange(3968..<3976, with: owner.prefix(8))
        source = [owned, interrupted]
        let recognized = try FirmwareStorageSurvey.run(exchange: answer, checkConnection: {}, progress: { _, _ in })
        assert(recognized.sectors.allSatisfy(\.allocationRecognized))
        interrupted[2000] = 1
        source = [owned, interrupted]
        let foreign = try FirmwareStorageSurvey.run(exchange: answer, checkConnection: {}, progress: { _, _ in })
        assert(foreign.sectors.map(\.allocationRecognized) == [true, false])
        print("PASS: pre-update reads recognize owned or blank allocations and refuse unfamiliar nonblank data")
        print("PASS: read-only survey reconstructs two 4 KB sectors and validates device identity, bounds, and every reply")
    }
}
