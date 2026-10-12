import Foundation
import SwiftUI

final class MockBus {
    struct Device {
        let id: UInt64
        var effect = 1
        var brightness = 3
        var colors = Array(repeating: RGB.black, count: 104)
        var validFirmware = true
        var sleepSeconds = 300
        var pendingPreview = [UInt8]()
        var activePreview = [UInt8]()
        var previewLength = 0
        var previewCRC: UInt32 = 0
        var previewSession: UInt32 = 0
    }
    struct Event {
        let id: UInt64
        let kind: String
        let payload: [UInt8]
    }
    final class Hold {
        let release = DispatchSemaphore(value: 0)
    }
    private let lock = NSLock()
    private var device: Device?
    private var events: [Event] = []
    private var nextHold: Hold?
    private var nextPreviewHold: Hold?
    private var held = false
    private var time: TimeInterval = 1000
    private var firmwareColors: [Int: RGB] = [:]
    private var flashPreview = [UInt8]()
    var wireless = false
    var adjustableSleep = false
    var previewFirmware = false
    var extendedEffects = false
    var reactiveEffects = false
    var matrixEffects = false
    var spacedEffects = false
    var inputPermission: KeyboardEvents.Permission = .unknown
    var permissionRequests = 0
    var persistentFirmware = false
    var loseCommitReply = false
    var corruptPreviewReadback = false
    private var awake = true
    func setAwake(_ value: Bool) { locked { awake = value } }

    private func locked<T>(_ action: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try action()
    }
    func attach(_ id: UInt64, valid: Bool = true) { locked {
        var fresh = Device(id: id, validFirmware: valid)
        fresh.activePreview = flashPreview
        if !flashPreview.isEmpty { fresh.effect = 20 }
        device = fresh
    } }
    func remove() { locked { device = nil } }
    func clock() -> TimeInterval { locked { time } }
    func advance(_ amount: TimeInterval) { locked { time += amount } }
    func snapshot() -> (count: Int, registryID: UInt64?) { locked { (device == nil ? 0 : 1, device?.id) } }
    func recorded(_ id: UInt64) -> [Event] { locked { events.filter { $0.id == id } } }
    func writes(_ id: UInt64) -> [Event] { recorded(id).filter { $0.kind == "write" } }
    func colors() -> [RGB]? { locked { device?.colors } }
    func activePreview() -> [UInt8]? { locked { device?.activePreview } }
    func overrideColors(_ colors: [Int: RGB]) { locked { firmwareColors = colors } }
    var isHeld: Bool { locked { held } }
    func holdNextRGBWrite() -> Hold {
        locked { let hold = Hold(); nextHold = hold; held = false; return hold }
    }
    func holdNextPreviewChunk() -> Hold {
        locked { let hold = Hold(); nextPreviewHold = hold; held = false; return hold }
    }
    private static func le16(_ value: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }
    private static func le32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    private static func u16(_ p: [UInt8], _ at: Int) -> Int { Int(p[at]) | Int(p[at + 1]) << 8 }
    private static func u32(_ p: [UInt8], _ at: Int) -> UInt32 {
        UInt32(p[at]) | UInt32(p[at + 1]) << 8 | UInt32(p[at + 2]) << 16 | UInt32(p[at + 3]) << 24
    }
    private static func uploadReply(_ op: UInt8, session: UInt32, offset: Int, crc: UInt32 = 0) -> [UInt8] {
        [7, 3, 7, op] + OnboardUploader.magic + [1, 0] + le32(session) + le16(offset) + le32(crc) + [UInt8](repeating: 0, count: 12)
    }
    func open() throws -> (transport: ReportTransport, registryID: UInt64?) {
        try locked {
            guard let device else { throw ControllerError.message("No mock attachment") }
            events.append(Event(id: device.id, kind: "open", payload: []))
            return (MockSession(bus: self, id: device.id), device.id)
        }
    }
    func check(_ id: UInt64) throws {
        try locked {
            guard device?.id == id else { throw ControllerError.message("Mock attachment changed") }
            events.append(Event(id: id, kind: "gate", payload: []))
        }
    }
    func close(_ id: UInt64) { locked { events.append(Event(id: id, kind: "close", payload: [])) } }
    func exchange(_ p: [UInt8], id: UInt64) throws -> [UInt8] {
        let hold: Hold? = locked {
            guard p.first == 7 else { return nil }
            if p[2] == 7 && p[3] == 2, let hold = nextPreviewHold {
                nextPreviewHold = nil; held = true; return hold
            }
            guard p[2] == 5, let hold = nextHold else { return nil }
            nextHold = nil; held = true; return hold
        }
        if let hold {
            try require(hold.release.wait(timeout: .now() + 5) == .success, "Test failed to release held frame")
            locked { held = false }
        }
        return try locked {
            guard var d = device, d.id == id else { throw ControllerError.message("Mock keyboard disconnected") }
            guard awake else { throw TransportUnavailableError(message: "Receiver has no wireless response") }
            if p[2] == 7 {
                guard previewFirmware else { return [UInt8](repeating: 0, count: 32) }
                if p[0] == 8 && p[3] == 0 {
                    events.append(Event(id: id, kind: "read", payload: p))
                    var response = [UInt8](repeating: 0, count: 32)
                    response.replaceSubrange(0..<9, with: [8, 3, 7, 0] + OnboardUploader.magic + [1])
                    response[9] = persistentFirmware ? 0b111 : 0b101
                    response.replaceSubrange(10..<12, with: Self.le16(OnboardProfile.maximumSize))
                    response[12] = UInt8(OnboardUploader.maximumChunk)
                    response[20] = spacedEffects ? 26 : matrixEffects ? 24 : reactiveEffects ? 23 : extendedEffects ? 17 : 0
                    response.replaceSubrange(14..<16, with: Self.le16(d.activePreview.count))
                    response.replaceSubrange(16..<20, with: Self.le32(OnboardProfile.crc32(d.activePreview)))
                    return response
                }
                if p[0] == 8 && p[3] == 5 {
                    events.append(Event(id: id, kind: "read", payload: p))
                    let offset = Self.u16(p, 4), count = Int(p[6])
                    try require(offset + count <= d.activePreview.count && count <= OnboardUploader.maximumRead,
                                "Mock preview readback outside active profile")
                    var response = [UInt8](repeating: 0, count: 32)
                    response.replaceSubrange(0..<9, with: [8, 3, 7, 5] + OnboardUploader.magic + [1])
                    response.replaceSubrange(10..<12, with: Self.le16(offset))
                    response[12] = UInt8(count)
                    response.replaceSubrange(13..<13 + count, with: d.activePreview[offset..<offset + count])
                    if corruptPreviewReadback && offset == 0 { response[13] ^= 1 }
                    return response
                }
                try require(p[0] == 7, "Unsupported mock preview command")
                events.append(Event(id: id, kind: "write", payload: p))
                let session = Self.u32(p, 4)
                switch p[3] {
                case 1:
                    d.previewSession = session; d.previewLength = Self.u16(p, 8)
                    d.previewCRC = Self.u32(p, 10); d.pendingPreview = []
                    device = d
                    return Self.uploadReply(1, session: session, offset: 0)
                case 2:
                    let offset = Self.u16(p, 8), count = Int(p[10])
                    try require(session == d.previewSession && offset == d.pendingPreview.count &&
                                count > 0 && count <= OnboardUploader.maximumChunk && p.count == 11 + count,
                                "Mock preview chunk is out of sequence")
                    d.pendingPreview += p[11..<11 + count]; device = d
                    return Self.uploadReply(2, session: session, offset: d.pendingPreview.count)
                case 3:
                    try require(session == d.previewSession && d.pendingPreview.count == d.previewLength &&
                                OnboardProfile.crc32(d.pendingPreview) == d.previewCRC,
                                "Mock preview profile failed validation")
                    try OnboardProfile(bytes: d.pendingPreview).validate()
                    return Self.uploadReply(3, session: session, offset: d.previewLength, crc: d.previewCRC)
                case 7:
                    try require(session == d.previewSession, "Mock preview session changed")
                    d.activePreview = d.pendingPreview; d.effect = 20; device = d
                    return Self.uploadReply(7, session: session, offset: d.previewLength, crc: d.previewCRC)
                case 4:
                    try require(persistentFirmware && session == d.previewSession,
                                "Mock permanent save is unavailable")
                    flashPreview = d.pendingPreview
                    d.activePreview = d.pendingPreview; d.effect = 20; device = d
                    if loseCommitReply { throw TransportUnavailableError(message: "Commit reply lost") }
                    return Self.uploadReply(4, session: session, offset: d.previewLength, crc: d.previewCRC)
                default:
                    throw ControllerError.message("Unexpected persistent or unsupported preview write")
                }
            }
            if p[0] == 7 {
                events.append(Event(id: id, kind: "write", payload: p))
                if p[2] == 1 { d.brightness = Int(p[3]) }
                if p[2] == 2 { d.effect = Int(p[3]) }
                if p[2] == 6 && adjustableSleep { d.sleepSeconds = Int(p[4]) | Int(p[5]) << 8 }
                if p[2] == 5 {
                    if d.effect != 19 || p[4] == 0 { d.colors = Array(repeating: .black, count: 104) }
                    d.effect = 19
                    for i in 0..<Int(p[4]) {
                        d.colors[Int(p[3]) + i] = RGB(r: p[5+i*3], g: p[6+i*3], b: p[7+i*3])
                    }
                }
                for (index, color) in firmwareColors { d.colors[index] = color }
                device = d
                return p + Array(repeating: 0, count: 32-p.count)
            }
            events.append(Event(id: id, kind: "read", payload: p))
            if p[2] == 6 {
                guard adjustableSleep else { return p + Array(repeating: 0, count: 32-p.count) }
                return KeyboardSleepState.signature + [UInt8(d.sleepSeconds&255),UInt8(d.sleepSeconds>>8),3,3,16,14,60,0] + Array(repeating:0,count:16)
            }
            let index = Int(p[3]), c = d.colors[index], sum = RGBClient.sum(d.colors)
            var response = RGBClient.signature + [UInt8(index), c.r, c.g, c.b, UInt8(d.effect), UInt8(d.brightness), UInt8(sum & 255), UInt8(sum >> 8)]
            response += Array(repeating: 0, count: 32-response.count)
            if !d.validFirmware { response[10] = 1 }
            return response
        }
    }
}

