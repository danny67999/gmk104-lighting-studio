import SwiftUI
import AppKit

/// Environment boundaries keep controller state transitions testable without opening
/// HID devices, requesting OS permissions, or touching the user's saved profiles.
struct ControllerEnvironment {
    var layoutURL: URL?
    var defaultMappingURL: URL?
    var mappingURL: URL
    var profileURL: URL
    var openTransport: () throws -> (transport: ReportTransport, registryID: UInt64?)
    var attachments: () -> (count: Int, registryID: UInt64?)
    var makeLightingInputs: (() -> LightingInputSource)?
    var inputMonitoringEnabled = true
    var mappingInputAllowed: () -> Bool = {
        NSApp.isActive && NSApp.keyWindow != nil && NSApp.keyWindow?.attachedSheet == nil &&
        NSApp.modalWindow == nil && RunLoop.current.currentMode != .eventTracking
    }
    var connectionInterval: TimeInterval = 1
    var animationInterval: TimeInterval? = nil
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    static var production: Self {
        Self(layoutURL: Bundle.main.url(forResource: "layout", withExtension: "json"),
             defaultMappingURL: Bundle.main.url(forResource: "default-led-map", withExtension: "json"),
             mappingURL: MappingFile.saveURL, profileURL: LightingProfile.url,
             openTransport: {
                 let transport = try HIDTransport()
                 return (transport, transport.registryEntryID)
             }, attachments: {
                 let matches = HIDTransport.candidates()
                 return (matches.count, matches.count == 1 ? try? HIDTransport.registryID(of: matches[0]) : nil)
             }, makeLightingInputs: { NativeLightingInputSource() })
    }
}

final class ControllerModel: ObservableObject {
    @Published var status = "Connect your GMK104 by USB to read its firmware and lighting state."
    @Published var connected = false
    @Published var busy = false
    @Published var state: RGBState?
    @Published var frame: [RGB]?
    @Published var brightness = 3
    @Published var effect = 0
    @Published var layers = [LightingLayer()]
    @Published var selectedLayerID: UUID?
    @Published var selectingLayerKeys = false
    @Published var playing = false
    @Published var restoreOnReconnect = true
    @Published var liveInputs = LightingInputs()
    private var lightingInputSource: LightingInputSource?
    private var inputGeneration = 0
    @Published var inputStatus = "Keyboard input is inactive"
    @Published var keyResponseEnabled = false
    @Published var indicatorNotice = ""
    @Published var measuredFPS = 0.0
    @Published var animationFPS = 60
    @Published private(set) var playingFPSLimit = 60
    @Published var lastPressedKey = "—"
    @Published var mappingMode = false {
        didSet {
            if mappingMode != oldValue {
                resetMappingSelection()
                if mappingMode { selectingLayerKeys = false; stopPlayback(savePausedState: false) }
                else { quickMapping = false; manualMapping = false }
            }
        }
    }
    @Published var quickMapping = false
    @Published var manualMapping = false {
        didSet { if manualMapping != oldValue { quickMapping = false; resetMappingSelection() } }
    }
    @Published var canUndoMappingReset = false
    @Published var mappingIndex = 1 {
        didSet { if mappingIndex != oldValue { resetMappingSelection() } }
    }
    @Published var illuminatedIndex: Int?
    @Published var selectedMappingKey = ""
    @Published var map: MappingFile?
    let keys: [KeyGeometry]
    private let environment: ControllerEnvironment
    private let queue = DispatchQueue(label: "GMK104.HID", qos: .userInitiated)
    private var client: RGBClient? // Only accessed on queue.
    private var clientAttachmentID: UInt64? // Only accessed on queue.
    private var keyboardEvents: KeyboardEvents?
    private var frameTimer: Timer?
    private var connectionTimer: Timer?
    private var pulses: [KeyPulse] = []
    private var activeLayers: [LightingLayer]?
    private var profile: LightingProfile?
    private var wantConnection = false
    private var connectionProbeInFlight = false
    private var frameInFlight = false
    private var generation = 0
    private var attachedID: UInt64?
    private var blockedID: UInt64?
    private var lastRendered: [RGB]?
    private var lastAudit = 0.0
    private var lastFrameFinished = 0.0
    private var now: TimeInterval { environment.clock() }

