import Foundation

private final class ProfileWire: ReportTransport {
    var connectionName = "USB"
    var reconnectsWithoutReplug = false
    var usesRollingAnimationVerification = false
    var supported = true
    var capabilityTemplate: [UInt8]?
    var supportsPersistence = true
    var corruptReadback = false
    var wrongOffset = false
    var disconnectAtChunk: Int?
    var maxLength = OnboardProfile.maximumSize
    var writes = 0
    var commits = 0
    var volatileActivations = 0
    var chunkCount = 0
    var sensorCalls = 0
    var wrongSensorCRC = false
    var effectValue = 20
    var effectSwitches = 0
    var activationQueriesRemaining = 0
    var neverActivates = false
    var checked = 0
    private var session: UInt32 = 0
    private var expectedLength = 0
    private var expectedCRC: UInt32 = 0
    private var pending = [UInt8]()
    private(set) var active = [UInt8]()

    func checkSingleDevice() throws { checked += 1 }
    func close() {}
    func exchange(_ p: [UInt8]) throws -> [UInt8] {
        if p == [8, 3, 5, 0] {
            var result = [UInt8](repeating: 0, count: 32)
            result.replaceSubrange(0..<RGBClient.signature.count, with: RGBClient.signature)
            result[11] = 0; result[15] = UInt8(effectValue); result[16] = 3
            return result
        }
        if p == [7, 3, 2, 20] {
            effectValue = 20; effectSwitches += 1
            return [UInt8](repeating: 0, count: 32)
        }
        guard supported else { return [UInt8](repeating: 0, count: 32) }
        guard p.count >= 4 && p[1] == 3 && p[2] == 7 else { fatalError("Unexpected profile packet") }
        if p == [8, 3, 7, 0] {
            var result = capabilityTemplate ?? header(8, 0)
            result[9] = supportsPersistence ? 7 : 5
            put16(&result, 10, maxLength)
            result[12] = 21
            if result[13] <= 1 { result[13] = (neverActivates || activationQueriesRemaining > 0) ? 1 : 0 }
            if activationQueriesRemaining > 0 { activationQueriesRemaining -= 1 }
            put16(&result, 14, active.count)
            put32(&result, 16, OnboardProfile.crc32(active))
            return result
        }
        if p[0] == 8 && p[3] == 5 {
            let offset = u16(p, 4), count = Int(p[6])
            assert(offset + count <= active.count && count <= 19)
            var result = header(8, 5)
            put16(&result, 10, offset)
            result[12] = UInt8(count)
            result.replaceSubrange(13..<(13 + count), with: active[offset..<(offset + count)])
            if corruptReadback && offset == 0 { result[13] ^= 1 }
            return result
        }
        assert(p[0] == 7)
        writes += 1
        switch p[3] {
        case 1:
            session = u32(p, 4); expectedLength = u16(p, 8); expectedCRC = u32(p, 10)
            pending = []
            return acknowledgment(1, 0)
        case 2:
            assert(u32(p, 4) == session)
            chunkCount += 1
            if disconnectAtChunk == chunkCount {
                throw TransportUnavailableError(message: "Simulated USB disconnect")
            }
            let offset = u16(p, 8), count = Int(p[10])
            assert(offset == pending.count && count > 0 && count <= 21 && p.count == 11 + count)
            pending += p[11...]
            return acknowledgment(2, pending.count + (wrongOffset ? 1 : 0))
        case 3:
            assert(u32(p, 4) == session)
            assert(pending.count == expectedLength && OnboardProfile.crc32(pending) == expectedCRC)
            try OnboardProfile(bytes: pending).validate()
            return acknowledgment(3, pending.count, digest: expectedCRC)
        case 4:
            assert(u32(p, 4) == session && pending.count == expectedLength)
            assert(supportsPersistence)
            active = pending; commits += 1; activationQueriesRemaining = 2
            return acknowledgment(4, active.count, digest: expectedCRC)
        case 7:
            assert(u32(p, 4) == session && pending.count == expectedLength)
            active = pending; volatileActivations += 1; activationQueriesRemaining = 2
            return acknowledgment(7, active.count, digest: expectedCRC)
        case 8, 9:
            assert(!active.isEmpty && p.count == (p[3] == 8 ? 8 : 6))
            sensorCalls += 1
            let digest = OnboardProfile.crc32(active) &+ (wrongSensorCRC ? 1 : 0)
            var result = acknowledgment(p[3], active.count, digest: digest)
            result.replaceSubrange(10..<14, with: [0, 0, 0, 0])
            return result
        default: fatalError("Unexpected profile operation")
        }
    }

