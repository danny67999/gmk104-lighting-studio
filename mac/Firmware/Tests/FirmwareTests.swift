import Foundation

private final class MockFirmware: FirmwareSession {
    var sent: [[UInt8]] = []
    var closed = false
    var timeouts: [TimeInterval] = []
    var source: UInt32 = FirmwareTarget.stock.crc
    var failAt: Int?
    var malformedAt: Int?
    var finalCode: UInt8 = 0
    func exchange(_ packet: [UInt8], timeout: TimeInterval) throws -> [UInt8] {
        sent.append(packet); timeouts.append(timeout)
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
// Virtual time exercises the production pacing and reply budget without USB
// writes or wall-clock waits. It does not simulate the keyboard's OTA internals.
private final class TimedFirmware: FirmwareSession {
    let mock = MockFirmware()
    var pacing = FirmwareReportPacing(exclusive: true)
    var now: TimeInterval = 0
    var delayedReport: Int?
    var delayedBy: TimeInterval = 0
    func exchange(_ packet: [UInt8], timeout: TimeInterval) throws -> [UInt8] {
        now += pacing.delay(at: now)
        pacing.sent(at: now)
        let reply = try mock.exchange(packet, timeout: timeout)
        let duration = mock.sent.count == delayedReport ? delayedBy : 0.007
        if duration > timeout {
            now += timeout
            throw ControllerError.message("Injected missing reply after timeout")
        }
        now += duration
        pacing.acknowledged(at: now)
        return reply
    }
    func close() { mock.close() }
}
@main struct FirmwareTests {
    static func rejects(_ action: () throws -> Void) { do { try action(); assertionFailure("Expected rejection") } catch {} }
    static func main() throws {
        var uploadPacing = FirmwareReportPacing(exclusive: true)
        assert(uploadPacing.delay(at: 0) == 0)
        uploadPacing.sent(at: 0)
        uploadPacing.acknowledged(at: 0.008)
        assert(abs(uploadPacing.delay(at: 0.016) - 0.008) < 0.000001)
        // A slow reply must still get the full settling interval. No burst can
        // follow a delayed response merely because the send interval expired.
        uploadPacing.sent(at: 1)
        uploadPacing.acknowledged(at: 3)
        assert(abs(uploadPacing.delay(at: 3) - 0.016) < 0.000001)
        assert(uploadPacing.delay(at: 4) == 0)
        var readPacing = FirmwareReportPacing(exclusive: false)
        readPacing.sent(at: 0); readPacing.acknowledged(at: 0.008)
        assert(abs(readPacing.delay(at: 0.008) - 0.008) < 0.000001)
        assert(readPacing.delay(at: 0.016) == 0)
        print("PASS: upload settling applies after fast and slow replies; passive query pacing is unchanged")
        for target in FirmwareTarget.allCases {
            let image = try Data(contentsOf: URL(fileURLWithPath: "mac/Firmware/Resources/\(target.file)"))
            let plan = try FirmwarePlan(target: target, data: image)
            assert(plan.streamHash == target.streamHash && plan.paddedHash == target.paddedHash)
            assert(plan.reports.count == (target.imageSize+47)/48 && plan.start.count == 64 && plan.end.count == 64)
            var corrupted = image; corrupted[100] ^= 1
            rejects { _ = try FirmwarePlan(target: target, data: corrupted) }
            rejects { _ = try FirmwarePlan(target: target, data: image.dropLast()) }
            if target == .nativeRipple {
                assert(!FirmwareTarget.allCases.contains { target.accepts(source: $0.crc) })
                print("PASS: \(target.name) is recognized for read-only inspection but cannot be installed")
                continue
            }
            let session = MockFirmware(); session.source = target == .auroraLighting ? FirmwareTarget.matrixColumns.crc : target == .matrixColumns ? FirmwareTarget.matrixRainVertical.crc : target == .matrixRainVertical ? FirmwareTarget.matrixRainStaggered.crc : target == .matrixRainStaggered ? FirmwareTarget.matrixRainFixed.crc : target == .matrixRainFixed ? FirmwareTarget.matrixLighting.crc : target == .matrixLighting ? FirmwareTarget.reactiveLighting.crc : target == .reactiveLighting ? FirmwareTarget.performanceLighting.crc : target == .performanceLighting ? FirmwareTarget.persistentLighting.crc : (target == .persistentLighting ? FirmwareTarget.storageDiagnosticRollback.crc : (target == .storageDiagnosticRollback ? FirmwareTarget.persistentLighting.crc : (target == .custom ? FirmwareTarget.stock.crc : (target == .streaming ? FirmwareTarget.wireless.crc : (target == .nativeRippleFixed ? FirmwareTarget.nativeRipple.crc : FirmwareTarget.custom.crc)))))
            try FirmwareTransfer.run(plan, session: session, sourceCRC: session.source, progress: { _, _ in }, log: { _ in })
            assert(session.closed && Array(session.sent.dropFirst(2)) == [plan.start] + plan.reports + [plan.end])
            assert(session.timeouts.prefix(2).allSatisfy { $0 == 3 })
            assert(session.timeouts.dropFirst(2).allSatisfy { $0 == 60 })
            if target == .matrixColumns {
                assert(plan.reports.count == 3629)
                let timed = TimedFirmware(); timed.mock.source = FirmwareTarget.reactiveLighting.crc
                try FirmwareTransfer.run(plan, session: timed, sourceCRC: timed.mock.source,
                    progress: { _, _ in }, log: { _ in }, clock: { timed.now })
                assert(timed.mock.closed && Array(timed.mock.sent.dropFirst(2)) == Array(session.sent.dropFirst(2)))
                let expectedDuration = Double(plan.reports.count + 4) * 0.007 + Double(plan.reports.count + 3) * 0.016
                assert(abs(timed.now - expectedDuration) < 0.000001 && timed.now < 85)
                for delayedReport in [3, 4, plan.reports.count + 4] {
                    let late = TimedFirmware(); late.mock.source = timed.mock.source
                    late.delayedReport = delayedReport; late.delayedBy = 45
                    try FirmwareTransfer.run(plan, session: late, sourceCRC: late.mock.source,
                        progress: { _, _ in }, log: { _ in }, clock: { late.now })
                    assert(late.mock.closed && late.mock.sent == timed.mock.sent)
                }
                // Reproduce both observed failure positions. A missing reply
                // still stops before END, with no resend, after the new budget.
                for dataReport in [3388, 3483] {
                    let missing = TimedFirmware(); missing.mock.source = timed.mock.source
                    missing.delayedReport = dataReport + 3; missing.delayedBy = 61
                    rejects { try FirmwareTransfer.run(plan, session: missing, sourceCRC: missing.mock.source,
                        progress: { _, _ in }, log: { _ in }, clock: { missing.now }) }
                    assert(missing.mock.closed && missing.mock.sent.count == dataReport + 3)
                    assert(!missing.mock.sent.contains(plan.end) && missing.mock.timeouts.last == 60)
                }
                print("PASS: full v1.7 transfer pacing takes 83.543 simulated seconds at 7ms replies; 45s late replies succeed; missing replies stop after 60s without resend or activation")
            }
            print("PASS: \(target.name) matches exact image and independent packet hashes; every packet sent once in order")
            for failure in [3, 4, 100, plan.reports.count+2, plan.reports.count+3] {
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
            let unknownEnd = MockFirmware(); unknownEnd.source = session.source; unknownEnd.failAt = plan.reports.count+4
            try FirmwareTransfer.run(plan, session: unknownEnd, sourceCRC: unknownEnd.source, progress: { _, _ in }, log: { _ in })
            assert(unknownEnd.sent.count == plan.reports.count+4 && unknownEnd.closed)
        }
        assert(FirmwareTarget.publishedCases == [.auroraLighting, .custom, .wireless, .streaming, .stock])
        for legacy in [FirmwareTarget.stock, .custom, .wireless, .streaming] { assert(FirmwareTarget.auroraLighting.accepts(source:legacy.crc)) }
        assert(FirmwareTarget.auroraLighting.accepts(source:FirmwareTarget.matrixColumns.crc))
        assert(FirmwareTarget.matrixColumns.accepts(source:FirmwareTarget.auroraLighting.crc))
        assert(!FirmwareTarget.auroraLighting.accepts(source:FirmwareTarget.auroraLighting.crc))
        assert(!FirmwareTarget.auroraLighting.accepts(source:FirmwareTarget.storageDiagnosticRollback.crc))
        for source in [FirmwareTarget.persistentLighting.crc, FirmwareTarget.performanceLighting.crc, FirmwareTarget.reactiveLighting.crc, FirmwareTarget.matrixLighting.crc, FirmwareTarget.matrixRainFixed.crc, FirmwareTarget.matrixRainStaggered.crc, FirmwareTarget.matrixRainVertical.crc] {
            assert(FirmwareTarget.matrixColumns.accepts(source: source))
        }
        assert(!FirmwareTarget.matrixColumns.accepts(source: FirmwareTarget.storageDiagnosticRollback.crc))
        assert(!FirmwareTarget.matrixColumns.accepts(source: FirmwareTarget.matrixColumns.crc))
        for target in [FirmwareTarget.matrixRainVertical, .matrixRainStaggered, .matrixRainFixed, .matrixLighting, .reactiveLighting, .performanceLighting, .persistentLighting, .stock] {
            assert(target.accepts(source: FirmwareTarget.matrixColumns.crc))
        }
        for source in [FirmwareTarget.persistentLighting.crc, FirmwareTarget.performanceLighting.crc, FirmwareTarget.reactiveLighting.crc, FirmwareTarget.matrixLighting.crc, FirmwareTarget.matrixRainFixed.crc, FirmwareTarget.matrixRainStaggered.crc] {
            assert(FirmwareTarget.matrixRainVertical.accepts(source: source))
        }
        assert(!FirmwareTarget.matrixRainVertical.accepts(source: FirmwareTarget.storageDiagnosticRollback.crc))
        assert(!FirmwareTarget.matrixRainVertical.accepts(source: FirmwareTarget.matrixRainVertical.crc))
        for target in [FirmwareTarget.matrixRainStaggered, .matrixRainFixed, .matrixLighting, .reactiveLighting, .performanceLighting, .persistentLighting, .stock] {
            assert(target.accepts(source: FirmwareTarget.matrixRainVertical.crc))
        }
        for source in [FirmwareTarget.persistentLighting.crc, FirmwareTarget.performanceLighting.crc, FirmwareTarget.reactiveLighting.crc, FirmwareTarget.matrixLighting.crc, FirmwareTarget.matrixRainFixed.crc] {
            assert(FirmwareTarget.matrixRainStaggered.accepts(source: source))
        }
        assert(!FirmwareTarget.matrixRainStaggered.accepts(source: FirmwareTarget.storageDiagnosticRollback.crc))
        assert(!FirmwareTarget.matrixRainStaggered.accepts(source: FirmwareTarget.matrixRainStaggered.crc))
        for target in [FirmwareTarget.matrixRainFixed, .matrixLighting, .reactiveLighting, .performanceLighting, .persistentLighting, .stock] {
            assert(target.accepts(source: FirmwareTarget.matrixRainStaggered.crc))
        }
        for source in [FirmwareTarget.persistentLighting.crc, FirmwareTarget.performanceLighting.crc, FirmwareTarget.reactiveLighting.crc, FirmwareTarget.matrixLighting.crc] {
            assert(FirmwareTarget.matrixRainFixed.accepts(source: source))
        }
        assert(!FirmwareTarget.matrixRainFixed.accepts(source: FirmwareTarget.storageDiagnosticRollback.crc))
        assert(!FirmwareTarget.matrixRainFixed.accepts(source: FirmwareTarget.matrixRainFixed.crc))
        for target in [FirmwareTarget.matrixLighting, .reactiveLighting, .performanceLighting, .persistentLighting, .stock] {
            assert(target.accepts(source: FirmwareTarget.matrixRainFixed.crc))
        }
        assert(FirmwareTarget.matrixLighting.accepts(source: FirmwareTarget.reactiveLighting.crc))
        assert(!FirmwareTarget.matrixLighting.accepts(source: FirmwareTarget.storageDiagnosticRollback.crc))
        assert(FirmwareTarget.reactiveLighting.accepts(source: FirmwareTarget.matrixLighting.crc))
        assert(FirmwareTarget.reactiveLighting.accepts(source: FirmwareTarget.performanceLighting.crc))
        assert(FirmwareTarget.reactiveLighting.accepts(source: FirmwareTarget.persistentLighting.crc))
        assert(!FirmwareTarget.reactiveLighting.accepts(source: FirmwareTarget.storageDiagnosticRollback.crc))
        assert(FirmwareTarget.performanceLighting.accepts(source: FirmwareTarget.reactiveLighting.crc))
        assert(FirmwareTarget.persistentLighting.accepts(source: FirmwareTarget.reactiveLighting.crc))
        assert(FirmwareTarget.performanceLighting.accepts(source: FirmwareTarget.persistentLighting.crc))
        assert(!FirmwareTarget.performanceLighting.accepts(source: FirmwareTarget.storageDiagnosticRollback.crc))
        assert(FirmwareTarget.persistentLighting.accepts(source: FirmwareTarget.performanceLighting.crc))
        assert(FirmwareTarget.persistentLighting.accepts(source: FirmwareTarget.storageDiagnosticRollback.crc))
        assert(!FirmwareTarget.persistentLighting.accepts(source: FirmwareTarget.custom.crc))
        assert(!FirmwareTarget.persistentLighting.accepts(source: FirmwareTarget.stock.crc))
        assert(FirmwareTarget.storageDiagnosticRollback.accepts(source: FirmwareTarget.persistentLighting.crc))
        assert(!FirmwareTarget.storageDiagnosticRollback.accepts(source: FirmwareTarget.custom.crc))
        assert(FirmwareTarget.stock.accepts(source: FirmwareTarget.persistentLighting.crc))
        assert(FirmwareTarget.stock.accepts(source: 0xC077F2F5) && !FirmwareTarget.custom.accepts(source: 0xC077F2F5))
        assert(FirmwareTarget.streaming.accepts(source: FirmwareTarget.wireless.crc))
        assert(!FirmwareTarget.streaming.accepts(source: FirmwareTarget.custom.crc))
        assert(!FirmwareTarget.nativeRipple.accepts(source: FirmwareTarget.wireless.crc))
        assert(!FirmwareTarget.nativeRipple.accepts(source: FirmwareTarget.streaming.crc))
        assert(!FirmwareTarget.nativeRipple.accepts(source: FirmwareTarget.custom.crc))
        assert(!FirmwareTarget.nativeRipple.accepts(source: FirmwareTarget.stock.crc))
        assert(FirmwareTarget.nativeRippleFixed.accepts(source: FirmwareTarget.nativeRipple.crc))
        assert(FirmwareTarget.nativeRippleFixed.accepts(source: FirmwareTarget.wireless.crc))
        assert(FirmwareTarget.nativeRippleFixed.accepts(source: FirmwareTarget.streaming.crc))
        assert(!FirmwareTarget.nativeRippleFixed.accepts(source: FirmwareTarget.custom.crc))
        for rollback in [FirmwareTarget.custom, .wireless, .stock] { assert(rollback.accepts(source: FirmwareTarget.streaming.crc)) }
        for rollback in [FirmwareTarget.custom, .wireless, .stock] { assert(rollback.accepts(source: FirmwareTarget.nativeRipple.crc)) }
        for rollback in [FirmwareTarget.custom, .wireless, .stock] { assert(rollback.accepts(source: FirmwareTarget.nativeRippleFixed.crc)) }
        let connection = MockFirmware()
        var connectionProgress = 0.0
        try FirmwareConnectionCheck.run(session: connection, expectedCRC: connection.source, progress: { value, _ in connectionProgress = value })
        let passiveQuery: [UInt8] = [5, 1] + [UInt8](repeating: 0, count: 62)
        assert(connection.closed && connection.sent.count == 4000 && connection.sent.allSatisfy { $0 == passiveQuery } && connectionProgress == 1)
        let interruptedConnection = MockFirmware(); interruptedConnection.failAt = 1515
        rejects { try FirmwareConnectionCheck.run(session: interruptedConnection, expectedCRC: interruptedConnection.source, progress: { _, _ in }) }
        assert(interruptedConnection.closed && interruptedConnection.sent.count == 1515 && interruptedConnection.sent.allSatisfy { $0 == passiveQuery })
        let changedConnection = MockFirmware()
        rejects { try FirmwareConnectionCheck.run(session: changedConnection, expectedCRC: FirmwareTarget.custom.crc, progress: { _, _ in }) }
        assert(changedConnection.closed && changedConnection.sent.count == 2)
        print("PASS: sustained connection test sends 4,000 passive queries only; timeout or identity change stops without any OTA write")
        print("PASS: malformed acknowledgments, bad identity, retired-image transitions and uncertain writes stop; no retry or premature activation")
    }
}
