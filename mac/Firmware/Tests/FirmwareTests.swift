import Foundation

private final class MockFirmware: FirmwareSession {
    var sent: [[UInt8]] = []
    var closed = false
    var source: UInt32 = FirmwareTarget.stock.crc
    var failAt: Int?
    var malformedAt: Int?
    var finalCode: UInt8 = 0
    func exchange(_ packet: [UInt8], timeout: TimeInterval) throws -> [UInt8] {
        sent.append(packet)
        if sent.count == failAt { throw ControllerError.message("Injected timeout") }
        if sent.count == malformedAt { return [5, 2, 3, 0, 6, 255, 9] + [UInt8](repeating: 0, count: 57) }
        if packet[1] == 1 {
            var result = [UInt8](repeating: 0, count: 64)
            result.replaceSubrange(0..<4, with: [5, 1, 8, 0])
            for i in 0..<4 { result[8 + i] = UInt8(truncatingIfNeeded: source >> (8 * i)) }
            return result
        }
        if Array(packet.prefix(6)) == [5, 2, 6, 0, 2, 255] {
            return [5, 2, 3, 0, 6, 255, finalCode] + [UInt8](repeating: 0, count: 57)
        }
        return [5, 2] + [UInt8](repeating: 0, count: 62)
    }
    func close() { closed = true }
}
@main struct FirmwareTests {
    static func rejects(_ action: () throws -> Void) { do { try action(); assertionFailure("Expected rejection") } catch {} }
    static func main() throws {
        for target in FirmwareTarget.allCases {
            let image = try Data(contentsOf: URL(fileURLWithPath: "mac/Firmware/Resources/\(target.file)"))
            let plan = try FirmwarePlan(target: target, data: image)
            assert(plan.streamHash == target.streamHash && plan.paddedHash == target.paddedHash)
            assert(plan.reports.count == 2922 && plan.start.count == 64 && plan.end.count == 64)
            var corrupted = image; corrupted[100] ^= 1
            rejects { _ = try FirmwarePlan(target: target, data: corrupted) }
            rejects { _ = try FirmwarePlan(target: target, data: image.dropLast()) }
            let session = MockFirmware(); session.source = target == .custom ? FirmwareTarget.stock.crc : FirmwareTarget.custom.crc
            try FirmwareTransfer.run(plan, session: session, sourceCRC: session.source, progress: { _, _ in }, log: { _ in })
            assert(session.closed && Array(session.sent.dropFirst(2)) == [plan.start] + plan.reports + [plan.end])
            print("PASS: \(target.name) matches exact Windows image/packet golden hashes; every packet sent once in order")
            for failure in [3, 4, 100, 2924, 2925] {
                let fault = MockFirmware(); fault.source = session.source; fault.failAt = failure
                rejects { try FirmwareTransfer.run(plan, session: fault, sourceCRC: fault.source, progress: { _, _ in }, log: { _ in }) }
                assert(fault.closed && fault.sent.count == failure && !fault.sent.contains(plan.end))
            }
            let invalid = MockFirmware(); invalid.source = session.source; invalid.malformedAt = 4
            rejects { try FirmwareTransfer.run(plan, session: invalid, sourceCRC: invalid.source, progress: { _, _ in }, log: { _ in }) }
            assert(invalid.sent.count == 4 && invalid.closed)
            let wrong = MockFirmware(); wrong.source = 0xDEADBEEF
            rejects { try FirmwareTransfer.run(plan, session: wrong, sourceCRC: wrong.source, progress: { _, _ in }, log: { _ in }) }
            assert(wrong.sent.count == 2 && !wrong.sent.contains(plan.start))
            let already = MockFirmware(); already.source = target.crc
            rejects { try FirmwareTransfer.run(plan, session: already, sourceCRC: already.source, progress: { _, _ in }, log: { _ in }) }
            assert(already.sent.count == 2)
            let expired = MockFirmware(); expired.source = session.source
            var clockReads = 0
            rejects { try FirmwareTransfer.run(plan, session: expired, sourceCRC: expired.source,
                progress: { _, _ in }, log: { _ in }, clock: { clockReads += 1; return clockReads == 1 ? 0 : 721 }) }
            assert(expired.closed && expired.sent.count == 3 && !expired.sent.contains(plan.end))
            let finalFailure = MockFirmware(); finalFailure.source = session.source; finalFailure.finalCode = 9
            rejects { try FirmwareTransfer.run(plan, session: finalFailure, sourceCRC: finalFailure.source, progress: { _, _ in }, log: { _ in }) }
            let unknownEnd = MockFirmware(); unknownEnd.source = session.source; unknownEnd.failAt = 2926
            try FirmwareTransfer.run(plan, session: unknownEnd, sourceCRC: unknownEnd.source, progress: { _, _ in }, log: { _ in })
            assert(unknownEnd.sent.count == 2926 && unknownEnd.closed)
        }
        assert(FirmwareTarget.stock.accepts(source: 0xC077F2F5) && !FirmwareTarget.custom.accepts(source: 0xC077F2F5))
        print("PASS: malformed acknowledgments, bad identity, retired-image transitions and uncertain writes stop; no retry or premature activation")
    }
}
