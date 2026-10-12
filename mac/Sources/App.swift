import SwiftUI
import AppKit

private extension LightingEffect {
    var symbol: String {
        switch self {
        case .ripple: return "dot.radiowaves.left.and.right"
        case .rainbowRipple: return "rainbow"
        case .reactive: return "sparkles"
        case .wave: return "water.waves"
        case .breathing: return "lungs"
        case .spectrum: return "circle.lefthalf.filled"
        case .staticColor: return "lightbulb"
        case .adaptiveMusic: return "waveform"
        case .cpuTemperature: return "thermometer.medium"
        case .keyHold: return "hand.point.up.left.fill"
        case .starlight: return "sparkle"
        case .rainbowStarlight: return "sparkles"
        case .fire: return "flame.fill"
        case .colorWheel: return "circle.hexagongrid.fill"
        case .scanner: return "line.3.horizontal"
        case .comet: return "sparkle"
        case .rain: return "cloud.rain.fill"
        case .aurora: return "moon.stars.fill"
        case .keyToggle: return "switch.2"
        case .rainbowReactive: return "rainbow"
        case .splash: return "drop.fill"
        case .crossRipple: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rowWave: return "arrow.left.and.right"
        case .columnWave: return "arrow.up.and.down"
        case .matrixRain, .spacedMatrixRain: return "text.line.first.and.arrowtriangle.forward"
        case .matrixKeyRain: return "cloud.rain.fill"
        }
    }
    var detail: String {
        switch self {
        case .ripple: return "A ring of light spreads from each key you press."
        case .rainbowRipple: return "A rainbow ring expands from each trigger key. Overlapping ripples blend their colors."
        case .reactive: return "Pressed keys light up, then fade away."
        case .wave: return "A moving rainbow crosses the mapped keyboard."
        case .breathing: return "This layer’s keys slowly brighten and dim."
        case .spectrum: return "This layer’s keys drift through the color spectrum."
        case .staticColor: return "One steady color across this layer’s keys."
        case .adaptiveMusic: return "Bass, mids and treble animate the keyboard with automatic volume adaptation. Audio stays on this Mac."
        case .cpuTemperature: return "Colors follow the hottest readable CPU sensor, from blue through green to red. Unavailable readings leave this layer transparent."
        case .keyHold: return "A key stays your chosen color for exactly as long as you hold it. Let go and the layer clears."
        case .starlight: return "Individual keys twinkle in your chosen color."
        case .rainbowStarlight: return "Random keys twinkle in changing rainbow colors."
        case .fire: return "Warm red, orange and yellow flames flicker across the keys."
        case .colorWheel: return "Rainbow colors rotate around the center of the keyboard."
        case .scanner: return "A bright bar sweeps from side to side in your chosen color."
        case .comet: return "A bright head and fading tail cross the keyboard."
        case .rain: return "Drops of your chosen color fall down the keyboard."
        case .aurora: return "Soft green and blue bands drift across the keyboard."
        case .keyToggle: return "Press once to switch a key on in your chosen color. Release it, then press again to switch it off. Holding never repeats the toggle."
        case .rainbowReactive: return "Each press flashes a changing rainbow color, then fades. Speed controls the fade."
        case .splash: return "A filled circle of light grows from each pressed key, reaches the edge, then fades."
        case .crossRipple: return "Light travels horizontally and vertically from each pressed key in a cross."
        case .rowWave: return "Each press sends two vertical bands left and right across the keyboard."
        case .columnWave: return "Each press sends two horizontal bands up and down across the keyboard."
        case .spacedMatrixRain: return "White heads and fading colored trails fall through fixed key columns. Every other column stays dark. Color and speed are adjustable. Native playback needs firmware v1.7."
        case .matrixKeyRain: return "Each selected key sends a falling trail down its fixed column, starting at the top. Every column can respond. Enable Affect all keys to let selected triggers light the rest of their columns. Native playback needs firmware v1.7."
        case .matrixRain: return "White heads lead colored fading trails and moving dark spaces, like the supplied video rotated vertically. Staggered columns loop from top to bottom. Speed controls the motion. Native playback requires firmware v1.6."
        }
    }
}
enum StudioPage: String, CaseIterable, Identifiable {
    case allEffects = "All Effects", automatic = "Automatic", reactive = "On Key Press", myLighting = "My Lighting", keyboard = "Keyboard"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .allEffects: return "square.grid.2x2"
        case .automatic: return "sparkles"
        case .reactive: return "hand.tap"
        case .myLighting: return "square.stack.3d.up"
        case .keyboard: return "keyboard"
        }
    }
}
final class StudioViewState: ObservableObject {
    @Published var page: StudioPage
    @Published var search = ""
    @Published var showingSettings = false
    @Published var showingMacPlayback = false
    @Published var showingAdvancedLayer = false
    @Published var showingEffect = false
    @Published var pendingSettings = LightingSettings()
    init(page: StudioPage) { self.page = page }
}
struct ControllerView: View {
    @ObservedObject var model: ControllerModel
    @StateObject private var interface: StudioViewState
    @Environment(\.colorScheme) private var colorScheme
    init(model: ControllerModel, initialPage: StudioPage = .myLighting) {
        _model = ObservedObject(wrappedValue: model)
        _interface = StateObject(wrappedValue: StudioViewState(page: initialPage))
    }
    #if GMK104_UI_SNAPSHOT
    init(model:ControllerModel,viewState:StudioViewState) {
        _model = ObservedObject(wrappedValue:model)
        _interface = StateObject(wrappedValue:viewState)
    }
    #endif
    var body: some View {
        HSplitView {
            sidebar.frame(minWidth:200,idealWidth:210,maxWidth:250,maxHeight:.infinity)
            VStack(spacing:0) {
                HStack(spacing:12) {
                    Text(model.mappingMode ? "Key Mapping" : [.allEffects,.automatic,.reactive].contains(interface.page) ? "Effects" : interface.page.rawValue).font(.title2.weight(.semibold))
                    Spacer()
                    if model.mappingMode {
                        Button("Done mapping") { model.mappingMode = false }.disabled(model.busy)
                    } else {
                        if interface.page != .myLighting && interface.page != .keyboard {
                            TextField("Search effects",text:$interface.search).textFieldStyle(.roundedBorder).frame(width:200)
                        }
                        profileMenu
                    }
                    Button(model.connected ? "Disconnect" : "Connect") { model.connected ? model.disconnect() : model.connect() }.disabled(model.busy)
                }.padding(.horizontal,24).padding(.vertical,16).fixedSize(horizontal:false,vertical:true)
                Divider()
                Group {
                    if model.mappingMode {
                        ScrollView { VStack(alignment:.leading,spacing:20) { keyboard;mappingControls }.padding(28) }
                    } else if interface.page == .myLighting { myLighting }
                    else if interface.page == .keyboard { keyboardSettings }
                    else { effectGallery }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                Divider()
                if model.mappingMode {
                    Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth:.infinity,alignment:.leading).padding(16)
                } else { playbackBar.fixedSize(horizontal:false,vertical:true).layoutPriority(1) }
            }.frame(minWidth:720,maxWidth:.infinity,maxHeight:.infinity)
                .background(Color(nsColor:.windowBackgroundColor))
        }
        .frame(minWidth: 1080, idealWidth: 1220, minHeight: 670, idealHeight: 810)
        .onChange(of:model.openedProfileName) { _ in interface.page = .myLighting;model.selectingLayerKeys = !model.layers.isEmpty }
        .sheet(isPresented: $interface.showingEffect) { newEffectSheet }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshInputPermission(restartListener:true)
        }
        .sheet(isPresented:$interface.showingMacPlayback) { macPlaybackSheet }
        .confirmationDialog("Reset the key mapping?", isPresented: $model.confirmingMappingReset, titleVisibility: .visible) {
            Button("Reset mapping", role: .destructive) { model.resetMapping() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This restores all 104 assignments in row order, starting with Escape at LED 0. Your current map is backed up for Undo.") }
    }
    private var macPlaybackSheet: some View {
            VStack(alignment:.leading,spacing:18) {
                HStack {
                    Text("Mac Playback").font(.title2.weight(.semibold));Spacer()
                    sheetCloseButton("Close Mac Playback") { interface.showingMacPlayback = false }
                }.fixedSize(horizontal:false,vertical:true)
                ScrollView { macPlaybackCard }.frame(maxWidth:.infinity,maxHeight:.infinity)
                Divider()
                HStack { Spacer();Button("Close") { interface.showingMacPlayback = false }.keyboardShortcut(.defaultAction) }
                    .fixedSize(horizontal:false,vertical:true)
            }.padding(26).frame(width:600,height:480).background(Color(nsColor:.windowBackgroundColor))
    }
    #if GMK104_UI_SNAPSHOT
    func snapshotSheet(_ name:String) -> AnyView {
        AnyView(macPlaybackSheet)
    }
    #endif
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:5) {
                    sidebarRow(.myLighting)
                    sidebarRow(.allEffects)
                    sidebarRow(.keyboard)
                }.padding(.horizontal,12).padding(.vertical,18)
            }.frame(maxHeight:.infinity)
            Divider()
            VStack(alignment:.leading,spacing:10) {
                Label(model.connected ? "GMK104 · \(model.connectionName)" : "GMK104 · Offline",systemImage:"keyboard")
                    .font(.callout.weight(.medium))
                Button { interface.page = .keyboard } label: {
                    Label(model.inputPermissionLabel,systemImage:model.inputPermission == .granted ? "checkmark.shield.fill" : "hand.raised")
                        .font(.caption).foregroundStyle(model.inputPermission == .granted ? Color.green : Color.secondary)
                        .fixedSize(horizontal:false,vertical:true)
                }.buttonStyle(.plain).help("View keyboard access and Input Monitoring settings")
            }.padding(16).fixedSize(horizontal:false,vertical:true)
        }.background(.regularMaterial)
    }
    private func sidebarRow(_ page:StudioPage) -> some View {
        let selected = page == .allEffects ? [.allEffects,.automatic,.reactive].contains(interface.page) : interface.page == page
        return Button {
            if model.mappingMode && model.busy { return }
            model.mappingMode = false;interface.page = page;interface.search = ""
        } label: {
            Label(page == .allEffects ? "Effects" : page.rawValue,systemImage:page.symbol).font(.callout.weight(.medium))
                .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,10).padding(.vertical,10)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.clear,in:RoundedRectangle(cornerRadius:7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("navigation-"+page.id)
    }
    private func sheetCloseButton(_ label:String,action:@escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:"xmark").font(.system(size:12,weight:.semibold)).frame(width:24,height:24) }
            .buttonStyle(.borderless).background(.quaternary,in:Circle())
            .accessibilityLabel(label).help(label).keyboardShortcut(.cancelAction)
    }
    private var galleryEffects: [LightingEffect] {
        let featured: [LightingEffect] = [.spacedMatrixRain, .matrixKeyRain, .matrixRain, .rainbowRipple, .wave, .keyToggle, .fire, .crossRipple]
        return LightingEffect.allCases.filter {
            $0 != .adaptiveMusic && $0 != .cpuTemperature &&
            (interface.page != .automatic || !$0.requiresKeyPresses) &&
            (interface.page != .reactive || $0.requiresKeyPresses) &&
            (interface.search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(interface.search))
        }.sorted { (featured.firstIndex(of: $0) ?? 99) < (featured.firstIndex(of: $1) ?? 99) }
    }
    private var effectGallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Effects").font(.system(size:30,weight:.bold))
                    Text("Choose an effect, then add it to your lighting.").foregroundStyle(.secondary)
                    Picker("Effect category",selection:$interface.page) {
                        Text("All").tag(StudioPage.allEffects)
                        Text("Automatic").tag(StudioPage.automatic)
                        Text("On key press").tag(StudioPage.reactive)
                    }.pickerStyle(.segmented).frame(width:360).padding(.top,6)
                }
                if galleryEffects.isEmpty { Text("No effects match your search.").foregroundStyle(.secondary).padding(.vertical, 40) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 350), spacing: 18)], spacing: 18) {
                    ForEach(galleryEffects) { effect in effectCard(effect) }
                }
            }.padding(30)
        }
    }
    private func effectCard(_ effect: LightingEffect) -> some View {
        let settings = defaultSettings(effect)
        let tint = cardTint(effect)
        return Button {
            interface.pendingSettings = settings; interface.showingEffect = true
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: effect.symbol).font(.system(size: 21, weight: .medium))
                    Text(effect.displayName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                EffectKeyboardThumbnail(keys: model.keys, mapping: model.map, settings: settings)
                    .frame(height: 76).padding(8).background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Text(effect.requiresKeyPresses ? "On key press" : "Automatic").font(.caption)
                    Spacer()
                    Image(systemName: "plus.circle").font(.system(size: 15))
                }.opacity(0.85)
            }.foregroundStyle(.white).padding(18).frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [tint, tint.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }.buttonStyle(.plain).help("Preview \(effect.displayName)").accessibilityLabel("Preview \(effect.displayName)").disabled(model.busy)
    }
    private func defaultSettings(_ effect: LightingEffect) -> LightingSettings {
        LightingSettings(effect: effect, color: [.matrixRain, .spacedMatrixRain, .matrixKeyRain].contains(effect) ? RGB(r: 0, g: 255, b: 32) : RGB(r: 30, g: 195, b: 255))
    }
    private func cardTint(_ effect: LightingEffect) -> Color {
        switch effect {
        case .matrixRain, .spacedMatrixRain, .matrixKeyRain: return Color(red: 0.07, green: 0.52, blue: 0.28)
        case .fire: return Color(red: 0.88, green: 0.34, blue: 0.12)
        case .starlight, .rainbowStarlight, .aurora: return Color(red: 0.52, green: 0.36, blue: 0.78)
        case .ripple, .rainbowRipple, .splash, .crossRipple: return Color(red: 0.18, green: 0.52, blue: 0.88)
        case .wave, .spectrum, .colorWheel, .rainbowReactive: return Color(red: 0.75, green: 0.32, blue: 0.57)
        case .keyHold, .keyToggle, .reactive: return Color(red: 0.82, green: 0.55, blue: 0.14)
        default: return Color(red: 0.15, green: 0.57, blue: 0.63)
        }
    }
    private var newEffectSheet: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: interface.pendingSettings.effect.symbol).font(.title).foregroundStyle(cardTint(interface.pendingSettings.effect))
                Text(interface.pendingSettings.effect.displayName).font(.title.weight(.bold))
                Spacer()
                sheetCloseButton("Close effect preview") { interface.showingEffect = false }
            }
            EffectKeyboardThumbnail(keys: model.keys, mapping: model.map, settings: interface.pendingSettings)
                .frame(height: 210).padding(20).background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
            Text(interface.pendingSettings.effect.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Speed").frame(width: 60, alignment: .leading)
                Slider(value: $interface.pendingSettings.speed, in: 0.25...3, step: 0.05).accessibilityLabel("Effect speed")
                Text(String(format: "%.2f×", interface.pendingSettings.speed)).monospacedDigit().frame(width: 55)
            }.disabled(!interface.pendingSettings.effect.hasAdjustableSpeed)
            ColorPicker("Color", selection: Binding(get: { ControllerModel.color(interface.pendingSettings.color) }, set: { color in
                let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
                interface.pendingSettings.color = RGB(r: UInt8(min(255, max(0, (c.redComponent * 255).rounded()))), g: UInt8(min(255, max(0, (c.greenComponent * 255).rounded()))), b: UInt8(min(255, max(0, (c.blueComponent * 255).rounded()))))
            }), supportsOpacity: false).disabled(!interface.pendingSettings.effect.usesSelectedColor)
            Divider()
            HStack {
                Text("Adds a layer to My Lighting.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { interface.showingEffect = false }.keyboardShortcut(.cancelAction)
                Button("Add to My Lighting") {
                    model.addLayer(interface.pendingSettings.effect); model.settings = interface.pendingSettings
                    interface.showingEffect = false; interface.page = .myLighting
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.layers.count >= LightingLayer.limit || model.busy)
            }
            if model.layers.count >= LightingLayer.limit { Text("Your profile has 16 layers. Remove one in My Lighting to add another.").font(.caption).foregroundStyle(.orange) }
        }.padding(30).frame(width: 760).background(Color(nsColor:.windowBackgroundColor))
    }
    private var myLighting: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                Text("My Lighting").font(.system(size:30,weight:.bold));Spacer()
                Menu("Presets") {
                        ForEach(LightingPreset.allCases) { preset in
                            Button(preset.rawValue) { model.applyPreset(preset) }.help(preset.detail)
                        }
                    }.fixedSize().disabled(model.busy).help("Load a layer combination. Undo restores your current layers.")
                Menu {
                    Section("Automatic") {
                        ForEach(LightingEffect.allCases.filter { !$0.requiresKeyPresses && $0 != .adaptiveMusic && $0 != .cpuTemperature }) { effect in
                            Button { addToWorkspace(effect) } label: { Label(effect.displayName,systemImage:effect.symbol) }
                        }
                    }
                    Section("On key press") {
                        ForEach(LightingEffect.allCases.filter(\.requiresKeyPresses)) { effect in
                            Button { addToWorkspace(effect) } label: { Label(effect.displayName,systemImage:effect.symbol) }
                        }
                    }
                } label: { Label("Add Effect",systemImage:"plus") }
                    .disabled(model.busy || model.layers.count >= LightingLayer.limit)
            }.fixedSize(horizontal:false,vertical:true)
            HStack(alignment:.top,spacing:20) {
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        HStack {
                            Text(model.settings.effect.requiresKeyPresses ? "Trigger keys" : "Selected keys").font(.callout.weight(.medium))
                            Text(model.selectedLayer.keyIDs.map { "\($0.count)" } ?? "All").font(.caption).foregroundStyle(.secondary)
                            Spacer();keySelectionPresets
                        }
                        KeyboardDiagram(model:model,selectionTool:.automatic,canvasHeight:220)
                        Text("Click or drag across keys. Drag from empty space for a box. ⌘-click tests a key.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Layers · \(model.layers.count)").font(.headline)
                            Spacer()
                            if model.canUndoWorkspace { Button("Undo") { model.undoWorkspace() }.disabled(model.busy) }
                            Button(role:.destructive) { model.removeAllEffects() } label: {
                                Label("Remove All Effects",systemImage:"trash")
                            }.disabled(model.busy || model.layers.isEmpty)
                        }.padding(.top,6)
                        if model.layers.isEmpty {
                            Text("No effects. Add an effect or choose a preset to start.")
                                .foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,18)
                        }
                        ForEach(model.layers) { layer in profileLayerCard(layer) }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                VStack(alignment:.leading,spacing:16) {
                    Text("Effect settings").font(.headline)
                    if model.layers.isEmpty {
                        Text("Select a layer after adding an effect or preset.").foregroundStyle(.secondary)
                        Spacer()
                    } else { ScrollView { layerEditor } }
                }.frame(width:300).frame(maxHeight:.infinity,alignment:.topLeading).padding(16)
                    .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:10))
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.padding(24)
            .onAppear { model.selectingLayerKeys = !model.layers.isEmpty }
            .onDisappear { model.selectingLayerKeys = false }
    }
    private func addToWorkspace(_ effect:LightingEffect) {
        model.addLayer(effect);model.settings = defaultSettings(effect);model.selectingLayerKeys = true
    }
    private var keySelectionPresets: some View {
        Menu("Select") {
            Button("All keys") { model.setLayerKeys(nil) }
            Button("No keys") { model.setLayerKeys([]) }
            Button("WASD") { model.setLayerKeys(["KeyW","KeyA","KeyS","KeyD"]) }
            Button("Arrow keys") { model.setLayerKeys(["ArrowUp","ArrowDown","ArrowLeft","ArrowRight"]) }
            Button("Number pad") { model.setLayerKeys(model.keys.filter { $0.id.hasPrefix("Numpad") }.map(\.id)) }
        }.fixedSize().disabled(model.busy || model.layers.isEmpty)
    }
    private func profileLayerCard(_ layer:LightingLayer) -> some View {
        let selected=model.selectedLayer.id == layer.id
        return HStack(spacing:8) {
            Button {
                model.selectedLayerID=layer.id;model.selectingLayerKeys = true
            } label: {
                HStack(spacing:10) {
                    Image(systemName:layer.settings.effect.symbol).foregroundStyle(cardTint(layer.settings.effect)).frame(width:22)
                    VStack(alignment:.leading,spacing:4) {
                        Text(layer.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text(layer.settings.effect.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Edit \(layer.name)").help("Edit this layer here")
            Toggle("Enable \(layer.name)",isOn:Binding(get:{ model.layers.first { $0.id == layer.id }?.enabled ?? false },set:{ value in
                if let index=model.layers.firstIndex(where:{ $0.id == layer.id }) { model.layers[index].enabled=value }
            })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Menu {
                Button("Duplicate") { model.selectedLayerID=layer.id;model.duplicateLayer() }.disabled(model.layers.count >= LightingLayer.limit)
                Button("Move up") { model.selectedLayerID=layer.id;model.moveLayer(-1) }.disabled(model.layers.first?.id == layer.id)
                Button("Move down") { model.selectedLayerID=layer.id;model.moveLayer(1) }.disabled(model.layers.last?.id == layer.id)
                Divider()
                Button("Remove",role:.destructive) { model.selectedLayerID=layer.id;model.removeLayer() }.disabled(model.layers.isEmpty)
            } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("Layer actions")
        }.padding(12).background(selected ? Color.accentColor.opacity(0.1) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(selected ? Color.accentColor.opacity(0.65) : Color(nsColor:.separatorColor).opacity(0.35)))
            .disabled(model.busy)
    }
    private var profileMenu: some View {
        Menu {
            Button("Open profile…") { model.chooseProfileFile(); interface.page = .myLighting }
            Divider()
            Button("Save on this Mac") { model.saveDraftToMac(); interface.page = .myLighting }
            Button("Export profile…") { model.saveProfileFileAs() }
            Button("Show saved profile in Finder") { model.showSavedProfileInFinder() }.disabled(!model.savedProfileExists)
        } label: { Label("Profiles", systemImage: "doc") }
            .disabled(model.busy).help("Open, save or export a lighting profile")
    }
    private var playbackBar: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack(spacing:10) {
                Label(model.onboardPreviewActive ? "Playing on keyboard" : model.playing ? "Playing from Mac" : model.connected ? "Ready" : "Offline",
                      systemImage:model.onboardPreviewActive ? "keyboard" : "play.circle")
                    .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { model.onboardPreviewActive ? model.stopOnboardPreview() : model.stopPlayback() }
                    .disabled(model.busy || (!model.onboardPreviewActive && !model.playing))
                Button("Play on keyboard") { model.previewOnKeyboard() }
                    .disabled(model.controlsLocked || !model.onboardPreviewAvailable || !model.onboardCompatibleDraft || model.mappedCount != 104)
                    .help("Plays this layout until the keyboard powers off")
                Button("Save to keyboard") { model.saveOnKeyboard() }.buttonStyle(.borderedProminent)
                    .disabled(model.controlsLocked || !model.onboardPersistentAvailable || !model.onboardCompatibleDraft || model.mappedCount != 104)
                    .help("Saves this layout so it returns after power-off")
            }
            HStack {
                Text("Play tries the layout. Save keeps it after power-off.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if let progress = model.onboardPreviewProgress { ProgressView(value:progress) }
            if let notice = keyboardActionNotice { Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled).help(model.status)
                .frame(maxWidth:.infinity,alignment:.leading)
        }.padding(.horizontal,24).padding(.vertical,12)
    }
    private var keyboardActionNotice: String? {
        if !model.connected { return "Connect the keyboard to play or save this layout." }
        if model.connectionName != "USB" { return "Use a USB data cable to send layouts to the keyboard. Mac playback works over your wireless connection." }
        if !model.onboardPreviewAvailable && !model.busy { return model.onboardPreviewStatus }
        if let message = model.onboardCompatibilityMessage { return message }
        if model.mappedCount != 104 { return "Confirm all 104 keys in Keyboard → Key Mapping before sending this layout." }
        if !model.onboardPersistentAvailable && !model.busy { return "Temporary playback is available. This firmware does not support saving after power-off." }
        return nil
    }
    private var keyboardSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard").font(.system(size: 30, weight: .bold))
            Form {
                Section("Keyboard access") {
                    Label(model.inputPermissionLabel,systemImage:model.inputPermission == .granted ? "checkmark.shield.fill" : "hand.raised")
                        .foregroundStyle(model.inputPermission == .granted ? Color.green : Color.primary)
                    Text(model.keyResponseEnabled ? "Listening to this keyboard" : model.inputStatus).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        keyResponseButton
                        Button("Open Input Monitoring") { model.openInputMonitoringSettings() }
                        Button("Refresh access") { model.refreshInputPermission(restartListener:true) }.disabled(model.busy)
                    }
                    Text("Input Monitoring is used for Mac playback and mapping. Effects saved on the keyboard read key presses themselves.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Connection & layout") {
                    Button("Key Mapping…") { model.mappingMode = true }.disabled(model.busy)
                    Text("\(model.mappedCount) of 104 keys mapped").font(.caption).foregroundStyle(.secondary)
                    Picker("Brightness", selection: $model.brightness) {
                        ForEach(0...4, id: \.self) { Text($0 == 0 ? "Off" : "\($0) of 4").tag($0) }
                    }
                    Button("Apply brightness") { model.applyBrightness() }.disabled(!model.connected || model.busy)
                    Picker("Wireless sleep", selection: $model.sleepAfterSeconds) {
                        ForEach(KeyboardPreferences.choices, id: \.self) { Text(KeyboardPreferences.label($0)).tag($0) }
                    }
                    Button("Apply sleep time") { model.applySleepTime() }
                        .disabled(!model.connected || !model.sleepSupported || model.busy)
                    Text(model.sleepStatus).font(.caption).foregroundStyle(.secondary)
                    Text("Sleep applies to Bluetooth and 2.4 GHz. The app reapplies your saved time after reconnect.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Check keyboard") { model.checkOnboardPreviewSupport() }
                        .disabled(!model.connected || model.connectionName != "USB" || model.controlsLocked)
                    Text(model.onboardPreviewStatus).font(.caption).foregroundStyle(.secondary)
                }
                Section("Mac playback") {
                    Button("Open Mac playback…") { interface.showingMacPlayback = true }.disabled(model.busy)
                    Text("Optional playback while this app is running. Use Play or Save below for effects that run on the keyboard.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Frame rate", selection: $model.animationFPS) {
                        ForEach([15,30,60,90,120], id: \.self) { Text("\($0) FPS").tag($0) }
                    }
                    Text("Native keyboard playback uses the firmware frame rate, up to 50 FPS.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Restore saved lighting after reconnect", isOn: Binding(
                        get: { model.restoreOnReconnect }, set: { model.restoreOnReconnect = $0; model.saveRestorePreference() }))
                }
                Section("Saved profile") {
                    Text(model.savedProfileExists ? model.savedProfilePath : "No profile saved on this Mac yet.")
                        .font(.caption).textSelection(.enabled)
                    Button("Show in Finder") { model.showSavedProfileInFinder() }.disabled(!model.savedProfileExists)
                    if let name = model.openedProfileName { Text("Opened: \(name)").font(.caption) }
                }
                Section("Manual lighting") {
                    HStack {
                        Button("Set all keys") { model.setAll() }
                        Button("Clear") { model.clear() }
                    }
                    Picker("Built-in effect", selection: $model.effect) {
                        ForEach(0...18, id: \.self) { Text("Effect \($0)").tag($0) }
                        Text("On-keyboard layout").tag(20)
                    }
                    Button("Play built-in effect") { model.playBuiltIn() }
                }.disabled(!model.connected || model.busy)
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Back to My Lighting") { interface.page = .myLighting }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(maxWidth: 750, maxHeight: .infinity)
    }
    private var macPlaybackCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Run from Mac", systemImage: "desktopcomputer").font(.headline)
                Spacer()
                Text(model.playing ? "PLAYING" : "READY").font(.caption2.weight(.bold))
                    .foregroundStyle(model.playing ? Color.green : Color.secondary)
            }
            Text("Plays your layout while this app is open. For lighting that runs on the keyboard, close this sheet and use Play or Save to keyboard.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.playing ? "Apply & save on Mac" : "Play & save on Mac") { model.startStudio() }
                    .buttonStyle(.borderedProminent).disabled(!model.connected || model.busy)
                Button("Stop Mac playback") { model.stopPlayback() }
                    .disabled(!model.playing || model.busy)
            }
            HStack {
                Button("Test Mac key pulse") { model.previewPulse() }
                    .disabled(!model.playing || !model.hasReactiveLayers || model.busy)
                Spacer()
                keyResponseButton
            }
            Text(model.inputStatus).font(.caption).foregroundStyle(.secondary)
            if model.playing && model.lastPressedKey != "—" {
                Text("Last Mac-detected key: \(model.lastPressedKey)")
                    .font(.caption).foregroundStyle(.green)
            }
            Text("Input Monitoring is used for Mac playback. Effects playing on the keyboard detect key presses themselves.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var layerEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Affect all keys",isOn:$model.selectedLayer.affectAllKeys)
                .accessibilityIdentifier("affect-all-keys")
            Text(model.selectedLayer.keyIDs == nil
                 ? (model.settings.effect.requiresKeyPresses ? "Every key can trigger this effect. " + layerReachDescription : "All keys are selected. Select fewer keys on the keyboard to limit this layer.")
                 : layerReachDescription).font(.caption).foregroundStyle(.secondary)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 16) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Layer name", text: $model.selectedLayer.name).textFieldStyle(.roundedBorder).accessibilityLabel("Layer name")
                }
                GridRow {
                    Text("Effect").foregroundStyle(.secondary)
                    Picker("Effect", selection: $model.settings.effect) {
                        Section("Automatic") {
                            ForEach(LightingEffect.allCases.filter { !$0.requiresKeyPresses && $0 != .adaptiveMusic && $0 != .cpuTemperature }) { effect in
                                Text(effect.displayName).tag(effect)
                            }
                        }
                        Section("On key press") {
                            ForEach(LightingEffect.allCases.filter(\.requiresKeyPresses)) { effect in Text(effect.displayName).tag(effect) }
                        }
                        Section("Live Mac inputs") {
                            Text("Adaptive music").tag(LightingEffect.adaptiveMusic)
                            Text("CPU temperature").tag(LightingEffect.cpuTemperature)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Text("Color").foregroundStyle(.secondary)
                    ColorPicker("Layer color", selection: $model.selectedColor, supportsOpacity: false).labelsHidden()
                        .disabled(!model.settings.effect.usesSelectedColor)
                }
                GridRow {
                    Text("Speed").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Slider(value: $model.settings.speed, in: 0.25...3, step: 0.05).accessibilityLabel("Selected layer effect speed")
                        Text(String(format: "%.2f×", model.settings.speed)).monospacedDigit().frame(width: 55, alignment: .trailing)
                    }.disabled(!model.settings.effect.hasAdjustableSpeed)
                }
            }
            Text(model.settings.effect.detail).font(.caption).foregroundStyle(.secondary)
                .lineLimit(3).help(model.settings.effect.detail)
            Divider()
            if model.selectedLayer.keyIDs?.isEmpty == true {
                Text("No keys selected. This layer will not light up.").font(.caption).foregroundStyle(.orange)
            }
            if model.settings.effect == .aurora {
                Text("Corrected Aurora is included in complete firmware 1.0 (previous local build v1.8).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Advanced layer controls", isExpanded: $interface.showingAdvancedLayer) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Intensity"); Slider(value: $model.settings.intensity, in: 0...1); Text("\(Int(model.settings.intensity * 100))%").monospacedDigit().frame(width: 45) }
                    HStack { Text("Opacity"); Slider(value: $model.selectedLayer.opacity, in: 0...1); Text("\(Int(model.selectedLayer.opacity * 100))%").monospacedDigit().frame(width: 45) }
                    Picker("Blend", selection: $model.selectedLayer.blendMode) {
                        ForEach(LayerBlendMode.allCases) { Text($0.displayName).tag($0) }
                    }
                }.padding(.top, 12)
            }
            if model.settings.effect == .adaptiveMusic {
                Text(model.liveInputs.musicStatus).font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.settings.musicSensitivity, in: 0.25...4) { Text("Music sensitivity") }
                HStack { Button("Retry audio") { model.retryAudio() }.disabled(!model.playing); Button("Audio permissions") { model.openAudioSettings() } }
            }
            if model.settings.effect == .cpuTemperature {
                Text(model.liveInputs.temperatureStatus).font(.caption).foregroundStyle(.secondary)
                Stepper("Blue at \(Int(model.settings.temperatureCold))°C", value: $model.settings.temperatureCold, in: 10...min(80, model.settings.temperatureHot - 5), step: 5)
                Stepper("Red at \(Int(model.settings.temperatureHot))°C", value: $model.settings.temperatureHot, in: max(40, model.settings.temperatureCold + 5)...110, step: 5)
            }
        }.disabled(model.busy)
    }
    private var layerReachDescription: String {
        switch model.settings.effect {
        case .ripple, .rainbowRipple, .splash, .crossRipple, .rowWave, .columnWave:
            return model.selectedLayer.affectAllKeys
                ? "Only selected keys trigger this ripple. It spreads across the whole keyboard."
                : "Only selected keys trigger this ripple. Its light stays within your selection."
        case .reactive, .rainbowReactive:
            if model.selectedLayer.keyIDs == nil {
                return model.selectedLayer.affectAllKeys ? "Press any key to flash the whole keyboard, then fade." : "Only the key you press lights up, then fades."
            }
            return model.selectedLayer.affectAllKeys
                ? "A selected key press flashes the whole keyboard, then fades. Other keys do not trigger this layer."
                : "Only selected keys light up when pressed, then fade."
        case .keyToggle:
            return model.selectedLayer.affectAllKeys
                ? "Selected keys toggle the whole keyboard. It stays lit while any selected key is toggled on."
                : "Each selected key toggles on with one press and off with the next. Release does not clear it."
        case .keyHold:
            return model.selectedLayer.affectAllKeys
                ? "Hold a selected key to light the whole keyboard. It clears when you release every trigger key."
                : "Selected keys stay lit only while physically held; releasing a key clears its light."
        default:
            return model.selectedLayer.affectAllKeys
                ? "This effect covers the whole keyboard while keeping your key selection."
                : "This effect lights only the selected keys."
        }
    }
    private var mappingControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: model.isRowMapping ? "checkmark.circle.fill" : "keyboard")
                    .font(.title).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.isRowMapping ? "All 104 keys are mapped" : "Map the whole keyboard in one click")
                        .font(.headline)
                    Text("Escape = 0. Continue left to right, then start the next row.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.isRowMapping ? "Row layout applied" : "Apply row layout") { model.applyRowMapping() }
                    .buttonStyle(.borderedProminent).disabled(model.isRowMapping)
            }.padding(16).background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            if !model.manualMapping {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Click a key above to light it and check its position.")
                        Text("You can also press a physical key with key response enabled. Testing does not change the saved map.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    keyResponseButton
                }
                HStack {
                    Button { model.stepMappingTest(-1) } label: { Label("Previous key", systemImage: "chevron.left") }
                        .disabled(!model.connected || model.mappingIndex == 0)
                    Text(model.illuminatedIndex.map { "Testing LED \($0) · \(model.selectedMappingKey)" } ?? "Choose a key to test")
                        .foregroundStyle(.green).frame(minWidth: 250)
                    Button { model.stepMappingTest(1) } label: { Label("Next key", systemImage: "chevron.right") }
                        .disabled(!model.connected || model.mappingIndex == 103)
                    Spacer()
                    if model.canUndoMappingReset { Button("Undo last mapping change") { model.undoMappingReset() } }
                    Button("Reset to row order…") { model.quickMapping = false; model.confirmingMappingReset = true }
                }
            }
            DisclosureGroup("Correct an individual key (advanced)", isExpanded: $model.manualMapping) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("1. Light an LED.  2. Press or select the key that glows.  3. Save the correction.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Stepper("LED \(model.mappingIndex)", value: $model.mappingIndex, in: 0...103).frame(width: 140)
                        Button("Light this LED") { model.identify() }.disabled(!model.connected)
                        Button("Next LED") { model.stepMappingTest(1) }.disabled(!model.connected || model.mappingIndex == 103)
                        Spacer()
                        keyResponseButton
                    }
                    HStack {
                        Text(model.illuminatedIndex.map { "Lit LED: \($0)" } ?? "Light an LED first").foregroundStyle(.green).frame(width: 140, alignment: .leading)
                        Picker("Key", selection: $model.selectedMappingKey) {
                            Text("Select a key…").tag("")
                            ForEach(model.keys) { key in Text("\(key.label.replacingOccurrences(of: "\n", with: " / ")) (\(key.id))").tag(key.id) }
                        }.frame(width: 300)
                        Button("Save correction") { model.saveMapping() }.buttonStyle(.borderedProminent).disabled(!model.canSaveMapping)
                        Spacer()
                    }
                    Toggle("Save and advance automatically", isOn: $model.quickMapping).toggleStyle(.switch)
                    HStack {
                        Button("Import mapping…") { model.importMap() }
                        Button("Export mapping…") { model.exportMap() }.disabled(model.map == nil)
                        Spacer()
                    }
                }.padding(.top, 12)
            }
        }.disabled(model.busy)
    }
    private var keyResponseButton: some View {
        Button { model.enableKeyboardInput() } label: {
            Label(model.keyResponseEnabled ? "Key response enabled" : model.inputPermission == .granted ? "Retry key response" : "Enable Input Monitoring",
                  systemImage: model.keyResponseEnabled ? "checkmark.circle.fill" : "hand.tap")
                .foregroundStyle(model.keyResponseEnabled ? Color.green : Color.primary)
        }.buttonStyle(.bordered)
            .background(model.keyResponseEnabled ? Color.green.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .disabled(model.busy).help(model.inputStatus)
    }
    private var keyboard: some View { KeyboardDiagram(model:model,selectionTool:.automatic) }

}
struct MenuBarControls: View {
    @ObservedObject var model: ControllerModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text(model.playing ? "GMK104 • Effect running" : "GMK104 Lighting Studio")
        Button("Open Lighting Studio") {
            if let window=NSApp.windows.first(where:{ $0.title == "GMK104 Lighting Studio" }) { window.makeKeyAndOrderFront(nil) }
            else { openWindow(id:"studio") }
            NSApp.activate(ignoringOtherApps:true)
        }
        Button(model.playing ? "Stop effect" : "Resume saved lighting") { model.playing ? model.stopPlayback() : model.resumeSavedLighting() }
            .disabled(!model.connected || model.busy || model.mappingMode)
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}
#if !GMK104_UI_SNAPSHOT
final class StudioWorkspaceWindow {
    static let shared=StudioWorkspaceWindow()
    var controller:ControllerModel?
    private var workspace:NSWindow?
    func show() {
        NSApp.setActivationPolicy(.regular)
        if let existing=NSApp.windows.first(where:{ $0.title == "GMK104 Lighting Studio" && $0.isVisible }) {
            existing.makeKeyAndOrderFront(nil)
        } else if let workspace { workspace.makeKeyAndOrderFront(nil) }
        else if let controller {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1220,height:810),
                                styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="GMK104 Lighting Studio";window.identifier=NSUserInterfaceItemIdentifier("studio")
            window.isReleasedWhenClosed=false
            window.contentView=NSHostingView(rootView:ControllerView(model:controller))
            window.contentMinSize=NSSize(width:1080,height:670)
            window.setFrameAutosaveName("GMK104StudioWorkspace");window.center()
            workspace=window;window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps:true)
    }
}
final class StudioApplicationDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification) {
        DispatchQueue.main.async { StudioWorkspaceWindow.shared.show() }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool {
        StudioWorkspaceWindow.shared.show();return true
    }
}
@main struct GMK104App: App {
    @NSApplicationDelegateAdaptor(StudioApplicationDelegate.self) private var appDelegate
    @StateObject private var model: ControllerModel
    init() {
        if CommandLine.arguments.contains("--inspect") { exit(ControllerDiagnostics.inspect()) }
        NSApplication.shared.appearance = nil
        let controller=ControllerModel()
        _model = StateObject(wrappedValue:controller)
        StudioWorkspaceWindow.shared.controller=controller
        // Also schedule directly: a restored menu-bar scene can finish launch
        // before SwiftUI installs the delegate adaptor on some macOS builds.
        DispatchQueue.main.async { StudioWorkspaceWindow.shared.show() }
    }
    private var studioWindow: some Scene {
        WindowGroup("GMK104 Lighting Studio", id: "studio") { ControllerView(model: model) }.windowStyle(.titleBar).defaultSize(width: 1220, height: 810)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Open profile…") { model.chooseProfileFile() }.keyboardShortcut("o").disabled(model.busy)
                    Button("Save profile on Mac") { model.saveDraftToMac() }.keyboardShortcut("s").disabled(model.busy)
                    Button("Export profile…") { model.saveProfileFileAs() }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.busy)
                }
            }
    }
    var body: some Scene {
        studioWindow
        MenuBarExtra("GMK104", systemImage: "keyboard") { MenuBarControls(model: model) }
    }
}

#endif