    init(environment: ControllerEnvironment = .production) {
        self.environment = environment
        do {
            guard let url = environment.layoutURL else {
                throw ControllerError.message("Keyboard layout resource is missing.")
            }
            keys = try JSONDecoder().decode([KeyGeometry].self, from: Data(contentsOf: url))
        } catch { keys = []; status = error.localizedDescription; return }
        do {
            guard let url = FileManager.default.fileExists(atPath: environment.mappingURL.path) ? environment.mappingURL :
                environment.defaultMappingURL else { throw ControllerError.message("Default keyboard mapping resource is missing.") }
            let loaded = try JSONDecoder().decode(MappingFile.self, from: Data(contentsOf: url))
            try loaded.validate(keys: keys); map = loaded
            profile = try LightingProfile.load(from: environment.profileURL)
            if let p = profile {
                let loadedLayers = p.studioLayers
                try LightingLayer.validate(loadedLayers, allowedKeyIDs: Set(keys.map(\.id)))
                layers = loadedLayers; selectedLayerID = layers.first?.id
                brightness = p.settings.brightness; effect = p.builtInEffect; animationFPS = p.frameRate ?? 60
                restoreOnReconnect = p.restoreOnReconnect
                wantConnection = p.restoreOnReconnect && p.resume
                if wantConnection { status = "Waiting for the keyboard to restore your saved lighting…" }
            }
        } catch { status = "Saved configuration could not be loaded: \(error.localizedDescription)" }
        canUndoMappingReset = FileManager.default.fileExists(atPath: mappingBackupURL.path)
        let timer = Timer(timeInterval: environment.connectionInterval, repeats: true) { [weak self] _ in self?.pollConnection() }
        connectionTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    static func color(_ c: RGB) -> Color { Color(red: Double(c.r)/255, green: Double(c.g)/255, blue: Double(c.b)/255) }
    private static func rgb(_ color: Color) -> RGB {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        func byte(_ v: CGFloat) -> UInt8 { UInt8(min(255, max(0, (v*255).rounded()))) }
        return RGB(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent))
    }
    var selectedLayer: LightingLayer {
        get { layers.first { $0.id == selectedLayerID } ?? layers.first ?? LightingLayer() }
        set {
            guard let index = layers.firstIndex(where: { $0.id == newValue.id }) else { return }
            layers[index] = newValue
        }
    }
    var settings: LightingSettings {
        get { selectedLayer.settings }
        set {
            var layer = selectedLayer
            if layer.name == layer.settings.effect.displayName { layer.name = newValue.effect.displayName }
            layer.settings = newValue; selectedLayer = layer
        }
    }
    var selectedColor: Color {
        get { Self.color(settings.color) }
        set { settings.color = Self.rgb(newValue) }
    }
    var rgb: RGB { settings.color }
    var mappedCount: Int { map?.mappings.filter(\.confirmed).count ?? 0 }
    var playingEffectName: String {
        let enabled = (activeLayers ?? layers).filter(\.enabled)
        return enabled.count == 1 ? enabled[0].settings.effect.displayName : "\(enabled.count) layers"
    }
    var hasLayerChanges: Bool {
        guard let profile, profile.mode == .studio else { return true }
        return layers != profile.studioLayers || brightness != profile.settings.brightness || animationFPS != (profile.frameRate ?? 60)
    }
    var hasReactiveLayers: Bool { (activeLayers ?? layers).contains { $0.enabled && $0.settings.effect.requiresKeyPresses } }
    var controlsLocked: Bool { busy || frameInFlight }

