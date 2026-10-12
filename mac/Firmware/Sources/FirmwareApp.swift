import SwiftUI
import AppKit
import IOKit.hid

final class FirmwareModel: ObservableObject {
    #if GMK104_V08_LOCAL_TEST
    @Published var target: FirmwareTarget = .storageSurvey
    #elseif GMK104_V07_LOCAL_TEST
    @Published var target: FirmwareTarget = .onboardProfilePreview
    #else
    @Published var target: FirmwareTarget = .auroraLighting
    #endif
    @Published var status = "Checking the bundled firmware files…"
    @Published var filesVerified = false
    @Published var state: FirmwareDeviceState?
    @Published var busy = false
    @Published var flashing = false
    @Published var progress = 0.0
    @Published var confirmation = ""
    @Published var ready = false
    @Published var logURL: URL?
    @Published var permissionGranted = false
    @Published var permissionStatus = "Checking keyboard access…"
    @Published var completed = false
    @Published var connectionChecked = false
    #if GMK104_V08_LOCAL_TEST
    @Published var storageSurvey: FirmwareStorageSurvey.Result?
    #endif
    @Published var confirmPermissionRefresh = false
    @Published var page = 0
    private let queue = DispatchQueue(label: "GMK104.Firmware", qos: .userInitiated)
    static let shared = FirmwareModel()
    static func plan(_ target: FirmwareTarget) throws -> FirmwarePlan {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(target.file) else { throw ControllerError.message("Firmware resource is missing.") }
        return try FirmwarePlan(target: target, data: Data(contentsOf: url))
    }
    func verifyFiles() {
        refreshPermission()
        queue.async {
            do {
                for target in FirmwareTarget.publishedCases { _ = try Self.plan(target) }
                DispatchQueue.main.async {
                    self.filesVerified = true
                    #if GMK104_V08_LOCAL_TEST
                    self.status = "Exact read-only v0.8 diagnostic and v0.7 rollback images verified offline. No keyboard command was sent."
                    #elseif GMK104_V07_LOCAL_TEST
                    self.status = "Exact v0.7 RAM-only test and v0.6 rollback images verified offline. No keyboard command was sent."
                    #else
                    self.status = "Persistent lighting firmware, rollback image and packet plans verified. Inspect before installing."
                    #endif
                }
            } catch { DispatchQueue.main.async { self.status = error.localizedDescription } }
        }
    }
    func refreshPermission() {
        permissionGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        permissionStatus = permissionGranted ? "Keyboard access enabled" : "Keyboard access needs permission"
    }
    func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    func requestPermission() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermission()
        if !permissionGranted { openPermissionSettings() }
    }
    /// The user explicitly confirms this app-only reset in the guided UI.
    func resetPermission() {
        guard !busy else { return }
        busy = true; state = nil; connectionChecked = false
        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            #if GMK104_V08_LOCAL_TEST
            process.arguments = ["reset", "ListenEvent", "com.gmk104.firmwareinstaller.v08localtest"]
            #elseif GMK104_V07_LOCAL_TEST
            process.arguments = ["reset", "ListenEvent", "com.gmk104.firmwareinstaller.v07localtest"]
            #else
            process.arguments = ["reset", "ListenEvent", "com.gmk104.firmwareinstaller"]
            #endif
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run(); process.waitUntilExit()
                try require(process.terminationStatus == 0, "macOS could not refresh the permission. Remove this installer from Input Monitoring, add it again from Applications, then restart it.")
                DispatchQueue.main.async {
                    self.busy = false; self.refreshPermission()
                    #if GMK104_V08_LOCAL_TEST
                    self.status = "Permission refreshed. Add GMK104 v0.8 Storage Test Installer from Applications in Input Monitoring, turn it on, then restart it."
                    #elseif GMK104_V07_LOCAL_TEST
                    self.status = "Permission refreshed. In Input Monitoring, add the separate GMK104 v0.7 Local Test Installer from its staging folder, turn it on, then restart it."
                    #else
                    self.status = "Permission refreshed. In Input Monitoring, click +, add GMK104 Firmware Installer from Applications, and turn it on. Return here and click Restart installer."
                    #endif
                    self.openPermissionSettings()
                }
            } catch { DispatchQueue.main.async { self.busy = false; self.status = error.localizedDescription } }
        }
    }
    func restart() {
        guard !busy else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error { self.status = error.localizedDescription }
                else { NSApp.terminate(nil) }
            }
        }
    }
    func inspect() {
        guard !busy && filesVerified else { return }
        refreshPermission()
        guard permissionGranted else { status = "Finish step 1, then inspect the keyboard. Nothing was flashed."; return }
        busy = true; state = nil; confirmation = ""; ready = false; completed = false; connectionChecked = false; progress = 0
        status = "Inspecting keyboard identity and installed firmware…"
        queue.async {
            do {
                let state = try FirmwareInstaller.inspect()
                DispatchQueue.main.async { self.state = state; self.busy = false; self.status = state.description + ". Read-only inspection passed." }
            } catch { DispatchQueue.main.async { self.busy = false; self.status = error.localizedDescription } }
        }
    }
    #if GMK104_V08_LOCAL_TEST
    func surveyStorage() {
        guard !busy && filesVerified else { return }
        refreshPermission()
        guard permissionGranted else { status = "Enable keyboard access before reading the proposed storage sectors."; return }
        busy = true; progress = 0; storageSurvey = nil
        status = "Reading the proposed flash sectors. No data will be written."
        queue.async {
            do {
                let result = try FirmwareInstaller.surveyStorage { value, message in
                    DispatchQueue.main.async { self.progress = value; self.status = message }
                }
                DispatchQueue.main.async {
                    self.storageSurvey = result; self.progress = 1; self.busy = false
                    self.status = result.description
                }
            } catch {
                DispatchQueue.main.async { self.busy = false; self.status = error.localizedDescription }
            }
        }
    }
    #endif
    func checkConnection() {
        guard !busy && filesVerified else { return }
        refreshPermission()
        guard permissionGranted else { status = "Enable keyboard access in Prepare, then test the connection."; return }
        busy = true; state = nil; connectionChecked = false; progress = 0; confirmation = ""; ready = false; completed = false
        status = "Testing the USB connection for about one minute. This only reads firmware identity."
        queue.async {
            do {
                let state = try FirmwareInstaller.checkConnection { value, message in
                    DispatchQueue.main.async { self.progress = value; self.status = message }
                }
                DispatchQueue.main.async {
                    self.state = state; self.connectionChecked = true; self.busy = false; self.progress = 1
                    self.status = "Connection test passed: 4,000 matching replies and the lighting interface verified. No firmware was written."
                }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false; self.state = nil; self.connectionChecked = false
                    self.status = "Connection test stopped: \(error.localizedDescription) No firmware was written. Reconnect USB once, then inspect."
                }
            }
        }
    }
    func closeStudio() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.gmk104.rgbcontroller") { app.terminate() }
        status = "Lighting Studio was asked to quit. Click Inspect keyboard when it has closed."
    }
    var alreadyInstalled: Bool { state?.crc == target.crc }
    var canInstall: Bool {
        guard let state else { return false }
        return filesVerified && permissionGranted && connectionChecked && !busy && !alreadyInstalled && target.accepts(source: state.crc) && ready && confirmation == target.phrase
    }
    func install() {
        guard canInstall, let expected = state else { return }
        let chosen = target, phrase = confirmation
        flashing = true; busy = true; completed = false; progress = 0; logURL = nil
        status = "Approve the macOS administrator prompt. The installer will verify the keyboard again before sending firmware."
        let operation = FirmwareOperation(action: .install, nonce: UUID(), target: chosen, expected: expected, confirmation: phrase)
        queue.async {
            do {
                _ = try Self.plan(chosen)
                let result = try FirmwareAdministrator.perform(operation) { event in
                    DispatchQueue.main.async {
                        if event.kind == .logFile { self.logURL = URL(fileURLWithPath: event.message) }
                        if event.kind == .progress { self.progress = event.progress ?? 0; self.status = event.message }
                    }
                }
                DispatchQueue.main.async {
                    self.state = result; self.progress = 1; self.busy = false; self.flashing = false
                    self.confirmation = ""; self.ready = false; self.completed = true
                    #if GMK104_V08_LOCAL_TEST
                    self.status = chosen == .onboardProfilePreview
                        ? "The owner-tested v0.7 firmware was restored and verified after reboot."
                        : "Read-only v0.8 diagnostic booted and its USB identity was verified. Check normal typing, then click Read storage sectors here."
                    #elseif GMK104_V07_LOCAL_TEST
                    self.status = chosen == .nativeRippleFixed
                        ? "Tested v0.6 firmware was restored and its USB identity was verified after reboot."
                        : "RAM-only v0.7 test firmware booted and its USB identity was verified. Use Lighting Studio to upload a layered profile and physically test it."
                    #else
                    self.status = chosen == .persistentLighting || chosen == .performanceLighting || chosen == .reactiveLighting || (chosen == .matrixLighting || chosen == .matrixRainFixed || chosen == .matrixRainStaggered || chosen == .matrixRainVertical || chosen == .matrixColumns || chosen == .auroraLighting)
                        ? "Firmware identity verified after reboot. Open Lighting Studio, choose Save to keyboard, then turn the keyboard fully off and on to verify your saved layers return. Check typing and wireless modes too."
                        : "Firmware identity verified after reboot. Open Lighting Studio to check typing, lighting and wireless modes."
                    #endif
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = nil; self.busy = false; self.flashing = false; self.confirmation = ""; self.ready = false; self.connectionChecked = false
                    self.status = "Installation stopped: \(error.localizedDescription) Keep the log. Return to Check and inspect before another attempt."
                }
            }
        }
    }
}
final class FirmwareAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if FirmwareModel.shared.flashing {
            let alert = NSAlert(); alert.messageText = "Firmware installation is still running"
            alert.informativeText = "Keep the app open and the keyboard connected until upload and reboot verification finish."
            alert.addButton(withTitle: "Keep installing"); alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
private struct FirmwareView: View {
    @ObservedObject var model = FirmwareModel.shared
    private let steps = ["Prepare", "Check", "Install", "Test"]
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    #if GMK104_V08_LOCAL_TEST
                    Text("GMK104 v0.8 Storage Test Installer").font(.title2.bold())
                    #elseif GMK104_V07_LOCAL_TEST
                    Text("GMK104 v0.7 Local Test Installer").font(.title2.bold())
                    #else
                    Text("GMK104 Firmware Installer").font(.title2.bold())
                    #endif
                    Text("Version \(version) • Connect → Check → Install → Test").font(.callout).foregroundStyle(.secondary)
                }
            }
            #if GMK104_V08_LOCAL_TEST
            Label("UNRELEASED STORAGE TEST • Installing v0.8 writes firmware. Its new storage check only reads flash; it cannot save profiles permanently, and existing layers remain RAM-only.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            #elseif GMK104_V07_LOCAL_TEST
            Label("UNRELEASED HARDWARE TEST • Profiles live in keyboard RAM only and disappear on power loss. No persistent Save. Studio supports up to 16 layers, without Mac sensor layers.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            #endif
            HStack(spacing: 10) {
                ForEach(0..<4) { index in
                    Text("\(index + 1). \(steps[index])").font(.callout.weight(model.page == index ? .semibold : .regular))
                        .foregroundStyle(model.page == index ? Color.white : Color.secondary)
                        .padding(.vertical, 7).frame(maxWidth: .infinity)
                        .background(model.page == index ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if model.page == 0 { preparation }
                    if model.page == 1 { inspection }
                    if model.page == 2 { review }
                    if model.page == 3 { completion }
                }.frame(width: 628, alignment: .leading).padding(.vertical, 6)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            if model.busy { ProgressView(value: model.progress) }
            if model.flashing {
                Text("Waiting for each USB reply can take up to one minute. The overall upload limit is 12 minutes.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            HStack {
                if model.page > 0 && model.page < 3 { Button("Back") { model.page -= 1 }.disabled(model.busy) }
                if let logURL = model.logURL {
                    Button("Show install log") { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }
                }
                Spacer()
                if model.page == 0 {
                    Button("Next: Check keyboard") { model.page = 1 }
                        .buttonStyle(.borderedProminent).disabled(model.busy || !model.filesVerified || !model.permissionGranted)
                } else if model.page == 1 {
                    Button("Next: Review update") { model.page = 2 }
                        .buttonStyle(.borderedProminent).disabled(model.busy || !model.connectionChecked || model.state == nil || model.alreadyInstalled || !(model.state.map { model.target.accepts(source: $0.crc) } ?? false))
                } else if model.page == 2 {
                    #if GMK104_V08_LOCAL_TEST
                    Button(model.target == .onboardProfilePreview ? "Roll back to v0.7" : "Install v0.8 diagnostic") { model.install() }
                        .buttonStyle(.borderedProminent).tint(.orange).disabled(!model.canInstall)
                    #elseif GMK104_V07_LOCAL_TEST
                    Button(model.target == .nativeRippleFixed ? "Roll back to v0.6" : "Install v0.7 test firmware") { model.install() }
                        .buttonStyle(.borderedProminent).tint(.orange).disabled(!model.canInstall)
                    #else
                    Button(model.target == .stock ? "Restore stock firmware" : "Install custom firmware") { model.install() }
                        .buttonStyle(.borderedProminent).tint(.orange).disabled(!model.canInstall)
                    #endif
                } else {
                    #if GMK104_V07_LOCAL_TEST
                    Button("Open Lighting Studio") { openStudio() }
                        .buttonStyle(.borderedProminent)
                    #else
                    Button("Open Lighting Studio") { openStudio() }.buttonStyle(.borderedProminent)
                    #endif
                }
            }
        }.padding(24).frame(width: 680, height: 660)
            .onAppear { model.verifyFiles() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermission() }
            .onChange(of: model.completed) { if $0 { model.page = 3 } }
            .confirmationDialog("Refresh this installer’s Input Monitoring permission?", isPresented: $model.confirmPermissionRefresh) {
                Button("Refresh this installer’s permission") { model.resetPermission() }
                Button("Cancel", role: .cancel) {}
            } message: {
                #if GMK104_V08_LOCAL_TEST
                Text("This removes only the separate v0.8 storage test installer’s permission. Add it back from Applications in System Settings and turn it on again. Other apps are unaffected.")
                #elseif GMK104_V07_LOCAL_TEST
                Text("This removes only the separate v0.7 local test installer’s permission. Add this staged app back in System Settings and turn it on again. Other apps are unaffected.")
                #else
                Text("This removes only GMK104 Firmware Installer’s existing permission. Add the updated app back in System Settings and turn it on again. Other apps are unaffected.")
                #endif
            }
    }
    private var preparation: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Prepare the Mac and keyboard").font(.headline)
            Text("Connect the keyboard directly to the Mac with a USB data cable, select wired mode, and connect Mac power. Keep the lid open. Firmware updates cannot use Bluetooth or the 2.4 GHz receiver.")
                .fixedSize(horizontal: false, vertical: true)
            Label(model.filesVerified ? "Firmware files verified" : "Checking firmware files…", systemImage: model.filesVerified ? "checkmark.shield.fill" : "shield")
                .foregroundStyle(model.filesVerified ? Color.green : Color.secondary)
            Label(model.permissionStatus, systemImage: model.permissionGranted ? "checkmark.circle.fill" : "hand.raised.fill")
                .foregroundStyle(model.permissionGranted ? Color.green : Color.orange)
            if !model.permissionGranted {
                #if GMK104_V08_LOCAL_TEST
                Text("Click Allow keyboard access. In System Settings → Privacy & Security → Input Monitoring, turn on the separate GMK104 v0.8 Storage Test Installer, then restart it.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                #elseif GMK104_V07_LOCAL_TEST
                Text("Click Allow keyboard access. In System Settings → Privacy & Security → Input Monitoring, turn on the separate GMK104 v0.7 Local Test Installer, then restart this app.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                #else
                Text("Click Allow keyboard access. In System Settings → Privacy & Security → Input Monitoring, turn on GMK104 Firmware Installer, then restart this installer.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                #endif
            }
            HStack {
                Button("Allow keyboard access") { model.requestPermission() }.disabled(model.permissionGranted)
                Button("Open Input Monitoring") { model.openPermissionSettings() }
                Button("Restart installer") { model.restart() }
            }
            DisclosureGroup("Permission is on but connection still fails") {
                VStack(alignment: .leading, spacing: 10) {
                    #if GMK104_V08_LOCAL_TEST
                    Text("After rebuilding this diagnostic app, macOS may retain permission for an older build. Refresh only this test app’s entry, add the copy in Applications using + in Input Monitoring, turn it on, then restart it.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    #elseif GMK104_V07_LOCAL_TEST
                    Text("After rebuilding this local test app, macOS may retain permission for an older test build. Refresh only the test app’s entry, add this staged app using + in Input Monitoring, turn it on, then restart the test app.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    #else
                    Text("After an app update, macOS may retain permission for the old build. Refresh this installer’s entry, add the current app using + in Input Monitoring, turn it on, then restart the installer.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    #endif
                    Button("Refresh permission…") { model.confirmPermissionRefresh = true }
                }.padding(.top, 8)
            }
        }.disabled(model.busy)
    }
    private var inspection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Choose firmware and inspect").font(.headline)
            Picker("Firmware", selection: $model.target) {
                #if GMK104_V08_LOCAL_TEST
                Text("v0.8 read-only storage test").tag(FirmwareTarget.storageSurvey)
                Text("Roll back to owner-tested v0.7").tag(FirmwareTarget.onboardProfilePreview)
                #elseif GMK104_V07_LOCAL_TEST
                Text("v0.7 RAM-only local test").tag(FirmwareTarget.onboardProfilePreview)
                Text("Roll back to tested v0.6").tag(FirmwareTarget.nativeRippleFixed)
                #else
                ForEach(FirmwareTarget.publishedCases) { target in Text(target.name).tag(target) }
                #endif
            }.pickerStyle(.menu).frame(height: 30)
                .onChange(of: model.target) { _ in model.confirmation = ""; model.ready = false; model.completed = false }
            Text(model.target.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Quit Lighting Studio and any other keyboard tools, then inspect. Inspection checks the connected keyboard and installed firmware without starting an update.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Quit Lighting Studio") { model.closeStudio() }
                Button("Inspect keyboard") { model.inspect() }.buttonStyle(.borderedProminent).disabled(!model.filesVerified)
            }
            if let state = model.state {
                Label(state.description, systemImage: "keyboard").font(.callout.weight(.semibold))
                if model.alreadyInstalled {
                    Label("Already installed. No update is needed.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if !model.target.accepts(source: state.crc) {
                    #if GMK104_V08_LOCAL_TEST
                    Text("The v0.8 diagnostic starts only from v0.7, and its rollback returns only to v0.7. Inspect before choosing either update.").foregroundStyle(.orange)
                    #elseif GMK104_V07_LOCAL_TEST
                    Text("The v0.7 local test starts only from the tested v0.6 image. Rollback to v0.6 starts only from v0.7. Inspect before choosing either update.").foregroundStyle(.orange)
                    #else
                    Text(model.target == .streaming ? "This update requires Wireless v0.3 first." : model.target == .nativeRippleFixed ? "On-keyboard ripple v0.6 requires v0.3, v0.4, or the installed v0.5 first." : "This transition is unavailable. Inspect the installed version and choose a supported update or rollback.").foregroundStyle(.orange)
                    #endif
                }
            }
            #if GMK104_V08_LOCAL_TEST
            if model.state?.crc == FirmwareTarget.storageSurvey.crc {
                Button("Read storage sectors (no changes)") { model.surveyStorage() }
                    .buttonStyle(.borderedProminent)
                if let survey = model.storageSurvey { surveyDetails(survey) }
            }
            #endif
            Divider()
            Text("Before installing, test the USB connection for about one minute. This only reads the keyboard and checks that its replies stay reliable.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Test USB connection") { model.checkConnection() }.disabled(model.state == nil)
                if model.connectionChecked { Label("Connection test passed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }.disabled(model.busy)
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Review the update").font(.headline)
            Text(model.target.name).font(.title3.bold())
            if let state = model.state { Text("Currently: \(state.description)").font(.callout).foregroundStyle(.secondary) }
            Text("Allow about three to four minutes. Keep USB connected during upload and reboot. This is experimental firmware; recovery is not guaranteed if USB stops responding. macOS will ask for administrator approval to give the installer exclusive access during the update.")
                .fixedSize(horizontal: false, vertical: true)
            #if GMK104_V08_LOCAL_TEST
            Text("Unreleased read-only diagnostic: after installation, use Read storage sectors in this installer to inspect the flash ID and two proposed storage sectors. The new diagnostic never erases or programs flash; custom layouts still disappear on power loss. v0.7 is bundled for rollback if USB remains responsive.")
                .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            #elseif GMK104_V07_LOCAL_TEST
            Text("Unreleased RAM-only test: after firmware installation, use Lighting Studio to upload up to sixteen layers over wired USB. Mac music and CPU sensor layers are not supported yet. The profile disappears on power loss. Tested v0.6 is bundled for rollback if USB still works.")
                .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            #endif
            Toggle("The keyboard is wired, my Mac is on power, and I’m ready to update", isOn: $model.ready)
            HStack {
                Text("To install, type: \(model.target.phrase)").font(.caption).textSelection(.enabled)
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.target.phrase, forType: .string) }
            }
            TextField("Confirmation phrase", text: $model.confirmation).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Firmware confirmation phrase")
        }.disabled(model.busy)
    }
    private var completion: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Installed and verified after reboot", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            if let state = model.state { Text(state.description).font(.callout.weight(.semibold)) }
            #if GMK104_V08_LOCAL_TEST
            if model.target == .onboardProfilePreview {
                Text("v0.7 is restored. Verify typing and the existing onboard effects. Layouts remain RAM-only.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This confirms USB boot and firmware identity only. Verify typing, then read the proposed sectors here. Blank sectors do not prove ownership. The custom profile uploader has no flash-write path, so layouts still disappear on power loss.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Read storage sectors (no changes)") { model.surveyStorage() }
                    .buttonStyle(.borderedProminent)
                if let survey = model.storageSurvey { surveyDetails(survey) }
            }
            #elseif GMK104_V07_LOCAL_TEST
            if model.target == .nativeRippleFixed {
                Text("v0.6 is restored. Verify typing and its on-keyboard rainbow ripple. This rollback required the keyboard to keep responding over wired USB.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This confirms USB boot and firmware identity only. Verify ordinary typing and stock lighting first. Use Lighting Studio to upload up to sixteen layers while wired. Music/CPU sensor layers are not supported yet. Profiles will not survive a power loss. If USB still responds, return to Check and choose Roll back to tested v0.6.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            #else
            if model.target == .persistentLighting || model.target == .performanceLighting || model.target == .reactiveLighting || (model.target == .matrixLighting || model.target == .matrixRainFixed || model.target == .matrixRainStaggered || model.target == .matrixRainVertical || model.target == .matrixColumns || model.target == .auroraLighting) {
                Text("Check normal typing. Open Lighting Studio and create your layers, then choose Save to keyboard. Unplug USB and turn the keyboard fully off, then turn it back on: the saved layers, speeds, colors and brightness should return without the app. Unplugging USB alone may leave the keyboard powered by its battery.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Check held-key release, ripple reach, Bluetooth, 2.4 GHz and wake from sleep. Profile uploads and permanent saves use wired USB.")
                    .fixedSize(horizontal: false, vertical: true)
                Text((model.target == .matrixLighting || model.target == .matrixRainFixed || model.target == .matrixRainStaggered || model.target == .matrixRainVertical || model.target == .matrixColumns || model.target == .auroraLighting) ? "The saved profile should load automatically. Choose Aurora, Matrix rain, Spaced matrix rain or Matrix key rain in Lighting Studio and adjust speed and color. Save to keyboard stores the layer for startup after power-off. Before rollback, first save a profile containing only effects supported by the older firmware. Rollback needs responsive wired USB." : model.target == .reactiveLighting ? "The saved profile should load automatically. Choose a new reactive effect in Lighting Studio, then Save to keyboard to store its configuration. Test fast typing and unplug/reconnect. To roll back, first save a profile containing only older effects; v1.0 and v1.1 reject new effect IDs. Wired USB must still work." : model.target == .performanceLighting ? "The saved profile should load automatically. Test fast typing with ripple while Lighting Studio is closed. If needed, reconnect wired USB, inspect and choose Persistent v1.0 / rollback. Rollback requires working USB and leaves profile storage untouched." : "If a problem occurs, reconnect wired USB, inspect, and choose Restore previous v0.8. Rollback requires working USB and leaves profile storage untouched.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Check normal typing, lighting, Bluetooth, 2.4 GHz and wake from sleep. A previous firmware may play temporary profiles but cannot restore saved Studio layers after power loss.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif
            Button("Choose another firmware or rollback") {
                model.completed = false
                #if GMK104_V08_LOCAL_TEST
                model.target = .onboardProfilePreview
                #elseif GMK104_V07_LOCAL_TEST
                model.target = .nativeRippleFixed
                #else
                model.target = model.state?.crc == FirmwareTarget.auroraLighting.crc ? .stock : .auroraLighting
                #endif
                model.confirmation = ""; model.ready = false; model.page = 1
            }
        }
    }
    #if GMK104_V08_LOCAL_TEST
    private func surveyDetails(_ result: FirmwareStorageSurvey.Result) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(result.description, systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green).fixedSize(horizontal: false, vertical: true)
            ForEach(result.sectors, id: \.address) { sector in
                Text(String(format: "Sector %05X: %@ • SHA-256 %@", sector.address,
                            sector.erased ? "blank" : "contains data", sector.sha256))
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }
    #endif
    private func openStudio() {
        #if GMK104_V07_LOCAL_TEST
        if model.target == .nativeRippleFixed {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/GMK104 RGB Controller.app"))
            return
        }
        let installed = URL(fileURLWithPath: "/Applications/GMK104 RGB Controller.app")
        if let bundle = Bundle(url: installed),
           bundle.bundleIdentifier == "com.gmk104.rgbcontroller",
           ["1.6.1", "1.6.2", "1.6.3", "1.6.4"].contains(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") {
            NSWorkspace.shared.open(installed)
            return
        }
        model.status = "Install the current Lighting Studio from this project before testing an on-keyboard profile."
        #else
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/GMK104 RGB Controller.app"))
        #endif
    }
}

private struct FirmwareInstallerApp: App {
    @NSApplicationDelegateAdaptor(FirmwareAppDelegate.self) private var delegate
    var body: some Scene {
        #if GMK104_V08_LOCAL_TEST
        WindowGroup("GMK104 v0.8 Storage Test Installer") { FirmwareView() }
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .newItem) {} }
        #elseif GMK104_V07_LOCAL_TEST
        WindowGroup("GMK104 v0.7 Local Test Installer") { FirmwareView() }
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .newItem) {} }
        #else
        WindowGroup("GMK104 Firmware Installer") { FirmwareView() }
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .newItem) {} }
        #endif
    }
}
@main private enum FirmwareEntry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty { FirmwareInstallerApp.main(); return }
        if arguments.count == 2 && arguments[0] == "--authorized-operation" {
            exit(FirmwareAuthorizedHelper.run(encoded: arguments[1]))
        }
        do {
            guard arguments == ["--dry-run"] || arguments == ["--inspect"] || arguments == ["--check-connection"] else {
                throw ControllerError.message("Use --dry-run for offline packet verification, --inspect for read-only USB inspection or --check-connection for the sustained read-only USB test. Flashing requires the app's confirmation screen.")
            }
            for target in FirmwareTarget.publishedCases {
                let plan = try FirmwareModel.plan(target)
                print("PASS \(target.name): SHA256 \(plan.imageHash); stream \(plan.streamHash); \(plan.reports.count) reports")
            }
            if arguments == ["--inspect"] { print(try FirmwareInstaller.inspect().description); print("READ-ONLY INSPECTION PASSED. No OTA START was sent.") }
            else if arguments == ["--check-connection"] {
                let checked = try FirmwareInstaller.checkConnection { value, message in
                    if Int(value * 4000) % 500 == 0 { print(message); fflush(stdout) }
                }
                print(checked.description)
                print("4,000-QUERY READ-ONLY CONNECTION CHECK PASSED. No OTA START was sent.")
            }
            else { print("OFFLINE DRY RUN PASSED. No HID device was enumerated or opened.") }
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
}
