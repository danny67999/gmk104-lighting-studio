import Foundation

@main struct AuthorizationTests {
    static func rejects(_ action: () throws -> Void) {
        do { try action(); fatalError("Expected rejection") } catch {}
    }
    static func main() throws {
        let before = FirmwareDeviceState(otaID: 101, viaID: 102, usbID: 100, location: 42, crc: FirmwareTarget.custom.crc)
        let request = FirmwareOperation(action: .install, nonce: UUID(), target: .wireless, expected: before,
                                        confirmation: FirmwareTarget.wireless.phrase)
        let roundtrip = try FirmwareOperation.decode(request.encoded())
        assert(roundtrip.target == .wireless && roundtrip.expected == before && roundtrip.nonce == request.nonce)
        rejects { _ = try FirmwareOperation.decode("not base64") }
        rejects { _ = try FirmwareOperation.decode(String(repeating: "A", count: 4097)) }
        rejects { _ = try FirmwareOperation(action: .install, nonce: UUID(), target: .wireless, expected: before, confirmation: "yes").validated() }
        rejects { _ = try FirmwareOperation(action: .install, nonce: UUID(), target: .custom, expected: before, confirmation: FirmwareTarget.custom.phrase).validated() }
        rejects { _ = try FirmwareOperation(action: .inspect, nonce: UUID(), target: .wireless, expected: nil, confirmation: nil).validated() }
        _ = try FirmwareOperation(action: .inspect, nonce: UUID(), target: nil, expected: nil, confirmation: nil).validated()
        let after = FirmwareDeviceState(otaID: 201, viaID: 202, usbID: 200, location: 42, crc: FirmwareTarget.wireless.crc)
        try FirmwareOperationEvent(nonce: request.nonce, kind: .result, message: "Verified", state: after).validate(for: request)
        rejects { try FirmwareOperationEvent(nonce: UUID(), kind: .result, message: "Verified", state: after).validate(for: request) }
        rejects { try FirmwareOperationEvent(nonce: request.nonce, kind: .result, message: "No identity").validate(for: request) }
        rejects { try FirmwareOperationEvent(nonce: request.nonce, kind: .result, message: "Old firmware", state: before).validate(for: request) }
        let anotherPort = FirmwareDeviceState(otaID: 201, viaID: 202, usbID: 200, location: 43, crc: FirmwareTarget.wireless.crc)
        rejects { try FirmwareOperationEvent(nonce: request.nonce, kind: .result, message: "Wrong port", state: anotherPort).validate(for: request) }
        rejects { try FirmwareOperationEvent(nonce: request.nonce, kind: .progress, message: "Bad progress", progress: 1.01).validate(for: request) }
        rejects { try FirmwareOperationEvent(nonce: request.nonce, kind: .progress, message: "Bad progress", progress: .nan).validate(for: request) }
        rejects { try FirmwareOperationEvent(nonce: request.nonce, kind: .logFile, message: "/etc/hosts").validate(for: request) }
        try FirmwareOperationEvent(nonce: request.nonce, kind: .logFile, message: FirmwareOperationLog.path(for: request.nonce)).validate(for: request)
        let surveyed = FirmwareDeviceState(otaID: 101, viaID: 102, usbID: 100, location: 42, crc: FirmwareTarget.storageDiagnosticRollback.crc)
        _ = try FirmwareOperation(action: .install, nonce: UUID(), target: .persistentLighting,
                                  expected: surveyed, confirmation: FirmwareTarget.persistentLighting.phrase).validated()
        rejects { _ = try FirmwareOperation(action: .install, nonce: UUID(), target: .persistentLighting,
                                             expected: surveyed, confirmation: "yes").validated() }
        rejects { _ = try FirmwareOperation(action: .install, nonce: UUID(), target: .persistentLighting,
                                             expected: before, confirmation: FirmwareTarget.persistentLighting.phrase).validated() }
        let performanceSource = FirmwareDeviceState(otaID: 101, viaID: 102, usbID: 100, location: 42, crc: FirmwareTarget.persistentLighting.crc)
        _ = try FirmwareOperation(action: .install, nonce: UUID(), target: .performanceLighting,
                                  expected: performanceSource, confirmation: FirmwareTarget.performanceLighting.phrase).validated()
        rejects { _ = try FirmwareOperation(action: .install, nonce: UUID(), target: .performanceLighting,
                                             expected: surveyed, confirmation: FirmwareTarget.performanceLighting.phrase).validated() }
        let persistent = FirmwareDeviceState(otaID: 201, viaID: 202, usbID: 200, location: 42, crc: FirmwareTarget.persistentLighting.crc)
        _ = try FirmwareOperation(action: .install, nonce: UUID(), target: .storageDiagnosticRollback,
                                  expected: persistent, confirmation: FirmwareTarget.storageDiagnosticRollback.phrase).validated()
        print("PASS: new firmware and its rollback require the pinned CRC, exact confirmation and correct source image")
        print("PASS: authorization requests reject missing identity, wrong confirmation, invalid transitions and malformed payloads")
        print("PASS: helper results require the same request, target CRC and USB port; progress and log paths are bounded")
    }
}
