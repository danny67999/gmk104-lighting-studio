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
        }
    }
}
struct ControllerView: View {
    @ObservedObject var model: ControllerModel
    @State private var confirmingMappingReset = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack {
                    Label(model.playing ? "LIVE • \(model.playingEffectName)" : model.state.map { $0.effect == 19 ? "Direct RGB" : "Built-in effect \($0.effect)" } ?? "Awaiting connection", systemImage: "keyboard")
                    if model.playing && model.measuredFPS > 0 { Text(String(format: "%.0f fps actual · %d cap", model.measuredFPS, model.playingFPSLimit)).monospacedDigit() }
                    Spacer()
                    Text("\(model.mappedCount) / 104 keys mapped").foregroundStyle(.secondary)
                    if !model.mappingMode {
                        Button("Key mapping") { model.mappingMode = true }.disabled(model.busy)
                    }
                }.font(.callout)
                keyboard
                if !model.indicatorNotice.isEmpty {
                    Label(model.indicatorNotice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                if model.mappingMode { mappingControls }
                else { studioControls }
                Text(model.status).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .padding(12).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }.padding(26)
        }.frame(minWidth: 1130, idealWidth: 1220, minHeight: 790)
            .background(Color(red: 0.055, green: 0.064, blue: 0.07))
            .preferredColorScheme(.dark).tint(Color(red: 0.25, green: 0.9, blue: 0.5))
            .confirmationDialog("Reset the key mapping?", isPresented: $confirmingMappingReset, titleVisibility: .visible) {
                Button("Reset mapping", role: .destructive) { model.resetMapping() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This restores all 104 assignments in GMK104 row order, starting with Escape at LED 0. Your current map is backed up so you can undo the reset.")
            }
    }
    private var header: some View {
        HStack {
            if model.mappingMode {
                Button { model.mappingMode = false } label: { Label("Back to effects", systemImage: "chevron.left") }
                    .disabled(model.busy)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("GMK104").font(.system(size: 29, weight: .bold, design: .rounded))
                Text("LIGHTING STUDIO").font(.system(size: 10, weight: .semibold)).tracking(3).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 8, height: 8)
            Text(model.connected ? "\(model.connectionName) connected" : "Offline").foregroundStyle(.secondary)
            if model.busy { ProgressView().controlSize(.small) }
            Button(model.connected ? "Disconnect" : "Connect") { model.connected ? model.disconnect() : model.connect() }
                .disabled(model.busy)
            Button("Refresh") { model.refresh() }.disabled(!model.connected || model.busy)
        }
    }
    private var studioControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Effect layers", systemImage: "square.3.layers.3d").font(.title3.weight(.semibold))
                Text("Top layers appear above those below.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.hasLayerChanges { Text("Changes waiting to apply").font(.caption).foregroundStyle(.orange) }
            }
            HStack(alignment: .top, spacing: 18) {
                layerStack.frame(width: 255)
                Divider()
                layerEditor.frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(model.busy)
            HStack {
                Picker("Animation FPS cap", selection: $model.animationFPS) {
                    ForEach([15, 30, 60, 90, 120], id: \.self) { rate in Text("\(rate) FPS").tag(rate) }
                }.frame(width: 240)
                Text("Shared by all layers. Actual FPS depends on the keyboard connection.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.disabled(model.busy)
            HStack(spacing: 16) {
                Picker("Keyboard brightness", selection: $model.brightness) {
                    ForEach(0...4, id: \.self) { Text("\($0)").tag($0) }
                }.frame(width: 230)
                Spacer()
                Button("Test key pulse") { model.previewPulse() }.disabled(!model.playing || !model.hasReactiveLayers)
                Button(model.playing ? "Apply & save layers" : "Start & save layers") { model.startStudio() }
                    .buttonStyle(.borderedProminent).disabled(!model.connected)
                Button("Stop") { model.stopPlayback() }.disabled(!model.playing)
            }.disabled(model.busy)
            HStack {
                Image(systemName: "hand.tap").foregroundStyle(model.keyResponseEnabled ? Color.green : Color.secondary)
                Text(model.inputStatus).font(.caption).foregroundStyle(.secondary)
                if model.playing && model.lastPressedKey != "—" {
                    Text("Last key: \(model.lastPressedKey)").font(.caption).foregroundStyle(.green)
                }
                Spacer()
                keyResponseButton
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Wireless sleep after", selection: $model.sleepAfterSeconds) {
                        ForEach(KeyboardPreferences.choices, id: \.self) { seconds in
                            Text(KeyboardPreferences.label(seconds)).tag(seconds)
                        }
                    }.frame(width: 270)
                    Button("Apply sleep time") { model.applySleepTime() }
                        .disabled(!model.connected || !model.sleepSupported || model.controlsLocked)
                    Spacer()
                }
                Text(model.sleepStatus).font(.caption).foregroundStyle(.secondary)
                Text("Applies to Bluetooth and 2.4 GHz. The keyboard returns to 5 minutes after power-off until this app reapplies your saved time.")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(model.busy)
            Divider()
            HStack {
                Toggle("Restore saved lighting after reconnect", isOn: $model.restoreOnReconnect)
                    .onChange(of: model.restoreOnReconnect) { _ in model.saveRestorePreference() }
                Spacer()
                Text("Runs from your Mac • Keeps playing in the menu bar").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Manual color & built-in effects") {
                HStack(spacing: 16) {
                    Button("Set all keys") { model.setAll() }
                    Button("Clear") { model.clear() }
                    Button("Apply brightness") { model.applyBrightness() }
                    Spacer()
                    Picker("Built-in effect", selection: $model.effect) { ForEach(0...18, id: \.self) { Text("\($0)").tag($0) } }.frame(width: 180)
                    Button("Play & save") { model.playBuiltIn() }
                }.padding(.top, 10).disabled(!model.connected || model.busy)
            }.font(.callout)
        }
    }
    private var layerStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(model.layers.count) / \(LightingLayer.limit) layers").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(LightingEffect.allCases) { effect in
                        Button(effect.displayName) { model.addLayer(effect) }
                    }
                } label: { Label("Add layer", systemImage: "plus") }
                    .disabled(model.layers.count >= LightingLayer.limit)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.layers) { layer in
                        HStack(spacing: 8) {
                            Toggle("Enable \(layer.name)", isOn: Binding(
                                get: { model.layers.first { $0.id == layer.id }?.enabled ?? false },
                                set: { value in
                                    if let index = model.layers.firstIndex(where: { $0.id == layer.id }) { model.layers[index].enabled = value }
                                })).labelsHidden().toggleStyle(.checkbox)
                            Button {
                                model.selectedLayerID = layer.id
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: layer.settings.effect.symbol)
                                        .symbolRenderingMode(layer.settings.effect == .rainbowRipple ? .multicolor : .monochrome)
                                        .foregroundStyle(ControllerModel.color(layer.settings.color)).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(layer.name).font(.callout.weight(.medium)).lineLimit(1)
                                        Text("\(layer.keyIDs.map { "\($0.count) \(layer.settings.effect.requiresKeyPresses ? "triggers" : "keys")" } ?? "All keys")\(layer.affectAllKeys ? " → All keys" : "") • \(Int(layer.opacity * 100))%")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Select layer \(layer.name)")
                        }.padding(10)
                            .background(model.selectedLayer.id == layer.id ? Color.green.opacity(0.13) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.selectedLayer.id == layer.id ? Color.green.opacity(0.65) : .clear))
                            .opacity(layer.enabled ? 1 : 0.55)
                    }
                }
            }.frame(minHeight: 120, maxHeight: 232)
            HStack {
                Button { model.moveLayer(-1) } label: { Image(systemName: "arrow.up") }
                    .help("Move layer up").accessibilityLabel("Move layer up")
                    .disabled(model.layers.first?.id == model.selectedLayer.id)
                Button { model.moveLayer(1) } label: { Image(systemName: "arrow.down") }
                    .help("Move layer down").accessibilityLabel("Move layer down")
                    .disabled(model.layers.last?.id == model.selectedLayer.id)
                Button { model.duplicateLayer() } label: { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate layer").accessibilityLabel("Duplicate layer")
                    .disabled(model.layers.count >= LightingLayer.limit)
                Spacer()
                Button { model.removeLayer() } label: { Image(systemName: "trash") }
                    .help("Remove layer").accessibilityLabel("Remove layer").disabled(model.layers.count == 1)
            }
        }
    }
    private var layerEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Layer name", text: $model.selectedLayer.name).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Layer name").frame(maxWidth: 260)
                Spacer()
                Picker("Blend", selection: $model.selectedLayer.blendMode) {
                    ForEach(LayerBlendMode.allCases) { mode in Text(mode.displayName).tag(mode) }
                }.frame(width: 180)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
                ForEach(LightingEffect.allCases) { effect in
                    Button { model.settings.effect = effect } label: {
                        VStack(spacing: 6) {
                            Image(systemName: effect.symbol).font(.system(size: 18))
                                .symbolRenderingMode(effect == .rainbowRipple ? .multicolor : .monochrome)
                            Text(effect.displayName).font(.system(size: 11, weight: .medium))
                        }.frame(maxWidth: .infinity, minHeight: 58)
                            .contentShape(Rectangle())
                            .background(model.settings.effect == effect ? Color.green.opacity(0.13) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(model.settings.effect == effect ? Color.green.opacity(0.7) : Color.white.opacity(0.08)))
                    }.buttonStyle(.plain).accessibilityLabel(effect.displayName)
                }
            }
            HStack(spacing: 18) {
                ColorPicker("Color", selection: $model.selectedColor, supportsOpacity: false).frame(width: 110)
                    .disabled(!model.settings.effect.usesSelectedColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "Speed  %.2f×", model.settings.speed)).font(.caption).foregroundStyle(.secondary)
                    Slider(value: $model.settings.speed, in: 0.25...3).accessibilityLabel("Layer speed")
                }.disabled(model.settings.effect == .staticColor || model.settings.effect == .cpuTemperature)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity  \(Int(model.selectedLayer.opacity * 100))%").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $model.selectedLayer.opacity, in: 0...1).accessibilityLabel("Layer opacity")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intensity  \(Int(model.settings.intensity * 100))%").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $model.settings.intensity, in: 0...1).accessibilityLabel("Layer intensity")
                }
            }
            Text(model.settings.effect.detail).font(.caption).foregroundStyle(.secondary)
            if model.settings.effect == .adaptiveMusic {
                HStack {
                    Image(systemName: "waveform").foregroundStyle(model.liveInputs.audioRunning ? Color.green : Color.secondary)
                    Text(model.liveInputs.musicStatus).font(.caption)
                    Spacer()
                    Button("Retry audio") { model.retryAudio() }.disabled(!model.playing)
                    Button("Audio permissions") { model.openAudioSettings() }
                }
                ProgressView(value: model.liveInputs.music.level).tint(.green).accessibilityLabel("Mac audio activity")
                HStack {
                    Text(String(format: "Sensitivity %.2f×", model.settings.musicSensitivity)).font(.caption)
                    Slider(value: $model.settings.musicSensitivity, in: 0.25...4).accessibilityLabel("Music sensitivity")
                }
            }
            if model.settings.effect == .cpuTemperature {
                Label(model.liveInputs.temperatureStatus, systemImage: "thermometer.medium").font(.caption)
                    .foregroundStyle(model.liveInputs.cpuCelsius == nil ? Color.secondary : Color.green)
                HStack {
                    Stepper("Blue at \(Int(model.settings.temperatureCold))°C", value: $model.settings.temperatureCold,
                            in: 10...min(80, model.settings.temperatureHot - 5), step: 5)
                    Spacer()
                    Stepper("Red at \(Int(model.settings.temperatureHot))°C", value: $model.settings.temperatureHot,
                            in: max(40, model.settings.temperatureCold + 5)...110, step: 5)
                }.font(.caption)
            }
            Divider()
            HStack {
                Label(model.selectedLayer.keyIDs.map { "\($0.count) \(model.settings.effect.requiresKeyPresses ? "trigger keys" : "selected keys")" } ??
                      (model.settings.effect.requiresKeyPresses ? "All 104 keys can trigger" : "All 104 keys"), systemImage: "keyboard")
                    .font(.callout)
                Spacer()
                Button(model.selectingLayerKeys ? "Done selecting" : "Choose keys") { model.selectingLayerKeys.toggle() }
                    .tint(model.selectingLayerKeys ? .green : .accentColor)
            }
            HStack {
                Text("Select:").font(.caption).foregroundStyle(.secondary)
                Button("All") { model.setLayerKeys(nil) }
                Button("None") { model.setLayerKeys([]); model.selectingLayerKeys = true }
                Button("WASD") { model.setLayerKeys(["KeyW", "KeyA", "KeyS", "KeyD"]) }
                Button("Arrows") { model.setLayerKeys(["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"]) }
                Button("Numpad") { model.setLayerKeys(model.keys.filter { $0.id.hasPrefix("Numpad") }.map(\.id)) }
                Spacer()
            }.controlSize(.small)
            Toggle("Affect all keys", isOn: $model.selectedLayer.affectAllKeys)
                .toggleStyle(.switch).accessibilityLabel("Affect all keys")
            Text(layerReachDescription).font(.caption).foregroundStyle(.secondary)
            if model.selectingLayerKeys {
                Text(model.settings.effect.requiresKeyPresses
                     ? "Click keys above to choose which presses trigger this layer. Green outlines show its trigger keys."
                     : "Click keys on the keyboard above to include or exclude them. Green outlines show this layer’s keys.")
                    .font(.caption).foregroundStyle(.green)
            } else if model.selectedLayer.keyIDs?.isEmpty == true {
                Text("This layer has no keys selected and will not light up. Choose a group or click Choose keys.").font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private var layerReachDescription: String {
        switch model.settings.effect {
        case .ripple, .rainbowRipple:
            return model.selectedLayer.affectAllKeys
                ? "Only selected keys trigger this ripple. It spreads across the whole keyboard."
                : "Only selected keys trigger this ripple. Its light stays within your selection."
        case .reactive:
            return model.selectedLayer.affectAllKeys
                ? "A selected key press flashes the whole keyboard, then fades. Other keys do not trigger this layer."
                : "Only selected keys light up when pressed, then fade."
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
                    Button("Reset to row order…") { model.quickMapping = false; confirmingMappingReset = true }
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
            Label(model.keyResponseEnabled ? "Key response enabled" : "Enable key response",
                  systemImage: model.keyResponseEnabled ? "checkmark.circle.fill" : "hand.tap")
                .foregroundStyle(model.keyResponseEnabled ? Color.green : Color.primary)
        }.buttonStyle(.bordered)
            .background(model.keyResponseEnabled ? Color.green.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .disabled(!model.connected || model.busy).help(model.inputStatus)
    }
    private var keyboard: some View {
        GeometryReader { g in
            let unit = min(g.size.width / 23, g.size.height / 6.5)
            ZStack(alignment: .topLeading) {
                ForEach(model.keys) { key in
                    let mapping = model.map?.mappings.first { $0.keyId == key.id }
                    let known = mapping?.confirmed == true
                    let color = keyColor(mapping)
                    let selected = model.mappingMode ? model.selectedMappingKey == key.id : model.selectingLayerKeys && model.layerIncludes(key)
                    Button { model.click(key) } label: {
                        VStack(spacing: 3) {
                            Text(key.label).font(.system(size: 10, weight: .medium)).multilineTextAlignment(.center)
                            if model.mappingMode, let index = mapping?.ledIndex {
                                Text("\(index)").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                            } else if !known { Circle().fill(.gray).frame(width: 3, height: 3) }
                        }.frame(width: key.width * unit - 4, height: key.height * unit - 4)
                            .contentShape(Rectangle())
                            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                            .background(color.opacity(0.32), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.green : known ? color.opacity(0.9) : Color.gray.opacity(0.25), lineWidth: selected ? 3 : 1))
                            .shadow(color: known ? color.opacity(0.25) : .clear, radius: 4)
                    }.buttonStyle(.plain).disabled(model.busy || model.map == nil || (!model.connected && !model.selectingLayerKeys))
                        .opacity(model.selectingLayerKeys && !model.layerIncludes(key) ? 0.35 : 1)
                        .accessibilityLabel(key.id)
                        .help(known ? "\(key.id) • LED \(mapping?.ledIndex ?? 0)" : "\(key.id) • LED not yet mapped")
                        .offset(x: key.x * unit + 2, y: key.y * unit + 2)
                }
            }.frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }.frame(height: 296).padding(14).background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
    private func keyColor(_ mapping: KeyMapping?) -> Color {
        guard let mapping, mapping.confirmed, let index = mapping.ledIndex else { return .gray }
        guard let frame = model.frame else { return .green }
        return ControllerModel.color(frame[index])
    }
}
struct MenuBarControls: View {
    @ObservedObject var model: ControllerModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text(model.playing ? "GMK104 • Effect running" : "GMK104 Lighting Studio")
        Button("Open Lighting Studio") { openWindow(id: "studio"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.playing ? "Stop effect" : "Resume saved lighting") { model.playing ? model.stopPlayback() : model.resumeSavedLighting() }
            .disabled(!model.connected || model.busy || model.mappingMode)
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}
@main struct GMK104App: App {
    @StateObject private var model = ControllerModel()
    var body: some Scene {
        Window("GMK104 Lighting Studio", id: "studio") { ControllerView(model: model) }.windowStyle(.titleBar)
        MenuBarExtra("GMK104", systemImage: "keyboard") { MenuBarControls(model: model) }
    }
}