private final class MockSession: ReportTransport {
    private let bus: MockBus
    private let id: UInt64
    private var closed = false // All calls are serialized by ControllerModel's HID queue.
    var connectionName: String { bus.wireless ? "2.4 GHz" : "USB" }
    var reconnectsWithoutReplug: Bool { bus.wireless }
    init(bus: MockBus, id: UInt64) { self.bus = bus; self.id = id }
    func checkSingleDevice() throws { try require(!closed, "Mock session closed"); try bus.check(id) }
    func exchange(_ payload: [UInt8]) throws -> [UInt8] { try require(!closed, "Mock session closed"); return try bus.exchange(payload, id: id) }
    func close() { if !closed { closed = true; bus.close(id) } }
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    try require(try condition(), "FAIL: \(message)")
}
private func pump(_ duration: TimeInterval) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline { _ = RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.003))) }
}
private func awaitState(_ description: String, timeout: TimeInterval = 3, _ condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { pump(0.003) }
    try expect(condition(), "Timed out waiting for \(description)")
}

private final class Harness {
    let bus = MockBus()
    let profileURL: URL
    let mappingURL: URL
    let defaultMappingURL: URL
    let model: ControllerModel
    init(_ name: String, initialProfile: LightingProfile? = nil, mappingInputAllowed: @escaping () -> Bool = { true }, makeInputs: (() -> LightingInputSource)? = nil) throws {
        let root = URL(fileURLWithPath: "mac/.build/ControllerModelTests-\(UUID().uuidString)-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        profileURL = root.appendingPathComponent("lighting-profile.json")
        mappingURL = root.appendingPathComponent("led-map.json")
        try initialProfile?.save(to: profileURL)
        let bus = self.bus
        let fixtureURL = root.appendingPathComponent("default-led-map.json")
        defaultMappingURL = fixtureURL
        var fixture = try JSONDecoder().decode(MappingFile.self, from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/default-led-map.json")))
        for i in fixture.mappings.indices {
            let escape = fixture.mappings[i].keyId == "Escape"
            fixture.mappings[i].ledIndex = escape ? 0 : nil
            fixture.mappings[i].confirmed = escape
        }
        try JSONEncoder().encode(fixture).write(to: fixtureURL)
        model = ControllerModel(environment: ControllerEnvironment(
            layoutURL: URL(fileURLWithPath: "mac/Resources/layout.json"),
            defaultMappingURL: fixtureURL,
            mappingURL: mappingURL, profileURL: profileURL,
            openTransport: { try bus.open() }, attachments: { bus.snapshot() },
            makeLightingInputs: makeInputs, inputMonitoringEnabled: false,
            readInputPermission: { bus.inputPermission },requestInputPermission: { bus.permissionRequests += 1;return false },
            mappingInputAllowed: mappingInputAllowed,
            connectionInterval: 0.02, animationInterval: 0.01,
            clock: { bus.clock() }))
    }
    func connect(_ id: UInt64) throws {
        bus.attach(id); model.connect()
        try awaitState("connection") { self.model.connected && !self.model.busy }
    }
    func start(_ effect: LightingEffect = .staticColor, color: RGB = RGB(r: 25, g: 170, b: 90)) throws {
        model.settings.effect = effect; model.selectedColor = ControllerModel.color(color)
        model.startStudio()
        try awaitState("studio start") { self.model.playing && !self.model.busy }
    }
    func shutdown() throws {
        model.disconnect()
        try awaitState("manual disconnection") { !self.model.busy && !self.model.connected }
    }
    func saved() throws -> LightingProfile {
        guard let p = try LightingProfile.load(from: profileURL) else { throw ControllerError.message("Missing test profile") }
        return p
    }
    func confirmAllPreviewKeys() throws {
        model.mappingMode = true; model.applyRowMapping(); model.mappingMode = false
        try expect(model.mappedCount == 104, "Preview test requires a complete output map")
        let factory = try Data(contentsOf: URL(fileURLWithPath: "mac/Resources/default-led-map.json"))
        try factory.write(to: defaultMappingURL)
    }
}

private final class MockLightingInputs: LightingInputSource {
    var requests: [(Bool, Bool)] = []
    var callbacks: [(LightingInputs) -> Void] = []
    var stops = 0
    func start(music: Bool, temperature: Bool, update: @escaping (LightingInputs) -> Void) {
        requests.append((music, temperature)); callbacks.append(update)
    }
    func stop() { stops += 1 }
}
#if !GMK104_UI_SNAPSHOT
@main private struct ControllerModelTests {
    static func main() throws {
        try workspacePresetsClearAndUndo()
        try openingDetectsKeyboardWithoutRestoringPausedProfile()
        try nativeControlsAreDiscoveredOnConnect()
        try checkingSupportPreservesPlayback()
        try reconnectDoesNotReplaceNativeLayout()
        try permissionIsIndependentOfConnection()
        try draftPreviewIsLocal()
        try wirelessSleepSettings()
        try sleepSettingDuringAnimation()
        try frameRatePersists()
        try receiverRecoversWithoutReplug()
        try liveInputLifecycle()
        try noProfileIsReadOnly()
        try reconnectRestoresAfterGate()
        try pauseAndResumePersist()
        try mappingSuppressesPlayback()
        try wrongFirmwareBlocksRestore()
        try rapidStopStartDiscardsOldCompletion()
        try explicitAndQuickMapping()
        try resetAndUndoMapping()
        try failedMappingSaveDoesNotAdvance()
        try backgroundTypingCannotMap()
        try indicatorLightsDoNotDisconnect()
        try verificationErrorKeepsVerifiedConnection()
        try applyRowOrderAndTestWithoutRemapping()
        try layersRestoreAppliedSnapshot()
        try layerEditingIsIsolated()
        try profileFileCanBeOpenedAndSent()
        try extendedEffectsRequireCompatibleFirmware()
        try reactiveFirmwareEnablesPlaybackAndSave()
        try reactiveLayerRevealsBackground()
        try heldKeyFollowsPhysicalRelease()
        try toggleFollowsSuccessivePresses()
        try wasdTriggersWholeKeyboard()
        try wasdTriggersWholeKeyboard(effect: .rainbowRipple)
        try onboardPreviewRequiresCapability()
        try onboardPreviewVerifiesDraftAndDoesNotSave()
        try onboardPreviewSupportsSixteenLayers()
        try onboardSaveRequiresPersistentFirmware()
        try onboardSaveNeverRetriesLostCommitReply()
        try onboardPreviewRejectsUnbridgedSensors()
        try onboardPreviewReadbackFailure()
        try onboardPreviewDisconnectDuringTransfer()
        print("All controller lifecycle tests passed using mock USB and isolated profiles.")
    }
    private static func workspacePresetsClearAndUndo() throws {
        let h = try Harness("workspace-presets")
        h.bus.previewFirmware=true;h.bus.persistentFirmware=true;h.bus.spacedEffects=true
        try h.connect(2970);try h.confirmAllPreviewKeys()
        let initial=h.model.layers
        let writes=h.bus.writes(2970).count
        let factory=try JSONDecoder().decode(MappingFile.self,from:Data(contentsOf:h.defaultMappingURL))
        for preset in LightingPreset.allCases {
            h.model.applyPreset(preset)
            try expect((2...3).contains(h.model.layers.count) && h.model.selectingLayerKeys,"Preset must load editable layers")
            let profile=LightingProfile(mode:.studio,settings:h.model.layers[0].settings,resume:false,layers:h.model.layers)
            let encoded=try OnboardProfile.compile(profile,keys:h.model.keys,mapping:h.model.map!,factoryMapping:factory)
            try expect(encoded.maximumEffectID <= 26 && !encoded.needsMacAudio && !encoded.needsMacTemperature,"All presets must run entirely on current v1.7 firmware")
            h.model.undoWorkspace();try expect(h.model.layers == initial,"Preset undo must restore exact previous layers")
        }
        h.model.removeAllEffects()
        try expect(h.model.layers.isEmpty && h.model.canUndoWorkspace,"Remove all must leave an empty draft with undo")
        h.model.saveDraftToMac();try expect(try h.saved().studioLayers.isEmpty,"An empty draft must round-trip through local profile storage")
        h.model.previewOnKeyboard();try awaitState("empty profile applied") { !h.model.busy && h.model.onboardPreviewActive }
        let bytes=h.bus.activePreview()!
        try expect(bytes[6] == 1 && bytes[344] == 6 && bytes[345] & 1 == 0,"Empty draft must encode a disabled black layer, not an invalid zero-layer wire profile")
        h.model.undoWorkspace();try expect(h.model.layers == initial,"Clear undo must restore exact layers")
        // All keys are triggers, with reach OFF: only the physically pressed
        // key lights, rather than flashing the entire keyboard.
        var reactive=LightingLayer(settings:LightingSettings(effect:.reactive,color:RGB(r:255,g:0,b:0)))
        reactive.keyIDs=nil;reactive.affectAllKeys=false
        let frame=LayerRenderer.frame(layers:[reactive],keys:h.model.keys,mapping:h.model.map!,pulses:[KeyPulse(keyID:"KeyA",time:0)],time:0.1)
        let index=h.model.map!.mappings.first { $0.keyId == "KeyA" }!.ledIndex!
        try expect(frame[index].r > 0 && frame.enumerated().allSatisfy { $0.offset == index || $0.element == .black },"Every key may trigger, but only the pressed key should light when reach is off")
        try expect(h.bus.writes(2970).count > writes,"Only the explicit test upload should write to mock USB")
        try h.shutdown()
        print("PASS: five native-compatible presets, exact undo, empty draft save/upload, and all-key triggers with pressed-key-only reactive output")
    }
    private static func openingDetectsKeyboardWithoutRestoringPausedProfile() throws {
        let h=try Harness("startup-discovery",initialProfile:LightingProfile(mode:.studio,settings:LightingSettings(effect:.wave),resume:false))
        h.bus.previewFirmware=true;h.bus.persistentFirmware=true;h.bus.spacedEffects=true
        let saved=try Data(contentsOf:h.profileURL)
        h.bus.attach(2960)
        try awaitState("automatic startup discovery") { h.model.connected && !h.model.busy }
        try expect(h.model.onboardPreviewAvailable && h.model.onboardPersistentAvailable && !h.model.playing,
                   "Opening must discover a plugged-in keyboard without playing a paused Mac profile")
        try expect(h.bus.writes(2960).isEmpty && (try Data(contentsOf:h.profileURL)) == saved,
                   "Startup discovery must be read-only and preserve the saved draft")
        try h.shutdown();pump(0.05)
        try expect(!h.model.connected,"Manual Disconnect must stay disconnected despite automatic startup detection")
        print("PASS: startup detects a connected keyboard without restoring paused lighting; manual Disconnect remains respected")
    }
    private static func nativeControlsAreDiscoveredOnConnect() throws {
        let h = try Harness("auto-native-support")
        h.bus.previewFirmware = true;h.bus.persistentFirmware = true;h.bus.spacedEffects = true
        try h.connect(2961)
        try expect(h.model.onboardPreviewAvailable && h.model.onboardPersistentAvailable && h.model.onboardMaximumEffectID == 26,
                   "Play and Save must be ready on first USB connection without a Check button")
        try expect(h.bus.writes(2961).isEmpty && !FileManager.default.fileExists(atPath:h.profileURL.path),
                   "Automatic discovery must not change lighting, upload or save a profile")
        try h.shutdown()
        print("PASS: USB connection automatically enables native Play/Save with read-only queries")
    }
    private static func checkingSupportPreservesPlayback() throws {
        let h = try Harness("support-keeps-playing")
        h.bus.previewFirmware = true;h.bus.persistentFirmware = true
        try h.connect(2962);try h.confirmAllPreviewKeys()
        h.model.saveOnKeyboard()
        try awaitState("native save before repeated checks") { !h.model.busy && h.model.onboardPreviewActive }
        let writes = h.bus.writes(2962).count
        for _ in 0..<5 {
            h.model.checkOnboardPreviewSupport()
            try awaitState("repeated support check") { !h.model.busy }
            try expect(h.model.onboardPreviewAvailable && h.model.onboardPersistentAvailable && h.model.onboardPreviewActive && h.model.onboardLastTransferPersistent,
                       "Checking must preserve availability, playing state and the verified save")
        }
        try expect(h.bus.writes(2962).count == writes && h.model.onboardPreviewLayerCount == 1,
                   "Checking must not replace or stop the active profile")
        try h.shutdown()
        print("PASS: five support checks after Save preserve native playing state and issue no writes")
    }
    private static func reconnectDoesNotReplaceNativeLayout() throws {
        let profile = LightingProfile(mode:.studio,settings:LightingSettings(effect:.staticColor),resume:true)
        let h = try Harness("native-reconnect",initialProfile:profile)
        h.bus.previewFirmware = true;h.bus.persistentFirmware = true
        try h.connect(2963)
        try awaitState("initial old host resume") { h.model.playing && !h.model.busy }
        h.model.stopPlayback(savePausedState:false);pump(0.05)
        try h.confirmAllPreviewKeys();h.model.saveOnKeyboard()
        try awaitState("save before reconnect") { h.model.onboardPreviewActive && !h.model.busy }
        let saved = try Data(contentsOf:h.profileURL)
        try h.shutdown();try h.connect(2964);pump(0.05)
        try expect(h.model.onboardPreviewActive && !h.model.playing && h.model.onboardPersistentAvailable,
                   "Reconnect must recognize a native layout without starting Mac streaming over it")
        try expect(h.bus.writes(2964).isEmpty && (try Data(contentsOf:h.profileURL)) == saved,
                   "Native reconnect must not upload, commit or edit the Mac profile")
        try h.shutdown()
        print("PASS: reconnect recognizes native playback and leaves the saved layout and Mac profile intact")
    }
    private static func permissionIsIndependentOfConnection() throws {
        let h = try Harness("permission-display")
        h.bus.inputPermission = .denied;h.model.refreshInputPermission()
        try expect(h.model.inputPermission == .denied && h.model.inputPermissionLabel == "Input Monitoring: Off" && !h.model.connected,
                   "Permission must be visible before the keyboard connects")
        h.model.enableKeyboardInput()
        try expect(h.bus.permissionRequests == 1,"Only an explicit permission action may request access")
        h.bus.inputPermission = .granted;h.model.refreshInputPermission()
        try expect(h.model.inputPermission == .granted && h.model.inputPermissionLabel == "Input Monitoring: Enabled" && !h.model.keyResponseEnabled,
                   "Granted OS permission must not pretend an input listener is active")
        h.model.enableKeyboardInput()
        try expect(h.bus.permissionRequests == 1,"Already granted access must not prompt again")
        try h.connect(2965);h.bus.inputPermission = .denied;h.model.refreshInputPermission()
        try expect(h.model.inputPermission == .denied && !h.model.keyResponseEnabled && h.bus.writes(2965).isEmpty,
                   "A changed permission state must refresh without changing lighting")
        try h.shutdown()
        print("PASS: permission refresh is visible offline, distinct from a listener, and never prompts automatically")
    }
    private static func draftPreviewIsLocal() throws {
        let h = try Harness("local-draft-preview")
        try h.connect(2951); try h.confirmAllPreviewKeys()
        h.model.settings.effect = .keyHold
        let writes = h.bus.writes(2951).count
        let existed = FileManager.default.fileExists(atPath: h.profileURL.path)
        h.model.previewDraftPulse("KeyW")
        let w = h.model.map!.mappings.first { $0.keyId == "KeyW" }!.ledIndex!
        try expect(h.model.draftPreviewFrame()[w] != .black, "Clicking a preview key lights its local draft")
        try expect(h.bus.writes(2951).count == writes && !h.model.playing, "Preview must not start host playback or issue a lighting write")
        try expect(FileManager.default.fileExists(atPath: h.profileURL.path) == existed, "Preview must not create a saved profile")
        pump(0.3)
        try expect(h.model.draftPreviewFrame()[w] == .black, "A simulated held key releases in the local draft")
        try h.shutdown()
        print("PASS: local draft previews animate without device writes, host playback or profile saves")
    }
    private static func onboardPreviewRequiresCapability() throws {
        let old = try Harness("preview-old")
        try old.connect(2001)
        old.model.previewOnKeyboard(); pump(0.02)
        try expect(old.bus.writes(2001).isEmpty && !old.model.onboardPreviewAvailable,
                   "Preview cannot send anything before a v0.7 capability check")
        old.model.checkOnboardPreviewSupport()
        try awaitState("old firmware capability check") { !old.model.busy }
        try expect(!old.model.onboardPreviewAvailable && old.bus.writes(2001).isEmpty,
                   "Older firmware must receive no preview writes")
        try old.shutdown()

        let wireless = try Harness("preview-wireless")
        wireless.bus.wireless = true; wireless.bus.previewFirmware = true
        try wireless.connect(2002)
        wireless.model.checkOnboardPreviewSupport(); wireless.model.previewOnKeyboard(); pump(0.02)
        try expect(!wireless.model.onboardPreviewAvailable && wireless.bus.writes(2002).isEmpty,
                   "Wireless sessions must not check or upload an onboard preview")
        try wireless.shutdown()
        print("PASS: v0.6 and wireless sessions cannot upload temporary previews")
    }
    private static func profileFileCanBeOpenedAndSent() throws {
        let h = try Harness("profile-file")
        h.bus.previewFirmware = true
        try h.connect(2051)
        try h.confirmAllPreviewKeys()
        h.model.settings.effect = .staticColor
        h.model.addLayer(.rainbowRipple)
        h.model.setLayerKeys(["KeyW", "KeyA", "KeyS", "KeyD"])
        h.model.selectedLayer.affectAllKeys = true
        h.model.settings.speed = 1.75
        h.model.animationFPS = 30
        let expectedLayers = h.model.layers
        let expectedMapping = h.model.map?.mappings.map { "\($0.keyId):\($0.ledIndex ?? -1):\($0.confirmed)" }
        let file = h.profileURL.deletingLastPathComponent().appendingPathComponent("shared-lighting-profile.json")
        let writesBefore = h.bus.writes(2051).count
        try h.model.exportProfile(to: file)
        try expect(FileManager.default.fileExists(atPath: file.path) && h.bus.writes(2051).count == writesBefore &&
                   !FileManager.default.fileExists(atPath: h.profileURL.path),
                   "Export must create a portable file without writing to the keyboard or internal saved profile")
        h.model.removeLayer(); h.model.animationFPS = 120; h.model.map = nil
        try h.model.importProfile(from: file)
        try expect(h.model.layers == expectedLayers && h.model.animationFPS == 30 &&
                   h.model.map?.mappings.map({ "\($0.keyId):\($0.ledIndex ?? -1):\($0.confirmed)" }) == expectedMapping &&
                   h.model.openedProfileName == file.lastPathComponent && h.bus.writes(2051).count == writesBefore &&
                   !FileManager.default.fileExists(atPath: h.profileURL.path),
                   "Opening a file must restore editable layers without sending or replacing anything")
        h.model.checkOnboardPreviewSupport()
        try awaitState("file profile support") { !h.model.busy && h.model.onboardPreviewAvailable }
        h.model.previewOnKeyboard()
        try awaitState("file profile sent to keyboard") { !h.model.busy && h.model.onboardPreviewActive }
        let active = h.bus.activePreview() ?? []
        try expect(active.count > 400 && active[6] == 2 &&
                   h.bus.writes(2051).contains { $0.payload.prefix(4) == [7, 3, 7, 7] },
                   "The opened profile must be the one sent to and verified on the keyboard")
        try expect(!FileManager.default.fileExists(atPath: h.profileURL.path),
                   "Sending a file must not silently replace the user's saved Mac profile")
        try h.shutdown()
        print("PASS: export includes the LED map; opening a different file prepares it and explicit Send applies it")
    }
    private static func extendedEffectsRequireCompatibleFirmware() throws {
        let h = try Harness("extended-capability")
        h.bus.previewFirmware = true
        try h.connect(2052)
        try h.confirmAllPreviewKeys()
        h.model.addLayer(.keyHold)
        h.model.setLayerKeys(["KeyW", "KeyA", "KeyS", "KeyD"])
        h.model.checkOnboardPreviewSupport()
        try awaitState("legacy effect capability") { !h.model.busy && h.model.onboardPreviewAvailable }
        try expect(!h.model.onboardCompatibleDraft && h.model.onboardMaximumEffectID == 8,
                   "Older firmware must disable keyboard upload for new effects")
        h.model.previewOnKeyboard()
        try expect(h.bus.writes(2052).isEmpty, "An unsupported effect must cause no profile writes")
        h.bus.extendedEffects = true
        h.model.checkOnboardPreviewSupport()
        try awaitState("extended effect capability") { !h.model.busy && h.model.onboardMaximumEffectID == 17 }
        try expect(h.model.onboardCompatibleDraft, "Compatible firmware must enable upload for held-key effects")
        h.model.previewOnKeyboard()
        try awaitState("extended effect uploaded") { !h.model.busy && h.model.onboardPreviewActive }
        try expect((h.bus.activePreview() ?? []).count > 344 && h.bus.activePreview()?[344] == 9,
                   "The extended effect ID must be encoded and verified on the keyboard")
        try h.shutdown()
        print("PASS: older firmware blocks new-effect writes; extended capability enables verified upload")
    }
    private static func reactiveFirmwareEnablesPlaybackAndSave() throws {
        let h = try Harness("reactive-firmware-capability")
        h.bus.previewFirmware = true; h.bus.extendedEffects = true; h.bus.persistentFirmware = true
        try h.connect(2053)
        try h.confirmAllPreviewKeys()
        h.model.settings.effect = .keyToggle
        for effect in OnboardProfile.effectIDs.dropFirst(19).prefix(5) { h.model.addLayer(effect) }
        h.model.checkOnboardPreviewSupport()
        try awaitState("old firmware capability for reactive layers") { !h.model.busy && h.model.onboardPreviewAvailable }
        try expect(!h.model.onboardCompatibleDraft && h.model.onboardMaximumEffectID == 17,
                   "v1.0/v1.1 must continue to block new reactive effects")
        let writesBefore = h.bus.writes(2053).count
        h.model.previewOnKeyboard(); h.model.saveOnKeyboard()
        try expect(h.bus.writes(2053).count == writesBefore, "Rejected drafts must never send profile bytes")
        h.bus.reactiveEffects = true
        h.model.checkOnboardPreviewSupport()
        try awaitState("v1.2 capability discovery") { !h.model.busy && h.model.onboardMaximumEffectID == 23 }
        try expect(h.model.onboardPreviewAvailable && h.model.onboardPersistentAvailable && h.model.onboardCompatibleDraft,
                   "v1.2 must enable both send and save controls for all six reactive layers")
        try expect(!h.model.onboardPreviewStatus.contains("v0.7") && h.model.onboardPreviewStatus.contains("permanent save"),
                   "v1.2 cannot show an old-firmware warning")
        h.model.previewOnKeyboard()
        try awaitState("v1.2 reactive layout sent") { !h.model.busy && h.model.onboardPreviewActive }
        try expect(h.model.onboardPreviewLayerCount == 6 && !h.model.onboardLastTransferPersistent,
                   "All six new effects must upload and verify without persistent commit")
        h.model.saveOnKeyboard()
        try awaitState("v1.2 reactive layout saved") { !h.model.busy && h.model.onboardLastTransferPersistent }
        try expect(h.model.onboardPreviewLayerCount == 6 && h.model.onboardPreviewActive,
                   "Permanent save must read back the complete six-layer v1.2 profile")
        h.model.addLayer(.matrixRain)
        try expect(!h.model.onboardCompatibleDraft, "v1.2 blocks a Matrix layer")
        let beforeMatrix = h.bus.writes(2053).count
        h.model.previewOnKeyboard(); h.model.saveOnKeyboard()
        try expect(h.bus.writes(2053).count == beforeMatrix, "v1.2 receives no Matrix writes")
        h.model.stopOnboardPreview()
        try awaitState("stop before firmware rediscovery") { !h.model.busy && !h.model.onboardPreviewActive }
        h.bus.matrixEffects = true; h.model.checkOnboardPreviewSupport()
        try awaitState("v1.3 Matrix support") { !h.model.busy && h.model.onboardMaximumEffectID == 24 }
        try expect(h.model.onboardCompatibleDraft, "v1.3 enables mixed reactive and Matrix layers")
        h.model.previewOnKeyboard()
        try awaitState("v1.3 Matrix preview") { !h.model.busy && h.model.onboardPreviewLayerCount == 7 }
        h.model.saveOnKeyboard()
        try awaitState("v1.3 Matrix save") { !h.model.busy && h.model.onboardLastTransferPersistent }
        try h.shutdown()
        print("PASS: v1.2 enables Send and Save for every new reactive layer; v1.0/v1.1 still reject them")
    }
    private static func onboardPreviewVerifiesDraftAndDoesNotSave() throws {
        let h = try Harness("preview-success")
        h.bus.previewFirmware = true
        try h.connect(2101); try h.start(.staticColor)
        let saved = try Data(contentsOf: h.profileURL)
        try h.confirmAllPreviewKeys()
        h.model.addLayer(.rainbowRipple)
        h.model.setLayerKeys(["KeyW", "KeyA", "KeyS", "KeyD"])
        h.model.selectedLayer.affectAllKeys = true
        h.model.checkOnboardPreviewSupport()
        try awaitState("preview capability") { !h.model.busy && h.model.onboardPreviewAvailable }
        try expect(h.bus.recorded(2101).contains { $0.kind == "read" && $0.payload == [8, 3, 7, 0] },
                   "Capability must be read before upload")
        h.model.previewOnKeyboard()
        try awaitState("temporary onboard preview") { !h.model.busy && h.model.onboardPreviewActive }
        let active = h.bus.activePreview() ?? []
        try expect(active.count > 400 && active[5] == 0 && active[6] == 2,
                   "Current draft layers must be encoded into the active keyboard profile")
        try expect(active[20] == 0 && h.model.state?.effect == 20 && h.model.effect == 20 && !h.model.playing,
                   "Keyboard mode 20 must replace Mac RGB streaming after readback")
        try expect(h.model.onboardPreviewStatus.contains("bytes, CRC") &&
                   h.model.onboardPreviewStatus.contains("CRC") &&
                   h.model.onboardPreviewStatus.contains("nothing was saved"),
                   "Successful preview must state exact readback and temporary storage")
        try expect(try Data(contentsOf: h.profileURL) == saved,
                   "Preview must preserve the saved Mac profile byte for byte")
        let writes = h.bus.writes(2101).filter { $0.payload.count >= 4 && $0.payload[2] == 7 }
        try expect(writes.contains { $0.payload[3] == 7 } && !writes.contains { $0.payload[3] == 4 },
                   "Preview must use RAM activation and never persistent commit")
        h.model.stopOnboardPreview()
        try awaitState("stop temporary preview") { !h.model.busy && !h.model.onboardPreviewActive }
        try expect(h.model.state?.effect == 1 && h.model.onboardPreviewStatus.contains("saved Mac profile was not changed") &&
                   (try Data(contentsOf: h.profileURL)) == saved,
                   "Stop preview must verify the replacement effect and preserve the saved profile")
        h.model.previewOnKeyboard()
        try awaitState("preview again after stop") { !h.model.busy && h.model.onboardPreviewActive }
        h.bus.remove()
        try awaitState("preview unplugged") { !h.model.connected }
        try expect(!h.model.onboardPreviewActive && !h.model.onboardPreviewAvailable,
                   "Preview capability and active state expire on disconnect")
        h.bus.attach(2102)
        try awaitState("keyboard reconnected") { h.model.connected && !h.model.busy }
        try expect(h.model.onboardPreviewAvailable && !h.model.onboardPreviewActive &&
                   h.bus.activePreview()?.isEmpty == true,
                   "Fresh connection must discover capability automatically; the RAM preview must be gone")
        try h.shutdown(); print("PASS: draft preview is read back, leaves Mac profile intact, and expires on reconnect")
    }
    private static func onboardPreviewSupportsSixteenLayers() throws {
        let h = try Harness("preview-sixteen-layers")
        h.bus.previewFirmware = true
        try h.connect(2151); try h.confirmAllPreviewKeys()
        for index in 0..<15 {
            h.model.addLayer(index.isMultiple(of: 3) ? .ripple : .staticColor)
        }
        try expect(h.model.layers.count == 16, "The editor must accept the firmware's full sixteen-layer format")
        h.model.checkOnboardPreviewSupport()
        try awaitState("sixteen-layer preview capability") { !h.model.busy && h.model.onboardPreviewAvailable }
        h.model.previewOnKeyboard()
        try awaitState("sixteen-layer preview") { !h.model.busy && h.model.onboardPreviewActive }
        let active = h.bus.activePreview() ?? []
        try expect(active.count > 1000 && active[6] == 16 && h.model.onboardPreviewLayerCount == 16 &&
                   h.model.onboardPreviewStatus.contains("16-layer"),
                   "All sixteen layers must be transferred, read back, and shown as active")
        let beforeSave = h.bus.writes(2151).count
        h.model.saveDraftToMac()
        try expect((try h.saved()).studioLayers.count == 16 && !(try h.saved()).resume &&
                   h.bus.writes(2151).count == beforeSave && h.model.onboardPreviewActive,
                   "Saving an editable Mac copy must not flash, interrupt, or replace the keyboard preview")
        try h.shutdown(); print("PASS: sixteen layers upload and read back; saving a Mac draft does not write keyboard storage")
    }
    private static func onboardSaveRequiresPersistentFirmware() throws {
        let h = try Harness("persistent-save")
        h.bus.previewFirmware = true
        try h.connect(2161); try h.confirmAllPreviewKeys()
        for index in 0..<15 { h.model.addLayer(index.isMultiple(of: 2) ? .ripple : .staticColor) }
        h.model.checkOnboardPreviewSupport()
        try awaitState("RAM-only capability") { !h.model.busy && h.model.onboardPreviewAvailable }
        try expect(!h.model.onboardPersistentAvailable, "RAM-only firmware must not expose permanent save")
        h.model.saveOnKeyboard(); pump(0.02)
        try expect(h.bus.writes(2161).isEmpty, "RAM-only firmware must receive no save writes")
        h.bus.persistentFirmware = true
        h.model.checkOnboardPreviewSupport()
        try awaitState("persistent capability") { !h.model.busy && h.model.onboardPersistentAvailable }
        h.model.saveOnKeyboard()
        try awaitState("verified persistent save") { !h.model.busy && h.model.onboardPreviewActive }
        let saved = h.bus.activePreview() ?? []
        try expect(saved.count > 1000 && saved[6] == 16 &&
                   h.bus.writes(2161).filter { $0.payload.prefix(4) == [7, 3, 7, 4] }.count == 1 &&
                   h.model.onboardPreviewStatus.contains("full readback verified"),
                   "Permanent save must commit exactly once and verify all sixteen layers")
        h.bus.remove()
        try awaitState("saved keyboard unplugged") { !h.model.connected }
        h.bus.attach(2162)
        try awaitState("saved keyboard reconnected") { h.model.connected && !h.model.busy }
        try expect(h.bus.activePreview() == saved,
                   "Mock flash must retain the validated layout after a simulated power cycle")
        try h.shutdown(); print("PASS: permanent save is firmware-gated, commits once, reads back, and retains sixteen layers in mock flash")
    }
    private static func onboardSaveNeverRetriesLostCommitReply() throws {
        let h = try Harness("lost-commit-reply")
        h.bus.previewFirmware = true; h.bus.persistentFirmware = true; h.bus.loseCommitReply = true
        try h.connect(2171); try h.confirmAllPreviewKeys()
        h.model.checkOnboardPreviewSupport()
        try awaitState("persistent capability") { !h.model.busy && h.model.onboardPersistentAvailable }
        h.model.saveOnKeyboard()
        try awaitState("lost commit reply") { !h.model.busy }
        try expect(h.bus.writes(2171).filter { $0.payload.prefix(4) == [7, 3, 7, 4] }.count == 1 &&
                   !h.model.onboardPersistentAvailable && h.model.onboardPreviewStatus.contains("Save result is uncertain"),
                   "A lost commit reply must not trigger a second flash write or claim success")
        try h.shutdown(); print("PASS: uncertain permanent commit is never retried automatically")
    }
    private static func onboardPreviewRejectsUnbridgedSensors() throws {
        let h = try Harness("preview-sensor")
        h.bus.previewFirmware = true
        try h.connect(2201); try h.confirmAllPreviewKeys()
        h.model.addLayer(.adaptiveMusic)
        h.model.checkOnboardPreviewSupport()
        try awaitState("sensor preview capability") { !h.model.busy && h.model.onboardPreviewAvailable }
        h.model.previewOnKeyboard()
        try expect(h.model.onboardPreviewStatus.contains("sensor updates") &&
                   h.bus.writes(2201).isEmpty,
                   "Sensor-dependent drafts must be refused before upload until telemetry is wired")
        try h.shutdown(); print("PASS: preview does not silently accept music or temperature without sensor updates")
    }
    private static func onboardPreviewReadbackFailure() throws {
        let h = try Harness("preview-readback")
        h.bus.previewFirmware = true; h.bus.corruptPreviewReadback = true
        try h.connect(2301); try h.confirmAllPreviewKeys()
        h.model.checkOnboardPreviewSupport()
        try awaitState("readback test capability") { !h.model.busy && h.model.onboardPreviewAvailable }
        h.model.previewOnKeyboard()
        try awaitState("failed preview readback") { !h.model.busy && !h.model.onboardPreviewAvailable }
        try expect(!h.model.onboardPreviewActive && h.model.onboardPreviewStatus.contains("may have started"),
                   "Corrupt readback must not claim verified playback or a definite rollback")
        try expect(h.bus.writes(2301).allSatisfy { $0.payload[2] != 7 || $0.payload[3] != 4 },
                   "Failed preview must never persist a profile")
        try h.shutdown(); print("PASS: corrupted readback reports uncertainty and never says saved")
    }
    private static func onboardPreviewDisconnectDuringTransfer() throws {
        let h = try Harness("preview-unplug")
        h.bus.previewFirmware = true
        try h.connect(2401); try h.confirmAllPreviewKeys()
        h.model.checkOnboardPreviewSupport()
        try awaitState("disconnect test capability") { !h.model.busy && h.model.onboardPreviewAvailable }
        let held = h.bus.holdNextPreviewChunk()
        h.model.previewOnKeyboard()
        try awaitState("held preview chunk") { h.bus.isHeld }
        h.bus.remove(); held.release.signal()
        try awaitState("preview interruption") { !h.model.connected && !h.model.busy }
        try expect(!h.model.onboardPreviewActive && !h.model.onboardPreviewAvailable,
                   "Unplug during transfer must clear preview state")
        try expect(h.bus.writes(2401).allSatisfy { $0.payload[2] != 7 || $0.payload[3] != 4 },
                   "Unplugged preview must never issue flash commit")
        print("PASS: unplug during temporary upload clears capability and avoids persistent writes")
    }
    private static func wirelessSleepSettings() throws {
        let old = try Harness("sleep-legacy")
        try old.connect(1701)
        try expect(!old.model.sleepSupported && old.bus.writes(1701).isEmpty, "v0.2 must remain connected with sleep controls locked")
        old.model.sleepAfterSeconds = 0; old.model.applySleepTime(); pump(0.03)
        try expect(old.bus.writes(1701).isEmpty, "Unsupported sleep settings must never write")
        try old.shutdown()
        let h = try Harness("sleep-settings")
        h.bus.wireless = true; h.bus.adjustableSleep = true
        try h.connect(1702)
        try expect(h.model.sleepSupported && h.model.appliedSleepSeconds == 300 && h.bus.writes(1702).isEmpty, "Connecting reads the actual sleep time without changing it")
        h.model.sleepAfterSeconds = 0; h.model.applySleepTime()
        try awaitState("verified Never setting") { !h.model.busy && h.model.appliedSleepSeconds == 0 }
        let settings = h.profileURL.deletingLastPathComponent().appendingPathComponent("keyboard-settings.json")
        try expect(try KeyboardPreferences.load(from: settings)?.sleepSeconds == 0, "Save Never only after readback verifies")
        try expect(!FileManager.default.fileExists(atPath: h.profileURL.path), "Sleep settings must not create or replace a lighting profile")
        h.model.disconnect(); try awaitState("sleep disconnect") { !h.model.busy }
        try h.connect(1703)
        try expect(h.model.appliedSleepSeconds == 0 && h.bus.writes(1703).count == 1 && h.bus.writes(1703)[0].payload[2] == 6,
                   "Reconnection restores only the saved sleep control before any lighting restore")
        try h.shutdown()
        print("PASS: v0.2 sleep controls remain locked; verified Never persists independently and restores after reconnect")
    }
    private static func receiverRecoversWithoutReplug() throws {
        let h = try Harness("receiver-sleep")
        h.bus.wireless = true
        try h.connect(5088); try h.start(.wave)
        try expect(h.model.connectionName == "2.4 GHz", "Receiver connection must be named accurately")
        h.bus.setAwake(false); h.bus.advance(0.1)
        try awaitState("radio timeout") { !h.model.connected && !h.model.busy }
        let opens = h.bus.recorded(5088).filter { $0.kind == "open" }.count
        pump(0.08)
        try expect(h.bus.recorded(5088).filter { $0.kind == "open" }.count == opens, "Wireless retries must back off")
        h.bus.setAwake(true); h.bus.advance(6)
        try awaitState("same receiver recovery") { h.model.connected && h.model.playing && !h.model.busy }
        try expect(h.bus.snapshot().registryID == 5088, "Recovery must work without replacing the receiver attachment")
        try h.shutdown()
        h.bus.advance(6); pump(0.08)
        try expect(!h.model.connected, "Manual Disconnect must suppress wireless retries")
        print("PASS: receiver timeout backs off, resumes the saved effect on the same dongle, and honors manual Disconnect")
    }
    private static func sleepSettingDuringAnimation() throws {
        let h = try Harness("sleep-during-frame")
        h.bus.adjustableSleep = true
        try h.connect(1710); try h.start(.wave)
        let saved = try h.saved()
        let held = h.bus.holdNextRGBWrite(); h.bus.advance(0.15)
        try awaitState("animation frame in flight") { h.bus.isHeld }
        h.model.sleepAfterSeconds = 600; h.model.applySleepTime()
        h.model.applySleepTime()
        try expect(h.model.busy, "A sleep change queues behind the current frame")
        held.release.signal()
        try awaitState("queued sleep setting") { !h.model.busy && h.model.appliedSleepSeconds == 600 }
        h.bus.advance(0.2); pump(0.05)
        try expect(h.bus.writes(1710).filter { $0.payload[2] == 6 }.count == 1, "Animation and duplicate clicks must not repeat the sleep write")
        try expect(h.model.playing && h.model.connected && h.saved().studioLayers == saved.studioLayers, "Changing sleep must preserve running layers")
        try h.shutdown()
        print("PASS: Apply sleep remains usable during animation, sends once after the in-flight frame, and preserves the saved layers")
    }
    private static func frameRatePersists() throws {
        let h = try Harness("frame-rate")
        try h.connect(8200)
        h.model.animationFPS = 90
        try h.start(.ripple)
        try expect(h.model.playingFPSLimit == 90 && (try h.saved()).frameRate == 90, "Applied FPS must save")
        h.model.animationFPS = 15
        try expect(h.model.hasLayerChanges && h.model.playingFPSLimit == 90, "Draft FPS cannot silently change running playback")
        h.bus.remove(); try awaitState("FPS disconnect") { !h.model.connected }
        h.bus.attach(8201); try awaitState("FPS restored") { h.model.connected && h.model.playing }
        try expect(h.model.playingFPSLimit == 90 && h.model.animationFPS == 15, "Reconnect restores saved FPS and preserves unapplied draft")
        h.model.startStudio(); try awaitState("new FPS applied") { !h.model.busy && h.model.playingFPSLimit == 15 }
        let saved = try h.saved(); try expect(saved.frameRate == 15, "Updated frame rate must save")
        try h.shutdown()
        let restored = try Harness("frame-rate-relaunch", initialProfile: saved)
        try expect(restored.model.animationFPS == 15, "Relaunch must restore selected FPS")
        try restored.shutdown()
        print("PASS: FPS cap persists, restores across reconnect/relaunch and stays isolated from unapplied edits")
    }
    private static func liveInputLifecycle() throws {
        let inputs = MockLightingInputs()
        let h = try Harness("sensor-lifecycle", makeInputs: { inputs })
        try h.connect(8100)
        try expect(inputs.requests.isEmpty, "Connection cannot start audio capture")
        try h.start(.cpuTemperature)
        try expect(inputs.requests.count == 1 && inputs.requests[0].1 && !inputs.requests[0].0, "CPU layer starts only temperature")
        var snapshot = LightingInputs(); snapshot.cpuCelsius = 70; snapshot.temperatureTimestamp = h.bus.clock()
        inputs.callbacks[0](snapshot)
        try awaitState("temperature input") { h.model.liveInputs.cpuCelsius == 70 && (h.bus.colors()?.first?.g ?? 0) > 0 }
        h.model.addLayer(.adaptiveMusic); h.model.addLayer(.adaptiveMusic)
        h.model.startStudio()
        try awaitState("shared audio source") { !h.model.busy && inputs.requests.count == 2 }
        try expect(inputs.requests[1].0 && inputs.requests[1].1, "Multiple music layers must share one source with CPU")
        h.model.stopPlayback()
        inputs.callbacks[1](snapshot); pump(0.03)
        try expect(h.model.liveInputs.cpuCelsius == nil && inputs.stops >= 2, "Stopped inputs cannot republish late results")
        h.model.resumeSavedLighting()
        try awaitState("resumed inputs") { inputs.requests.count == 3 && h.model.playing }
        h.bus.remove()
        try awaitState("unplugged input source") { !h.model.connected && !h.model.playing }
        inputs.callbacks[2](snapshot); pump(0.03)
        try expect(h.model.liveInputs.cpuCelsius == nil, "Unplugging invalidates in-flight sensor updates")
        try h.shutdown()
        print("PASS: capture starts only for applied layers, music layers share one source, and stop/unplug reject late callbacks")
    }
    private static func layersRestoreAppliedSnapshot() throws {
        let h = try Harness("layer-reconnect")
        try h.connect(1401)
        h.model.settings.effect = .staticColor
        h.model.selectedColor = ControllerModel.color(RGB(r: 0, g: 0, b: 200))
        h.model.addLayer(.staticColor)
        h.model.selectedColor = ControllerModel.color(RGB(r: 240, g: 0, b: 0))
        h.model.selectedLayer.name = "Escape overlay"
        h.model.selectedLayer.opacity = 0.5; h.model.setLayerKeys(["Escape"])
        h.model.startStudio()
        try awaitState("layered start") { h.model.playing && !h.model.busy }
        let saved = try h.saved(), applied = h.bus.colors()
        try expect(saved.layers == h.model.layers && saved.layers?.count == 2, "Every applied layer must be saved in order")
        try expect(!h.model.hasLayerChanges && applied?[0] == RGB(r: 120, g: 0, b: 100) && applied?[1] == RGB(r: 0, g: 0, b: 200), "Hardware must receive the composed masked frame")
        h.model.selectedLayer.opacity = 0; h.model.selectedLayer.name = "Draft change"
        h.model.addLayer(.spectrum)
        try expect(h.model.hasLayerChanges, "Draft changes must be marked unapplied")
        h.bus.advance(0.5); pump(0.05)
        try expect(h.bus.colors() == applied && (try h.saved()).layers == saved.layers, "Draft layer edits must not change live lighting or the saved profile")
        h.bus.remove(); try awaitState("layer USB removal") { !h.model.connected }
        h.bus.attach(1402)
        try awaitState("layered reconnect") { h.model.connected && h.model.playing && !h.model.busy }
        try expect(h.bus.colors() == applied, "Reconnect must restore the applied stack instead of draft layers")
        try expect(h.model.layers.count == 3 && h.model.hasLayerChanges, "Reconnect must also retain unsaved editor changes")
        let restored = try Harness("layer-relaunch", initialProfile: saved)
        try expect(restored.model.layers == saved.layers, "Relaunch must restore layer IDs, order, names and masks")
        try restored.shutdown(); try h.shutdown()
        print("PASS: composed layers save, restore on reconnect/relaunch, and remain isolated from unapplied edits")
    }
    private static func layerEditingIsIsolated() throws {
        let h = try Harness("layer-selection")
        try h.connect(1501); try h.start()
        let before = h.bus.writes(1501).count
        let mappingEncoder = JSONEncoder(); mappingEncoder.outputFormatting = [.sortedKeys]
        let mapBytes = try mappingEncoder.encode(h.model.map)
        let saved = try Data(contentsOf: h.profileURL)
        h.model.setLayerKeys([]); h.model.selectingLayerKeys = true
        h.model.click(h.model.keys.first { $0.id == "Escape" }!)
        try expect(h.model.selectedLayer.keyIDs == ["Escape"], "Clicking while choosing keys must toggle layer membership")
        h.model.duplicateLayer()
        try expect(h.model.layers.count == 2 && Set(h.model.layers.map(\.id)).count == 2, "Duplicate must copy options with a new identity")
        let duplicate = h.model.selectedLayer.id
        h.model.moveLayer(1)
        try expect(h.model.layers.last?.id == duplicate, "Move must reorder the selected layer")
        h.model.removeLayer(); h.model.removeLayer()
        try expect(h.model.layers.isEmpty && h.model.canUndoWorkspace, "Removing the last layer must leave an empty draft with Undo")
        h.model.mappingMode = true
        try expect(!h.model.selectingLayerKeys, "Mapping mode must leave layer key selection")
        pump(0.04)
        try expect(h.bus.writes(1501).count == before, "Layer edits and key selection must not send lighting writes")
        try expect(try mappingEncoder.encode(h.model.map) == mapBytes, "Layer key selection must not change key-to-LED assignments")
        try expect(try Data(contentsOf: h.profileURL) == saved, "Layer edits must not overwrite the saved stack before Apply")
        try h.shutdown(); print("PASS: layer key selection, duplication, reorder and removal preserve mapping and applied lighting")
    }
    private static func reactiveLayerRevealsBackground() throws {
        let h = try Harness("layer-reactive")
        try h.connect(1601)
        let blue = RGB(r: 0, g: 0, b: 200), red = RGB(r: 240, g: 0, b: 0)
        h.model.settings.effect = .staticColor; h.model.selectedColor = ControllerModel.color(blue)
        h.model.addLayer(.reactive); h.model.selectedColor = ControllerModel.color(red)
        h.model.startStudio(); try awaitState("reactive layer start") { h.model.playing && !h.model.busy }
        try expect(h.bus.colors()?.allSatisfy { $0 == blue } == true, "Idle reactive overlay must leave the background visible")
        h.model.keyPressed("Escape")
        try awaitState("reactive layer press") { h.bus.colors()?[0] == red }
        h.bus.advance(0.7)
        try awaitState("reactive layer fade") { h.bus.colors()?[0] == RGB(r: 60, g: 0, b: 150) }
        h.bus.advance(1)
        try awaitState("background restored") { h.bus.colors()?.allSatisfy { $0 == blue } == true }
        h.model.stopPlayback()
        try expect((try h.saved()).layers?.count == 2 && !(try h.saved()).resume, "Pause must preserve the complete layer stack")
        try h.shutdown(); print("PASS: physical-key events animate an overlay back into its background through the serialized USB renderer")
    }
    private static func toggleFollowsSuccessivePresses() throws {
        let h = try Harness("layer-toggle")
        try h.connect(1649)
        let blue = RGB(r: 0, g: 0, b: 180), red = RGB(r: 240, g: 0, b: 0)
        h.model.settings.effect = .staticColor; h.model.selectedColor = ControllerModel.color(blue)
        h.model.addLayer(.keyToggle); h.model.selectedColor = ControllerModel.color(red)
        h.model.setLayerKeys(["Escape"])
        h.model.startStudio(); try awaitState("toggle start") { h.model.playing && !h.model.busy }
        h.model.keyPressed("Escape"); try awaitState("toggle on") { h.bus.colors()?[0] == red }
        h.model.keyPressed("Escape"); pump(0.04)
        try expect(h.bus.colors()?[0] == red, "Repeated key down must never toggle")
        h.model.keyReleased("Escape"); h.bus.advance(20); pump(0.04)
        try expect(h.bus.colors()?[0] == red, "Release and time must not clear a toggle")
        h.model.keyPressed("Escape"); try awaitState("toggle off") { h.bus.colors()?[0] == blue }
        h.model.keyReleased("Escape"); h.model.keyPressed("Escape")
        try awaitState("toggle back on") { h.bus.colors()?[0] == red }
        h.model.stopPlayback(); h.model.startStudio()
        try awaitState("toggle state reset") { h.model.playing && !h.model.busy && h.bus.colors()?[0] == blue }
        try h.shutdown(); print("PASS: toggle on/off ignores repeats and releases, and resets for a new playback")
    }
    private static func heldKeyFollowsPhysicalRelease() throws {
        let h = try Harness("layer-hold")
        try h.connect(1651)
        let blue = RGB(r: 0, g: 0, b: 180), red = RGB(r: 240, g: 0, b: 0)
        h.model.settings.effect = .staticColor; h.model.selectedColor = ControllerModel.color(blue)
        h.model.addLayer(.keyHold); h.model.selectedColor = ControllerModel.color(red)
        h.model.setLayerKeys(["Escape"])
        h.model.startStudio(); try awaitState("held layer start") { h.model.playing && !h.model.busy }
        h.model.keyPressed("Escape")
        try awaitState("held key lights") { h.bus.colors()?[0] == red }
        h.bus.advance(5); pump(0.04)
        try expect(h.bus.colors()?[0] == red, "Held key must not time out or fade")
        h.model.keyReleased("Escape")
        try awaitState("released key clears") { h.bus.colors()?[0] == blue }
        h.model.keyPressed("Escape")
        try awaitState("second held key lights") { h.bus.colors()?[0] == red }
        h.bus.remove(); try awaitState("held keyboard disconnected") { !h.model.connected }
        h.bus.attach(1652)
        try awaitState("held keyboard reconnects") { h.model.connected && h.model.playing && !h.model.busy }
        try awaitState("held state cleared on reconnect") { h.bus.colors()?[0] == blue }
        h.model.click(h.model.keys.first { $0.id == "Escape" }!)
        try awaitState("virtual key preview lights") { h.bus.colors()?[0] == red }
        try awaitState("virtual key preview releases", timeout: 2) { h.bus.colors()?[0] == blue }
        try h.shutdown()
        print("PASS: physical release, disconnect and virtual-key preview cannot leave hold lighting stuck")
    }
    private static func wasdTriggersWholeKeyboard(effect: LightingEffect = .ripple) throws {
        let h = try Harness("wasd-reach-\(effect.rawValue)")
        try h.connect(1701)
        h.model.map = try MappingFile.rowOrder(keys: h.model.keys)
        let blue = RGB(r: 0, g: 0, b: 200), red = RGB(r: 240, g: 0, b: 0)
        let triggers = ["KeyA", "KeyD", "KeyS", "KeyW"]
        h.model.settings.effect = .staticColor; h.model.selectedColor = ControllerModel.color(blue)
        h.model.addLayer(effect); h.model.selectedColor = ControllerModel.color(red)
        h.model.setLayerKeys(triggers); h.model.selectedLayer.affectAllKeys = true
        h.model.startStudio(); try awaitState("whole keyboard ripple start") { h.model.playing && !h.model.busy }
        h.model.keyPressed("KeyQ"); h.bus.advance(0.125); pump(0.04)
        try expect(h.bus.colors()?.allSatisfy { $0 == blue } == true, "An unselected key must not start or dim a WASD ripple")
        h.model.keyPressed("KeyW"); h.bus.advance(0.125)
        try awaitState("ripple reaches E outside WASD") { (h.bus.colors()?[40].r ?? 0) > 190 }
        let saved = try h.saved()
        try expect(saved.layers?[0].settings.effect == effect, "The selected ripple type must survive save and restore")
        try expect(saved.layers?[0].affectAllKeys == true && saved.layers?[0].keyIDs == triggers, "Apply must save reach and triggers independently")
        h.bus.remove(); try awaitState("WASD ripple removal") { !h.model.connected }
        h.bus.attach(1702)
        try awaitState("WASD ripple restore") { h.model.connected && h.model.playing && !h.model.busy }
        try expect(h.model.selectedLayer.affectAllKeys && h.model.selectedLayer.keyIDs == triggers, "Reconnect must retain trigger selection and whole-keyboard reach")
        h.model.previewPulse()
        try expect(triggers.contains(h.model.lastPressedKey), "Test key pulse must choose a key that actually triggers the selected active layer")
        h.model.selectedLayer.affectAllKeys = false; h.model.startStudio()
        try awaitState("limited ripple start") { h.model.playing && !h.model.busy }
        h.model.keyPressed("KeyW"); h.bus.advance(0.125); pump(0.05)
        try expect(h.bus.colors()?[40] == blue && h.model.selectedLayer.keyIDs == triggers, "Turning reach off must contain the ripple while retaining WASD triggers")
        try h.shutdown(); print("PASS: WASD triggers \(effect.displayName) across the keyboard, rejects other keys, and preserves reach through save/reconnect")
    }
    private static func indicatorLightsDoNotDisconnect() throws {
        let h = try Harness("status-light")
        h.bus.overrideColors([57: RGB(r: 255, g: 255, b: 255)])
        try h.connect(1101)
        h.model.mappingMode = true; h.model.manualMapping = true
        for index in [0, 1, 59, 103] {
            h.model.mappingIndex = index; h.model.identify()
            try awaitState("status-light identify") { !h.model.busy }
            try expect(h.model.connected && h.model.illuminatedIndex == index, "Firmware indicator must not disconnect or block identify")
            try expect(!h.model.indicatorNotice.isEmpty, "Active firmware override must be explained in the UI")
        }
        try h.shutdown(); print("PASS: active status light does not disconnect identification across the keyboard")
    }
    private static func verificationErrorKeepsVerifiedConnection() throws {
        let h = try Harness("color-mismatch")
        try h.connect(1201)
        h.bus.overrideColors([58: RGB(r: 255, g: 255, b: 255)])
        h.model.mappingMode = true; h.model.manualMapping = true; h.model.identify()
        try awaitState("reported mismatch") { !h.model.busy }
        try expect(h.model.connected && h.model.illuminatedIndex == nil && h.model.status.contains("USB is still connected"), "Color mismatch must fail the action while retaining verified USB")
        try expect(!h.bus.recorded(1201).contains { $0.kind == "close" }, "Non-transport failure must not close the input session")
        h.bus.overrideColors([:]); h.model.identify()
        try awaitState("retry without reconnect") { !h.model.busy && h.model.illuminatedIndex == 1 }
        try h.shutdown(); print("PASS: real color mismatches remain errors, and a verified connection permits manual retry")
    }
    private static func applyRowOrderAndTestWithoutRemapping() throws {
        let h = try Harness("row-layout")
        try h.connect(1301); h.model.mappingMode = true
        let writes = h.bus.writes(1301).count
        h.model.applyRowMapping()
        try expect(h.model.mappedCount == 104 && h.model.isRowMapping && !h.model.manualMapping, "Row preset maps the complete keyboard")
        try expect(h.bus.writes(1301).count == writes, "Applying a map must not write lighting")
        let saved = try Data(contentsOf: h.mappingURL)
        h.model.click(h.model.keys.first { $0.id == "F1" }!)
        try awaitState("click-to-test F1") { !h.model.busy && h.model.illuminatedIndex == 1 }
        h.model.keyPressed("KeyA")
        try awaitState("physical-key preview") { !h.model.busy && h.model.illuminatedIndex == 58 }
        try expect(try Data(contentsOf: h.mappingURL) == saved, "Testing keys must never reassign or save mappings")
        h.model.undoMappingReset()
        try expect(h.model.mappedCount == 1, "Undo restores the previous map after applying row order")
        try h.shutdown(); print("PASS: one-click row layout is undoable, and click/press testing never changes assignments")
    }
    private static func noProfileIsReadOnly() throws {
        let h = try Harness("read-only")
        h.bus.attach(101)
        try awaitState("automatic connection without saved profile") { h.model.connected && !h.model.busy }
        try awaitState("read-only connection") { h.model.connected && !h.model.busy }
        h.model.enableKeyboardInput()
        try expect(!h.model.keyResponseEnabled, "Mock environment must never enable real keyboard monitoring")
        try expect(h.bus.writes(101).isEmpty, "First connect must not write lighting")
        try expect(h.model.mappedCount == 1, "Test must use fixture mapping, not the user's map")
        try expect(!FileManager.default.fileExists(atPath: h.profileURL.path), "First connect must not save a profile")
        try h.shutdown(); print("PASS: initial connection is read-only and uses isolated fixture resources")
    }
    private static func reconnectRestoresAfterGate() throws {
        let h = try Harness("reconnect")
        try h.connect(201); try h.start()
        let saved = try h.saved(), expected = h.bus.colors()
        try expect(saved.resume && saved.mode == .studio, "Successful Start saves a resumable studio profile")
        h.bus.remove()
        try awaitState("USB removal") { !h.model.connected && !h.model.playing }
        h.bus.attach(202)
        try awaitState("automatic profile restoration") { h.model.connected && h.model.playing && !h.model.busy && !h.bus.writes(202).isEmpty }
        try expect(h.bus.colors() == expected, "Reconnection restores the saved effect frame")
        let events = h.bus.recorded(202)
        guard let write = events.firstIndex(where: { $0.kind == "write" }) else { throw ControllerError.message("No restoration write") }
        try expect(events[..<write].contains { $0.kind == "read" } && events[..<write].contains { $0.kind == "gate" }, "Firmware read and attachment gate must precede restoration writes")
        try expect(events.first?.kind == "open", "Reconnection must open a new transport session")
        try h.shutdown(); print("PASS: Start/save survives removal and restores only after the new attachment is verified")
    }
    private static func pauseAndResumePersist() throws {
        let h = try Harness("resume")
        try h.connect(301); try h.start()
        h.model.stopPlayback()
        try expect(!h.model.playing && !(try h.saved()).resume, "Stop persists resume=false")
        h.bus.remove()
        try awaitState("paused USB removal") { !h.model.connected }
        h.bus.attach(302)
        try awaitState("paused reconnection") { h.model.connected && !h.model.busy }
        pump(0.06)
        try expect(!h.model.playing && h.bus.writes(302).isEmpty, "Paused profile must not restart on reconnect")
        h.model.resumeSavedLighting()
        try awaitState("explicit resume") { h.model.playing && !h.model.busy }
        try expect((try h.saved()).resume, "Explicit resume must be persisted")
        h.bus.remove()
        try awaitState("resumed USB removal") { !h.model.connected }
        h.bus.attach(303)
        try awaitState("restoration after explicit resume") { h.model.playing && h.model.connected && !h.model.busy }
        try expect(!h.bus.writes(303).isEmpty, "Explicitly resumed profile must restore again")
        try h.shutdown(); print("PASS: Stop stays paused across reconnect, and explicit resume persists for later reconnects")
    }
    private static func mappingSuppressesPlayback() throws {
        let h = try Harness("mapping")
        try h.connect(401); try h.start(.spectrum)
        h.model.mappingMode = true
        try expect(!h.model.playing, "Entering mapping stops animation")
        h.model.identify()
        try awaitState("identify LED") { !h.model.busy && h.model.illuminatedIndex == 1 }
        let identified = h.bus.colors(), before = h.bus.writes(401).count
        h.bus.advance(0.5); pump(0.08)
        try expect(h.bus.colors() == identified && h.bus.writes(401).count == before, "Animation must not overwrite mapping lighting")
        try expect((try h.saved()).settings.effect == .spectrum, "Mapping must preserve the saved effect")
        h.bus.remove()
        try awaitState("mapping USB removal") { !h.model.connected }
        h.bus.attach(402)
        try awaitState("mapping reconnection") { h.model.connected && !h.model.busy }
        h.model.restoreProfile(); h.model.resumeSavedLighting(); h.model.startStudio()
        pump(0.08)
        try expect(!h.model.playing && h.bus.writes(402).isEmpty, "Mapping must suppress automatic restore, explicit resume, and Studio start")
        h.model.mappingMode = false; h.model.resumeSavedLighting()
        try awaitState("resume after leaving mapping") { h.model.playing && !h.model.busy }
        try h.shutdown(); print("PASS: mapping preserves the saved effect and suppresses automatic and explicit streaming")
    }
    private static func wrongFirmwareBlocksRestore() throws {
        let saved = LightingProfile(mode: .studio, settings: LightingSettings(effect: .staticColor))
        let h = try Harness("bad-firmware", initialProfile: saved)
        h.bus.attach(501, valid: false)
        try awaitState("invalid firmware rejection") { h.model.status.contains("Exact custom firmware") && !h.model.busy }
        pump(0.08)
        try expect(!h.model.connected && h.bus.writes(501).isEmpty, "Unknown firmware must block all restore writes")
        try expect(h.bus.recorded(501).filter { $0.kind == "open" }.count == 1, "Rejected attachment must not be retried continuously")
        h.bus.remove(); pump(0.06); h.bus.attach(502)
        try awaitState("valid replacement restoration") { h.model.connected && h.model.playing && !h.model.busy }
        try expect(!h.bus.writes(502).isEmpty, "A newly verified attachment may restore the saved profile")
        try h.shutdown(); print("PASS: invalid firmware blocks writes and repeated retries until attachment changes")
    }
    private static func rapidStopStartDiscardsOldCompletion() throws {
        let h = try Harness("cancellation")
        try h.connect(601); try h.start(.spectrum)
        let hold = h.bus.holdNextRGBWrite()
        h.bus.advance(0.4)
        try awaitState("held animation frame") { h.bus.isHeld }
        h.model.stopPlayback()
        let replacement = RGB(r: 200, g: 10, b: 80)
        h.model.settings.effect = .staticColor; h.model.selectedColor = ControllerModel.color(replacement)
        h.model.startStudio()
        try expect(h.model.busy && !h.model.playing, "Replacement must wait behind the in-flight frame")
        hold.release.signal()
        try awaitState("replacement effect start") { h.model.playing && !h.model.busy && h.model.playingEffectName == "Static color" }
        h.bus.advance(1); pump(0.08)
        let expected = Array(repeating: replacement, count: 104)
        try expect(h.bus.colors() == expected && h.model.frame == expected, "Old animation completion must not replace new hardware or preview state")
        try expect((try h.saved()).settings.effect == .staticColor && (try h.saved()).resume, "Replacement profile must remain saved and resumable")
        try h.shutdown(); print("PASS: rapid Stop/Start serializes USB and discards stale animation completions")
    }
    private static func explicitAndQuickMapping() throws {
        let h = try Harness("quick-mapping")
        try h.connect(701)
        h.model.mappingMode = true; h.model.manualMapping = true; h.model.identify()
        try awaitState("explicit identify") { !h.model.busy && h.model.illuminatedIndex == 1 }
        let before = h.bus.writes(701).count
        h.model.keyPressed("Backquote")
        try expect(!h.model.quickMapping && h.model.selectedMappingKey == "Backquote" && h.model.mappingIndex == 1, "Default physical selection must wait for explicit save")
        try expect(h.model.map?.mappings.first { $0.keyId == "Backquote" }?.ledIndex == nil, "Default selection must not save a mapping")
        let q = h.model.keys.first { $0.id == "KeyQ" }!
        h.model.click(q)
        try expect(h.model.selectedMappingKey == "KeyQ" && h.bus.writes(701).count == before, "Default on-screen selection must not advance or send USB writes")
        try expect(h.model.saveMapping() && h.model.mappingIndex == 1, "Explicit save keeps the currently lit LED")
        h.model.quickMapping = true
        h.model.keyPressed("Backquote")
        try expect(h.model.busy && h.model.mappingIndex == 2, "Quick physical selection saves and immediately starts the next unknown LED")
        h.model.keyPressed("KeyA")
        try expect(h.model.selectedMappingKey.isEmpty, "Key events during identify must be ignored")
        try awaitState("quick next LED") { !h.model.busy && h.model.illuminatedIndex == 2 }
        try expect(h.model.map?.mappings.first { $0.keyId == "Backquote" }?.ledIndex == 1, "Quick physical selection saved the lit LED")
        h.model.click(h.model.keys.first { $0.id == "KeyW" }!)
        try awaitState("quick on-screen next LED") { !h.model.busy && h.model.illuminatedIndex == 3 }
        try expect(h.model.map?.mappings.first { $0.keyId == "KeyW" }?.ledIndex == 2, "Quick on-screen selection saved and advanced")
        h.model.mappingMode = false
        try expect(!h.model.quickMapping && h.model.illuminatedIndex == nil, "Leaving mapping clears quick-mode and selection state")
        try h.shutdown(); print("PASS: explicit mapping remains the default; quick physical and on-screen mapping save then advance")
    }
    private static func resetAndUndoMapping() throws {
        let h = try Harness("reset-mapping")
        try h.connect(801); try h.start()
        let profileBefore = try Data(contentsOf: h.profileURL)
        h.model.mappingMode = true; h.model.manualMapping = true; h.model.identify()
        try awaitState("reset test identify") { !h.model.busy && h.model.illuminatedIndex == 1 }
        h.model.keyPressed("KeyQ"); try expect(h.model.saveMapping(), "Fixture custom mapping saved")
        let previous = try Data(contentsOf: h.mappingURL), writes = h.bus.writes(801).count
        h.model.quickMapping = true; h.model.resetMapping()
        try expect(h.model.mappedCount == 1 && h.model.canUndoMappingReset && !h.model.quickMapping, "Reset restores validated defaults and exposes Undo")
        let backup = h.mappingURL.deletingLastPathComponent().appendingPathComponent("led-map-backup.json")
        try expect(try Data(contentsOf: backup) == previous, "Reset preserves the exact previous mapping in its backup")
        h.model.undoMappingReset()
        try expect(try Data(contentsOf: h.mappingURL) == previous, "Undo restores the complete previous mapping")
        try expect(h.model.map?.mappings.first { $0.keyId == "KeyQ" }?.ledIndex == 1, "Undo also restores the UI mapping")
        try expect(h.bus.writes(801).count == writes, "Reset and Undo must not send any USB writes")
        try expect(try Data(contentsOf: h.profileURL) == profileBefore, "Mapping reset and Undo preserve the lighting profile")
        h.model.mappingMode = false; h.model.resetMapping()
        try expect(try Data(contentsOf: h.mappingURL) == previous, "Reset is disabled outside mapping mode")
        try h.shutdown(); print("PASS: reset backs up the full map, Undo restores it, and both preserve lighting without USB writes")
    }
    private static func backgroundTypingCannotMap() throws {
        let h = try Harness("background-mapping", mappingInputAllowed: { false })
        try h.connect(1001)
        h.model.mappingMode = true; h.model.manualMapping = true; h.model.identify()
        try awaitState("background guard identify") { !h.model.busy && h.model.illuminatedIndex == 1 }
        let writes = h.bus.writes(1001).count
        h.model.quickMapping = true; h.model.keyPressed("KeyQ"); pump(0.04)
        try expect(h.model.selectedMappingKey.isEmpty && h.model.mappingIndex == 1 && h.model.mappedCount == 1,
                   "Typing outside the mapping window must not select or assign a key")
        try expect(h.bus.writes(1001).count == writes, "Background typing must not advance lighting")
        try h.shutdown(); print("PASS: background typing cannot accidentally assign keys in Quick mapping")
    }
    private static func failedMappingSaveDoesNotAdvance() throws {
        let h = try Harness("failed-mapping-save")
        try h.connect(901)
        h.model.mappingMode = true; h.model.manualMapping = true; h.model.identify()
        try awaitState("failed-save identify") { !h.model.busy && h.model.illuminatedIndex == 1 }
        // A directory at the target file is a deterministic filesystem write failure.
        try FileManager.default.createDirectory(at: h.mappingURL, withIntermediateDirectories: false)
        let writes = h.bus.writes(901).count
        h.model.quickMapping = true; h.model.keyPressed("KeyQ"); pump(0.04)
        try expect(h.model.status.contains("Mapping was not saved"), "Failed quick save must report its write error")
        try expect(h.model.mappingIndex == 1 && h.model.illuminatedIndex == 1 && !h.model.busy, "Failed save must keep the same lit LED available")
        try expect(h.model.map?.mappings.first { $0.keyId == "KeyQ" }?.ledIndex == nil, "Failed save must not alter the in-memory mapping")
        try expect(h.bus.writes(901).count == writes, "Failed save must not advance or send lighting writes")
        try h.shutdown(); print("PASS: a failed quick mapping save retains the current LED and never advances")
    }
}

#endif