    private func header(_ kind: UInt8, _ operation: UInt8) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 32)
        result.replaceSubrange(0..<9, with: [kind, 3, 7, operation] + OnboardUploader.magic + [1])
        return result
    }
    private func acknowledgment(_ operation: UInt8, _ offset: Int, digest: UInt32 = 0) -> [UInt8] {
        var result = header(7, operation)
        put32(&result, 10, session); put16(&result, 14, offset); put32(&result, 16, digest)
        return result
    }
    private func put16(_ p: inout [UInt8], _ at: Int, _ value: Int) {
        p[at] = UInt8(truncatingIfNeeded: value); p[at + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }
    private func put32(_ p: inout [UInt8], _ at: Int, _ value: UInt32) {
        for i in 0..<4 { p[at + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
    }
    private func u16(_ p: [UInt8], _ at: Int) -> Int { Int(p[at]) | Int(p[at + 1]) << 8 }
    private func u32(_ p: [UInt8], _ at: Int) -> UInt32 {
        UInt32(p[at]) | UInt32(p[at + 1]) << 8 | UInt32(p[at + 2]) << 16 | UInt32(p[at + 3]) << 24
    }
}

@main struct OnboardUploaderTests {
    static func rejects(_ description: String, _ body: () throws -> Void) {
        do { try body(); fatalError("Expected rejection: \(description)") }
        catch { print("PASS: \(description)") }
    }
    static func main() throws {
        let keys = try JSONDecoder().decode([KeyGeometry].self,
                                            from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/layout.json")))
        let factory = try JSONDecoder().decode(MappingFile.self,
                                               from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/default-led-map.json")))
        var layer = LightingLayer(settings: LightingSettings(effect: .rainbowRipple))
        layer.keyIDs = ["KeyW", "KeyA", "KeyS", "KeyD"]
        layer.affectAllKeys = true
        let profile = try OnboardProfile.compile(
            LightingProfile(mode: .studio, settings: layer.settings, layers: [layer]),
            keys: keys, mapping: factory, factoryMapping: factory)
        let old = ProfileWire(); old.supported = false
        let oldSupportsPreview = try OnboardUploader(transport: old, session: 16).supportsVolatile()
        assert(!oldSupportsPreview)
        rejects("v0.6 capability failure stops before every profile write") {
            _ = try OnboardUploader(transport: old, session: 17).upload(profile)
        }
        assert(old.writes == 0 && old.commits == 0)

        let receiver = ProfileWire(); receiver.connectionName = "2.4 GHz"; receiver.reconnectsWithoutReplug = true
        let receiverSupportsPreview = try OnboardUploader(transport: receiver, session: 17).supportsVolatile()
        assert(!receiverSupportsPreview)
        rejects("persistent layout upload requires wired USB") {
            _ = try OnboardUploader(transport: receiver, session: 18).upload(profile)
        }
        assert(receiver.checked == 0 && receiver.writes == 0)

        try capabilityVersionsAndReactiveTransfers(keys: keys, factory: factory)

        let tooSmall = ProfileWire(); tooSmall.maxLength = 40
        rejects("oversize layout stops before begin") {
            _ = try OnboardUploader(transport: tooSmall, session: 19).upload(profile)
        }
        assert(tooSmall.writes == 0)

        let good = ProfileWire(); good.effectValue = 3
        let goodSupportsPreview = try OnboardUploader(transport: good, session: 20).supportsVolatile()
        assert(goodSupportsPreview)
        var lastProgress = 0
        let receipt = try OnboardUploader(transport: good, session: 20).upload(profile) { sent, total in
            assert(sent > lastProgress && sent <= total); lastProgress = sent
        }
        assert(good.active == profile.bytes && good.commits == 1 && good.checked >= 5 &&
               good.effectValue == 20 && good.effectSwitches == 1)
        assert(receipt.length == profile.bytes.count && receipt.crc32 == OnboardProfile.crc32(profile.bytes))
        assert(receipt.chunks == good.chunkCount && receipt.chunks > 1 && lastProgress == receipt.length && receipt.persistent)
        print("PASS: every bounded chunk is acknowledged and the committed layout is read back byte for byte")

        let ramOnly = ProfileWire(); ramOnly.supportsPersistence = false
        let volatile = try OnboardUploader(transport: ramOnly, session: 24).activateVolatile(profile)
        assert(!volatile.persistent && ramOnly.volatileActivations == 1 && ramOnly.commits == 0 && ramOnly.active == profile.bytes)
        rejects("RAM-only firmware refuses persistent saves before any profile write") {
            _ = try OnboardUploader(transport: ramOnly, session: 25).upload(profile)
        }
        assert(ramOnly.commits == 0 && ramOnly.volatileActivations == 1)
        print("PASS: RAM-only activation is explicit and never invokes persistent commit")

        let badAck = ProfileWire(); badAck.wrongOffset = true
        rejects("a wrong acknowledged offset stops before commit") {
            _ = try OnboardUploader(transport: badAck, session: 21).upload(profile)
        }
        assert(badAck.commits == 0)
        let lost = ProfileWire(); lost.disconnectAtChunk = 2
        rejects("USB loss stops without retrying or committing") {
            _ = try OnboardUploader(transport: lost, session: 22).upload(profile)
        }
        assert(lost.commits == 0 && lost.chunkCount == 2)
        let corrupt = ProfileWire(); corrupt.corruptReadback = true
        rejects("a successful commit is not reported as verified if readback differs") {
            _ = try OnboardUploader(transport: corrupt, session: 23).upload(profile)
        }
        assert(corrupt.commits == 1)

        let noStart = ProfileWire(); noStart.neverActivates = true
        rejects("an already activating keyboard refuses a second transfer") {
            _ = try OnboardUploader(transport: noStart, session: 27).activateVolatile(profile)
        }
        assert(noStart.writes == 0)

        rejects("v0.6 cannot receive sensor samples") {
            _ = try OnboardTelemetry(transport: old)
        }
        assert(old.writes == 0)
        rejects("sensor samples require wired USB") {
            _ = try OnboardTelemetry(transport: receiver)
        }
        assert(receiver.writes == 0)
        let sensorBytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath:
            "mac/Tests/Fixtures/onboard-profile-all-effects-v1.bin")))
        let sensorWire = ProfileWire(); sensorWire.supportsPersistence = false
        _ = try OnboardUploader(transport: sensorWire, session: 26)
            .activateVolatile(OnboardProfile(bytes: sensorBytes))
        let samples = try OnboardTelemetry(transport: sensorWire)
        try samples.sendMusic(bass: 1, mid: 0.5, treble: 0, level: 0.75)
        try samples.sendTemperature(celsius: 42.5)
        assert(sensorWire.sensorCalls == 2)
        rejects("nonfinite sensor samples stop before writes") {
            try samples.sendMusic(bass: .nan, mid: 0, treble: 0, level: 0)
        }
        rejects("out-of-range temperature stops before writes") {
            try samples.sendTemperature(celsius: 126)
        }
        assert(sensorWire.sensorCalls == 2)
        sensorWire.wrongSensorCRC = true
        rejects("sensor acknowledgement must match the active profile") {
            try samples.sendMusic(bass: 0.3, mid: 0.4, treble: 0.5, level: 0.6)
        }
        sensorWire.wrongSensorCRC = false
        for limit: UInt8 in [17, 23] {
            var caps = [UInt8](try Data(contentsOf: URL(fileURLWithPath:
                "mac/Tests/Fixtures/onboard-capabilities-v1.2.bin")))
            caps[20] = limit
            sensorWire.capabilityTemplate = caps
            try OnboardTelemetry(transport: sensorWire).sendTemperature(celsius: 42.5)
        }
        assert(sensorWire.sensorCalls == 5)
        print("PASS: sensor samples accept legacy and v1.2 capabilities with exact active-profile acknowledgments")
    }
    private static func capabilityVersionsAndReactiveTransfers(keys: [KeyGeometry], factory: MappingFile) throws {
        // Generated by the production v1.2 C runtime dispatch, not a host mock.
        let actual = [UInt8](try Data(contentsOf: URL(fileURLWithPath:
            "mac/Tests/Fixtures/onboard-capabilities-v1.2.bin")))
        assert(actual.count == 32 && actual[9] == 7 && actual[20] == 23)
        for limit: UInt8 in [0, 9, 17, 18, 23, 24] {
            let wire = ProfileWire()
            var caps = actual; caps[20] = limit; wire.capabilityTemplate = caps
            let modes = try OnboardUploader(transport: wire).supportedModes()
            assert(modes.volatile && modes.persistent && modes.maximumEffectID == (limit == 0 ? 8 : Int(limit)))
            assert(wire.writes == 0 && wire.commits == 0)
        }
        for effect in OnboardProfile.effectIDs.dropFirst(18).prefix(6) {
            let layer = LightingLayer(settings: LightingSettings(effect: effect))
            let profile = try OnboardProfile.compile(
                LightingProfile(mode: .studio, settings: layer.settings, layers: [layer]),
                keys: keys, mapping: factory, factoryMapping: factory)
            for persistent in [false, true] {
                let wire = ProfileWire(); wire.capabilityTemplate = actual
                let uploader = OnboardUploader(transport: wire, session: 36)
                let receipt = try persistent ? uploader.upload(profile) : uploader.activateVolatile(profile)
                assert(wire.active == profile.bytes && receipt.persistent == persistent)
                assert(wire.commits == (persistent ? 1 : 0) && wire.volatileActivations == (persistent ? 0 : 1))
            }
            let older = ProfileWire(); var caps = actual; caps[20] = 17; older.capabilityTemplate = caps
            rejects("v1.0/v1.1 block \(effect.displayName) before profile writes") {
                _ = try OnboardUploader(transport: older).upload(profile)
            }
            assert(older.writes == 0 && older.commits == 0)
        }
        let matrix = try OnboardProfile(bytes: [UInt8](Data(contentsOf: URL(fileURLWithPath: "mac/Tests/Fixtures/onboard-profile-matrix-v1.3.bin"))))
        let matrixCaps = [UInt8](try Data(contentsOf: URL(fileURLWithPath: "mac/Tests/Fixtures/onboard-capabilities-v1.3.bin")))
        assert(matrixCaps[20] == 24)
        let oldMatrix = ProfileWire(); oldMatrix.capabilityTemplate = actual
        rejects("v1.2 refuses Matrix rain before writing") { _ = try OnboardUploader(transport: oldMatrix).upload(matrix) }
        assert(oldMatrix.writes == 0 && oldMatrix.commits == 0)
        for persistent in [false, true] {
            let wire = ProfileWire(); wire.capabilityTemplate = matrixCaps
            let uploader = OnboardUploader(transport: wire)
            let receipt = try persistent ? uploader.upload(matrix) : uploader.activateVolatile(matrix)
            assert(wire.active == matrix.bytes && receipt.persistent == persistent)
        }
        for name in ["spaced", "key"] {
            let p = try OnboardProfile(bytes: [UInt8](Data(contentsOf: URL(fileURLWithPath: "mac/Tests/Fixtures/onboard-profile-\(name)-matrix-v1.7.bin"))))
            let caps = [UInt8](try Data(contentsOf: URL(fileURLWithPath: "mac/Tests/Fixtures/onboard-capabilities-v1.7.bin")))
            assert(caps[20] == 26)
            for persistent in [false,true] {
                let wire=ProfileWire(); wire.capabilityTemplate=caps
                _ = try persistent ? OnboardUploader(transport:wire).upload(p) : OnboardUploader(transport:wire).activateVolatile(p)
                assert(wire.active == p.bytes)
            }
            let old=ProfileWire();old.capabilityTemplate=matrixCaps
            rejects("v1.6 refuses the new column effects before any write") { _ = try OnboardUploader(transport:old).upload(p) }
            assert(old.writes == 0 && old.commits == 0)
        }
        print("PASS: production v1.3 capabilities enable Matrix Send/Save; v1.2 rejects it before every write")
        let layer = LightingLayer(settings: LightingSettings(effect: .columnWave))
        let profile = try OnboardProfile.compile(
            LightingProfile(mode: .studio, settings: layer.settings, layers: [layer]),
            keys: keys, mapping: factory, factoryMapping: factory)
        for (index, value) in [(20, UInt8(8)), (20, 25), (20, 255), (21, 1), (8, 2), (13, 2)] {
            let wire = ProfileWire(); var caps = actual; caps[index] = value; wire.capabilityTemplate = caps
            let modes = try OnboardUploader(transport: wire).supportedModes()
            assert(!modes.volatile && !modes.persistent)
            rejects("unrecognized capability byte \(index)=\(value) refuses profile writes") {
                _ = try OnboardUploader(transport: wire).upload(profile)
            }
            assert(wire.writes == 0 && wire.commits == 0)
        }
        print("PASS: production v1.2 reply enables read-only discovery and verified send/save of all six new effects; older and malformed replies stay blocked")
    }

}