    func addLayer(_ effect: LightingEffect) {
        guard !busy && layers.count < LightingLayer.limit else { return }
        var selected = LightingSettings(effect: effect)
        selected.brightness = brightness
        let layer = LightingLayer(settings: selected)
        layers.insert(layer, at: 0); selectedLayerID = layer.id; selectingLayerKeys = false
    }
    func duplicateLayer() {
        guard !busy && layers.count < LightingLayer.limit,
              let index = layers.firstIndex(where: { $0.id == selectedLayer.id }) else { return }
        var duplicate = layers[index]; duplicate.id = UUID()
        duplicate.name = String(duplicate.name.prefix(73)) + " copy"
        layers.insert(duplicate, at: index); selectedLayerID = duplicate.id
    }
    func removeLayer() {
        guard !busy && layers.count > 1, let index = layers.firstIndex(where: { $0.id == selectedLayer.id }) else { return }
        layers.remove(at: index); selectedLayerID = layers[min(index, layers.count - 1)].id
        selectingLayerKeys = false
    }
    func moveLayer(_ offset: Int) {
        guard !busy, let index = layers.firstIndex(where: { $0.id == selectedLayer.id }), layers.indices.contains(index + offset) else { return }
        layers.swapAt(index, index + offset)
    }
    func setLayerKeys(_ ids: [String]?) {
        selectedLayer.keyIDs = ids.map { Array(Set($0).intersection(Set(keys.map(\.id)))).sorted() }
    }
    func toggleLayerKey(_ key: KeyGeometry) {
        var selected = Set(selectedLayer.keyIDs ?? keys.map(\.id))
        if selected.contains(key.id) { selected.remove(key.id) } else { selected.insert(key.id) }
        setLayerKeys(Array(selected))
    }
    func layerIncludes(_ key: KeyGeometry) -> Bool { selectedLayer.keyIDs?.contains(key.id) ?? true }

