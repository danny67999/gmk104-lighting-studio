import Foundation
import SwiftUI

private final class MockBus {
    struct Device {
        let id: UInt64
        var effect = 1
        var brightness = 3
        var colors = Array(repeating: RGB.black, count: 104)
        var validFirmware = true
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
    private var held = false
    private var time: TimeInterval = 1000
    private var firmwareColors: [Int: RGB] = [:]

    private func locked<T>(_ action: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try action()
    }
    func attach(_ id: UInt64, valid: Bool = true) { locked { device = Device(id: id, validFirmware: valid) } }
    func remove() { locked { device = nil } }
    func clock() -> TimeInterval { locked { time } }
    func advance(_ amount: TimeInterval) { locked { time += amount } }
    func snapshot() -> (count: Int, registryID: UInt64?) { locked { (device == nil ? 0 : 1, device?.id) } }
    func recorded(_ id: UInt64) -> [Event] { locked { events.filter { $0.id == id } } }
    func writes(_ id: UInt64) -> [Event] { recorded(id).filter { $0.kind == "write" } }
    func colors() -> [RGB]? { locked { device?.colors } }
    func overrideColors(_ colors: [Int: RGB]) { locked { firmwareColors = colors } }
    var isHeld: Bool { locked { held } }
    func holdNextRGBWrite() -> Hold {
        locked { let hold = Hold(); nextHold = hold; held = false; return hold }
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
            guard p.first == 7, p[2] == 5, let hold = nextHold else { return nil }
            nextHold = nil; held = true; return hold
        }
        if let hold {
            try require(hold.release.wait(timeout: .now() + 5) == .success, "Test failed to release held frame")
            locked { held = false }
        }
        return try locked {
            guard var d = device, d.id == id else { throw ControllerError.message("Mock keyboard disconnected") }
            if p[0] == 7 {
                events.append(Event(id: id, kind: "write", payload: p))
                if p[2] == 1 { d.brightness = Int(p[3]) }
                if p[2] == 2 { d.effect = Int(p[3]) }
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
    let model: ControllerModel
    init(_ name: String, initialProfile: LightingProfile? = nil, mappingInputAllowed: @escaping () -> Bool = { true }, makeInputs: (() -> LightingInputSource)? = nil) throws {
        let root = URL(fileURLWithPath: "mac/.build/ControllerModelTests-\(UUID().uuidString)-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        profileURL = root.appendingPathComponent("lighting-profile.json")
        mappingURL = root.appendingPathComponent("led-map.json")
        try initialProfile?.save(to: profileURL)
        let bus = self.bus
        let fixtureURL = root.appendingPathComponent("default-led-map.json")
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
            makeLightingInputs: makeInputs, inputMonitoringEnabled: false, mappingInputAllowed: mappingInputAllowed,
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
@main private struct ControllerModelTests {
    static func main() throws {
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
        try reactiveLayerRevealsBackground()
        try wasdTriggersWholeKeyboard()
        try wasdTriggersWholeKeyboard(effect: .rainbowRipple)
        print("All controller lifecycle tests passed using mock USB and isolated profiles.")
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
        try expect(h.model.layers.count == 1, "Remove must keep one editable layer")
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
        h.bus.attach(101); pump(0.08)
        try expect(h.bus.recorded(101).isEmpty && !h.model.connected, "No profile must not auto-open USB")
        h.model.connect()
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