    func connect(automatic: Bool = false) {
        guard !busy && !connected else { return }
        wantConnection = true
        if !automatic { blockedID = nil }
        busy = true; status = "Reading custom firmware signature…"
        queue.async {
            self.client?.transport.close(); self.client = nil; self.clientAttachmentID = nil
            do {
                let opened = try self.environment.openTransport()
                let c = RGBClient(opened.transport); self.client = c; self.clientAttachmentID = opened.registryID
                let s = try c.read()
                if s.effect == 19 { _ = try c.readFrame() }
                let colors = s.effect == 19 ? c.shadow : nil
                let id = opened.registryID
                DispatchQueue.main.async {
                    self.connected = true; self.busy = false; self.state = s; self.frame = colors; self.attachedID = id
                    self.brightness = s.brightness; self.effect = min(18, s.effect)
                    self.status = "Connected • Custom firmware v0.2 verified"
                    self.startKeyboardInput()
                    if self.restoreOnReconnect && self.profile?.resume == true && !self.mappingMode { self.restoreProfile() }
                }
            } catch { self.failOnQueue(error) }
        }
    }
    private func failOnQueue(_ error: Error) {
        // A failed color check is not evidence of USB removal. Keep the existing
        // session only after its attachment and exact firmware still verify.
        if error is LightingVerificationError, let c = client, let id = clientAttachmentID {
            do {
                try c.transport.checkSingleDevice()
                let current = try c.read()
                DispatchQueue.main.async {
                    self.stopPlayback(savePausedState: false)
                    self.connected = true; self.attachedID = id; self.busy = false
                    self.state = current; self.frame = nil; self.resetMappingSelection()
                    self.status = "\(error.localizedDescription) USB is still connected. Try the lighting action again."
                }
                return
            } catch { /* Identity or transport also failed: close below. */ }
        }
        let failedID = clientAttachmentID
        client?.transport.close(); client = nil; clientAttachmentID = nil
        DispatchQueue.main.async {
            self.blockedID = failedID ?? self.attachedID
            self.stopPlayback(savePausedState: false)
            self.keyboardEvents?.stop(); self.keyboardEvents = nil
            self.keyResponseEnabled = false
            self.connected = false; self.busy = false; self.state = nil; self.frame = nil
            self.attachedID = nil; self.resetMappingSelection()
            self.status = "\(error.localizedDescription) Waiting for USB reconnection; click Connect to retry."
            self.inputStatus = "Keyboard disconnected"
        }
    }
    func disconnect() {
        wantConnection = false; stopPlayback(savePausedState: false)
        keyboardEvents?.stop(); keyboardEvents = nil
        keyResponseEnabled = false
        busy = true; connected = false; attachedID = nil
        queue.async {
            self.client?.transport.close(); self.client = nil; self.clientAttachmentID = nil
            DispatchQueue.main.async {
                self.busy = false; self.state = nil; self.frame = nil; self.resetMappingSelection()
                self.status = "Disconnected. Click Connect to use the keyboard again."
            }
        }
    }
    private func pollConnection() {
        guard wantConnection && !busy && !frameInFlight && !connectionProbeInFlight else { return }
        connectionProbeInFlight = true
        queue.async {
            let snapshot = self.environment.attachments()
            let id = snapshot.count == 1 ? snapshot.registryID : nil
            DispatchQueue.main.async {
                self.connectionProbeInFlight = false
                if self.connected {
                    if id != self.attachedID {
                        self.stopPlayback(savePausedState: false)
                        self.keyboardEvents?.stop(); self.keyboardEvents = nil
                        self.keyResponseEnabled = false
                        self.connected = false; self.attachedID = nil; self.state = nil; self.frame = nil
                        self.resetMappingSelection()
                        self.queue.async { self.client?.transport.close(); self.client = nil; self.clientAttachmentID = nil }
                        self.status = snapshot.count > 1 ? "Connect exactly one GMK104 keyboard." : "Keyboard unplugged. Your lighting profile will resume after reconnection."
                    }
                } else if let id, id != self.blockedID { self.connect(automatic: true) }
                else if id == nil { self.blockedID = nil }
            }
        }
    }
    private func startKeyboardInput() {
        keyboardEvents?.stop()
        keyResponseEnabled = false
        guard environment.inputMonitoringEnabled else { keyboardEvents = nil; return }
        let events = KeyboardEvents { [weak self] key in self?.keyPressed(key) }
        do {
            try events.start(registryID: attachedID)
            keyboardEvents = events; keyResponseEnabled = true; inputStatus = "Listening to GMK104 key presses"
        } catch {
            keyboardEvents = nil
            inputStatus = "\(error.localizedDescription) Preview and continuous effects still work."
        }
    }
    func enableKeyboardInput() {
        guard environment.inputMonitoringEnabled else { return }
        _ = KeyboardEvents.requestPermission()
        if connected { startKeyboardInput() }
        if KeyboardEvents.permission != .granted {
            inputStatus = "Allow GMK104 RGB Controller in System Settings → Privacy & Security → Input Monitoring, then click Enable key response again."
        }
    }
    func keyPressed(_ key: String) {
        guard connected else { return }
        if mappingMode {
            guard !busy && environment.mappingInputAllowed() else { return }
            if !manualMapping {
                if let geometry = keys.first(where: { $0.id == key }) { testMappingKey(geometry) }
                return
            }
            selectedMappingKey = key; completeQuickMapping(); return
        }
        guard playing else { return }
        lastPressedKey = key
        pulses.append(KeyPulse(keyID: key, time: now))
        if pulses.count > 48 { pulses.removeFirst(pulses.count - 48) }
    }
    func previewPulse() {
        let reactive = (activeLayers ?? []).filter { $0.enabled && $0.settings.effect.requiresKeyPresses && $0.opacity > 0 }
        let preferred = reactive.first { $0.id == selectedLayer.id } ?? reactive.first
        guard let layer = preferred,
              let key = map?.mappings.first(where: { $0.confirmed && $0.keyId == "KeyQ" && layer.acceptsTrigger($0.keyId) })?.keyId ??
                map?.mappings.first(where: { $0.confirmed && layer.acceptsTrigger($0.keyId) })?.keyId else {
            status = "Choose at least one mapped trigger key in an active layer that responds to key presses."; return
        }
        keyPressed(key)
    }
    func startStudio() {
        guard !mappingMode else { status = "Leave key mapping before starting a lighting effect."; return }
        guard connected && !busy else { return }
        do {
            try LightingLayer.validate(layers, allowedKeyIDs: Set(keys.map(\.id)))
            try require((0...4).contains(brightness), "Brightness must be 0–4.")
            try require([15, 30, 60, 90, 120].contains(animationFPS), "Choose a valid animation FPS limit.")
        } catch { status = error.localizedDescription; return }
        guard mappedCount > 0 || !layers.contains(where: { $0.enabled && ($0.settings.effect.requiresMapping || $0.keyIDs != nil) }) else {
            status = "Map at least one key before using spatial effects or selected keys."; return
        }
        stopPlayback(savePausedState: false)
        selectingLayerKeys = false
        applyStudio(layers, brightness: brightness, frameRate: animationFPS, save: true)
    }
    private func applyStudio(_ selected: [LightingLayer], brightness: Int, frameRate: Int, save: Bool, explicitResume: Bool = false) {
        guard connected && !busy, let map else { return }
        let colors = LayerRenderer.frame(layers: selected, keys: keys, mapping: map, pulses: [], time: now)
        run("Start lighting layers", operation: { c in
            // Write visible RGB first, then apply an explicitly selected zero brightness.
            try c.brightness(max(1, brightness))
            try c.setFrame(colors)
            if brightness == 0 { try c.brightness(0) }
        }, success: {
            var saved = true
            if save {
                var summary = selected.first?.settings ?? LightingSettings(); summary.brightness = brightness
                self.profile = LightingProfile(mode: .studio, settings: summary, restoreOnReconnect: self.restoreOnReconnect, layers: selected, frameRate: frameRate)
                saved = self.saveProfile()
            } else if explicitResume {
                self.profile?.resume = true
                saved = self.saveProfile()
            }
            self.playingFPSLimit = frameRate
            self.activeLayers = selected; self.lastRendered = colors; self.pulses = []
            self.playing = brightness > 0; self.generation += 1; self.lastAudit = self.now
            if self.playing {
                self.startLightingInputs()
                let timer = Timer(timeInterval: self.environment.animationInterval ?? 1.0 / Double(frameRate), repeats: true) { [weak self] _ in self?.animationTick() }
                self.frameTimer = timer; RunLoop.main.add(timer, forMode: .common)
            }
            if saved {
                self.status = brightness == 0 ? "Layers saved with brightness off." : "\(self.playingEffectName) running • Layers saved on this Mac"
            }
        })
    }
    private func startLightingInputs() {
        inputGeneration += 1
        lightingInputSource?.stop(); lightingInputSource = nil; liveInputs = LightingInputs()
        guard playing, let activeLayers else { return }
        let visible = activeLayers.filter { $0.enabled && $0.opacity > 0 && $0.settings.intensity > 0 && $0.keyIDs?.isEmpty != true }
        let music = visible.contains { $0.settings.effect == .adaptiveMusic }
        let temperature = visible.contains { $0.settings.effect == .cpuTemperature }
        guard music || temperature, let source = environment.makeLightingInputs?() else { return }
        lightingInputSource = source
        let token = inputGeneration
        source.start(music: music, temperature: temperature) { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self, self.playing, token == self.inputGeneration else { return }
                self.liveInputs = snapshot
            }
        }
    }
    func retryAudio() { if playing { startLightingInputs() } }
    func openAudioSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    func stopPlayback(savePausedState: Bool = true) {
        generation += 1; playing = false; frameTimer?.invalidate(); frameTimer = nil; pulses = []
        activeLayers = nil; measuredFPS = 0
        inputGeneration += 1; lightingInputSource?.stop(); lightingInputSource = nil; liveInputs = LightingInputs()
        if savePausedState, profile?.mode == .studio {
            profile?.resume = false; saveProfile()
            status = "Effect paused. The last lighting frame remains on the keyboard."
            if connected && !busy {
                queue.async {
                    do { if let c = self.client { _ = try c.readFrame() } }
                    catch { self.failOnQueue(error) }
                }
            }
        }
    }
    private func animationTick() {
        guard playing && connected && !busy && !frameInFlight, let selected = activeLayers, let map else { return }
        pulses.removeAll { now - $0.time > 20 }
        let colors = LayerRenderer.frame(layers: selected, keys: keys, mapping: map, pulses: pulses, time: now, inputs: liveInputs)
        guard colors != lastRendered else { return }
        frameInFlight = true
        let token = generation; let full = now - lastAudit > 2; let started = now
        queue.async {
            do {
                guard let c = self.client else { throw ControllerError.message("Keyboard disconnected.") }
                let s = try c.setAnimationFrame(colors, fullVerification: full)
                let overrides = c.indicatorOverrides
                var displayed = colors
                for index in overrides { displayed[index] = RGB(r: 255, g: 255, b: 255) }
                DispatchQueue.main.async {
                    self.frameInFlight = false
                    guard token == self.generation else { return }
                    self.state = s; self.frame = displayed; self.lastRendered = colors
                    self.updateIndicatorNotice(overrides)
                    self.measuredFPS = 1.0 / max(0.001, self.now - max(self.lastFrameFinished, started - 1.0 / Double(self.playingFPSLimit)))
                    self.lastFrameFinished = self.now
                    if full { self.lastAudit = self.now }
                }
            } catch {
                DispatchQueue.main.async { self.frameInFlight = false }
                self.failOnQueue(error)
            }
        }
    }
    func saveRestorePreference() { profile?.restoreOnReconnect = restoreOnReconnect; saveProfile() }
    @discardableResult private func saveProfile() -> Bool {
        do { try profile?.save(to: environment.profileURL); return true }
        catch { status = "The lighting profile could not be saved: \(error.localizedDescription)"; return false }
    }
    func restoreProfile(explicitResume: Bool = false) {
        guard !mappingMode else { status = "Leave key mapping before restoring a lighting effect."; return }
        guard let p = profile else { return }
        if p.mode == .studio { applyStudio(p.studioLayers, brightness: p.settings.brightness, frameRate: p.frameRate ?? 60, save: false, explicitResume: explicitResume); return }
        run("Restore saved lighting", operation: { c in
            if p.mode == .builtIn { try c.brightness(p.settings.brightness); try c.effect(p.builtInEffect) }
            else if let frame = p.colors {
                try c.brightness(max(1, p.settings.brightness)); try c.setFrame(frame)
                if p.settings.brightness == 0 { try c.brightness(0) }
            }
        }, success: {
            if explicitResume { self.profile?.resume = true; self.saveProfile() }
        })
    }
    func resumeSavedLighting() {
        guard !mappingMode, !busy, connected else { return }
        restoreProfile(explicitResume: true)
    }
    func run(_ label: String, operation: @escaping (RGBClient) throws -> Void, success: (() -> Void)? = nil) {
        guard connected && !busy else { return }
        busy = true; status = "\(label)…"
        queue.async {
            do {
                guard let c = self.client else { throw ControllerError.message("Connect the keyboard first.") }
                try operation(c)
                let s = try c.read(); let colors = s.effect == 19 ? c.shadow : nil
                let overrides = c.indicatorOverrides
                DispatchQueue.main.async {
                    self.state = s; self.frame = colors; self.busy = false
                    self.brightness = s.brightness; self.effect = min(18, s.effect)
                    self.updateIndicatorNotice(overrides)
                    self.status = "\(label) • Readback verified"; success?()
                }
            } catch { self.failOnQueue(error) }
        }
    }
    private func updateIndicatorNotice(_ indices: Set<Int>) {
        indicatorNotice = indices.isEmpty ? "" : "The keyboard keeps its active status lights white. Other keys still follow your effect."
    }
    func refresh() {
        if playing { startKeyboardInput(); status = "Playback active • \(inputStatus)"; return }
        run("Refresh") { c in if try c.read().effect == 19 { _ = try c.readFrame() } }
        startKeyboardInput()
    }
    private func rememberCurrentFrame() {
        guard let frame, let s = state else { return }
        var selected = settings; selected.color = rgb; selected.brightness = s.brightness
        profile = LightingProfile(mode: .frame, settings: selected, colors: frame, restoreOnReconnect: restoreOnReconnect, layers: layers)
        saveProfile()
    }
    func setAll() {
        stopPlayback(savePausedState: false)
        let color = rgb
        run("Set all keys", operation: { try $0.setFrame(Array(repeating: color, count: 104)) }, success: { self.rememberCurrentFrame() })
    }
    func clear() {
        stopPlayback(savePausedState: false)
        run("Clear", operation: { try $0.clear() }, success: { self.rememberCurrentFrame() })
    }
    func applyBrightness() {
        let value = brightness
        if playing { settings.brightness = value; startStudio(); return }
        run("Brightness", operation: { try $0.brightness(value) }, success: {
            self.profile?.settings.brightness = value; self.saveProfile()
        })
    }
    func playBuiltIn() {
        stopPlayback(savePausedState: false)
        let value = effect
        run("Built-in effect", operation: { try $0.effect(value) }, success: {
            var selected = self.settings; selected.brightness = self.brightness
            self.profile = LightingProfile(mode: .builtIn, settings: selected, builtInEffect: value, restoreOnReconnect: self.restoreOnReconnect, layers: self.layers)
            self.saveProfile()
        })
    }
    func identify() {
        let index = mappingIndex; resetMappingSelection()
        run("Identify LED \(index)", operation: { c in
            var colors = Array(repeating: RGB.black, count: 104); colors[index] = RGB(r: 0, g: 80, b: 0)
            try c.setFrame(colors)
        }, success: {
            self.illuminatedIndex = index
            if self.manualMapping {
                self.status = self.quickMapping ? "LED \(index) is lit. Press its key to save and advance." : "LED \(index) is lit. Select its key, then save the correction."
            } else {
                let label = self.map?.mappings.first { $0.ledIndex == index }?.keyId ?? "unassigned key"
                self.selectedMappingKey = label
                self.status = "Testing \(label) • LED \(index). Click another key to test it."
            }
        })
    }
    func testMappingKey(_ key: KeyGeometry) {
        guard mappingMode && !busy else { return }
        guard let index = map?.mappings.first(where: { $0.keyId == key.id && $0.confirmed })?.ledIndex else {
            status = "Apply the GMK104 row layout to map all 104 keys first."; return
        }
        mappingIndex = index; identify()
    }
    func stepMappingTest(_ offset: Int) {
        guard !busy else { return }
        mappingIndex = min(103, max(0, mappingIndex + offset)); identify()
    }
    var isRowMapping: Bool {
        guard let current = map, let preset = try? MappingFile.rowOrder(keys: keys) else { return false }
        return preset.mappings.allSatisfy { expected in
            current.mappings.contains { $0.keyId == expected.keyId && $0.ledIndex == expected.ledIndex && $0.confirmed }
        }
    }
    func applyRowMapping() {
        guard mappingMode && !busy, let current = map else { return }
        do {
            let preset = try MappingFile.rowOrder(keys: keys)
            try backupMapping(current)
            try saveMap(preset); map = preset; manualMapping = false; quickMapping = false
            mappingIndex = 0; resetMappingSelection()
            status = "All 104 keys are mapped: Escape is 0, then left to right across each row. Click any key to test it."
        } catch { status = "Row layout was not saved: \(error.localizedDescription)" }
    }
    func resetMappingSelection() { illuminatedIndex = nil; selectedMappingKey = "" }
    var canSaveMapping: Bool {
        connected && !busy && mappingMode && manualMapping && illuminatedIndex == mappingIndex &&
        keys.contains { $0.id == selectedMappingKey } && map != nil
    }
    @discardableResult func saveMapping() -> Bool {
        guard canSaveMapping, let lit = illuminatedIndex, var updated = map,
              let key = keys.first(where: { $0.id == selectedMappingKey }) else { return false }
        updated.assign(key: key.id, index: lit)
        do {
            try saveMap(updated); map = updated
            status = "Saved LED \(lit) → \(key.label.replacingOccurrences(of: "\n", with: " ")). Choose Next unmapped LED when ready."
            return true
        } catch { status = "Mapping was not saved: \(error.localizedDescription)"; return false }
    }
    private func completeQuickMapping() {
        guard mappingMode && quickMapping && !busy && illuminatedIndex == mappingIndex else { return }
        if saveMapping() { nextMappingLED() }
    }
    private var mappingBackupURL: URL {
        environment.mappingURL.deletingLastPathComponent().appendingPathComponent("led-map-backup.json")
    }
    private func backupMapping(_ current: MappingFile) throws {
        if FileManager.default.fileExists(atPath: mappingBackupURL.path) {
            let archive = mappingBackupURL.deletingLastPathComponent().appendingPathComponent("led-map-backup-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: mappingBackupURL, to: archive)
        }
        try saveMap(current, to: mappingBackupURL)
        canUndoMappingReset = true
    }
    func resetMapping() {
        guard mappingMode && !busy, let current = map else { return }
        do {
            guard let url = environment.defaultMappingURL else { throw ControllerError.message("Default keyboard mapping resource is missing.") }
            let initial = try JSONDecoder().decode(MappingFile.self, from: Data(contentsOf: url))
            try initial.validate(keys: keys)
            // Preserve the current mapping before replacing its file. Neither action sends USB commands.
            try backupMapping(current)
            try saveMap(initial)
            map = initial; quickMapping = false; resetMappingSelection()
            status = "Mapping reset to the supplied defaults. Use Undo reset to recover your previous mapping."
        } catch { status = "Mapping was not reset: \(error.localizedDescription)" }
    }
    func undoMappingReset() {
        guard mappingMode && !busy && canUndoMappingReset else { return }
        do {
            let previous = try JSONDecoder().decode(MappingFile.self, from: Data(contentsOf: mappingBackupURL))
            try saveMap(previous)
            map = previous; quickMapping = false; resetMappingSelection()
            status = "Your previous LED mapping was restored."
        } catch { status = "Previous mapping could not be restored: \(error.localizedDescription)" }
    }
    func nextMappingLED() {
        let assigned = Set(map?.mappings.filter(\.confirmed).compactMap(\.ledIndex) ?? [])
        guard let next = ((mappingIndex + 1)..<104).first(where: { !assigned.contains($0) }) ??
                (0..<104).first(where: { !assigned.contains($0) }) else {
            status = "All 104 LEDs have a saved mapping."; return
        }
        mappingIndex = next; identify()
    }
    func click(_ key: KeyGeometry) {
        if mappingMode {
            guard !busy else { return }
            if !manualMapping { testMappingKey(key); return }
            selectedMappingKey = key.id
            status = illuminatedIndex == mappingIndex ? "Selected \(key.id) for LED \(mappingIndex). Click Save mapping." : "Light the LED first, then select its key and save."
            completeQuickMapping()
        } else if selectingLayerKeys { toggleLayerKey(key) }
        else if playing { keyPressed(key.id) }
        else if let mapping = map?.mappings.first(where: { $0.keyId == key.id }), mapping.confirmed, let index = mapping.ledIndex {
            let color = rgb
            run("Set \(key.id)", operation: { try $0.setLED(index, color: color) }, success: { self.rememberCurrentFrame() })
        } else { status = "This key’s LED is unconfirmed. Use Mapping mode to identify it first." }
    }
    func importMap() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let updated = try JSONDecoder().decode(MappingFile.self, from: Data(contentsOf: url))
            try updated.validate(keys: keys); try saveMap(updated); map = updated; resetMappingSelection()
            status = "Imported and saved LED mapping."
        } catch { status = "Mapping import failed: \(error.localizedDescription)" }
    }
    func exportMap() {
        guard let map else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "led-map.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; try e.encode(map).write(to: url, options: .atomic); status = "Exported LED mapping." }
        catch { status = error.localizedDescription }
    }
    private func saveMap(_ updated: MappingFile, to target: URL? = nil) throws {
        try updated.validate(keys: keys)
        let url = target ?? environment.mappingURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updated).write(to: url, options: .atomic)
    }
}
