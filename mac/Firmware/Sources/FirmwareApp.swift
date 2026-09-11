import SwiftUI
import AppKit

final class FirmwareModel: ObservableObject {
    @Published var target: FirmwareTarget = .custom
    @Published var status = "Checking the bundled firmware files…"
    @Published var filesVerified = false
    @Published var state: FirmwareDeviceState?
    @Published var busy = false
    @Published var flashing = false
    @Published var progress = 0.0
    @Published var confirmation = ""
    @Published var ready = false
    @Published var logURL: URL?
    private let queue = DispatchQueue(label: "GMK104.Firmware", qos: .userInitiated)
    static let shared = FirmwareModel()
    static func plan(_ target: FirmwareTarget) throws -> FirmwarePlan {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(target.file) else { throw ControllerError.message("Firmware resource is missing.") }
        return try FirmwarePlan(target: target, data: Data(contentsOf: url))
    }
    func verifyFiles() {
        queue.async {
            do {
                for target in FirmwareTarget.allCases { _ = try Self.plan(target) }
                DispatchQueue.main.async { self.filesVerified = true; self.status = "Both firmware images and their complete OTA packet streams match the verified PC build." }
            } catch { DispatchQueue.main.async { self.status = error.localizedDescription } }
        }
    }
    func inspect() {
        guard !busy && filesVerified else { return }
        busy = true; state = nil; confirmation = ""; ready = false
        status = "Inspecting keyboard identity and installed firmware…"
        queue.async {
            do {
                let state = try FirmwareInstaller.inspect()
                DispatchQueue.main.async { self.state = state; self.busy = false; self.status = state.description + ". Read-only inspection passed." }
            } catch { DispatchQueue.main.async { self.busy = false; self.status = error.localizedDescription } }
        }
    }
    func closeStudio() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.gmk104.rgbcontroller") { app.terminate() }
        status = "Lighting Studio was asked to quit. Click Inspect keyboard when it has closed."
    }
    var alreadyInstalled: Bool { state?.crc == target.crc }
    var canInstall: Bool {
        guard let state else { return false }
        return filesVerified && !busy && !alreadyInstalled && target.accepts(source: state.crc) && ready && confirmation == target.phrase
    }
    func install() {
        guard canInstall, let expected = state else { return }
        let chosen = target, phrase = confirmation
        flashing = true; busy = true; progress = 0; status = "Verifying the keyboard again before starting…"
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/GMK104/Firmware-\(UUID().uuidString).log")
        logURL = log
        queue.async {
            do {
                let plan = try Self.plan(chosen)
                let result = try FirmwareInstaller.install(plan: plan, expected: expected, confirmation: phrase, logURL: log) { value, message in
                    DispatchQueue.main.async { self.progress = value; self.status = message }
                }
                DispatchQueue.main.async {
                    self.state = result; self.progress = 1; self.busy = false; self.flashing = false
                    self.confirmation = ""; self.ready = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = nil; self.busy = false; self.flashing = false; self.confirmation = ""; self.ready = false
                    self.status = "Installation stopped: \(error.localizedDescription) Keep the log and inspect before taking any further action."
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
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 5) {
                    Text("GMK104 Firmware Installer").font(.title2.bold())
                    Text("Verified PC firmware • Native Mac installer").foregroundStyle(.secondary)
                }
            }
            Label(model.filesVerified ? "Firmware files verified" : "Checking firmware files", systemImage: model.filesVerified ? "checkmark.shield.fill" : "shield")
                .foregroundStyle(model.filesVerified ? Color.green : Color.secondary)
            Picker("Firmware", selection: $model.target) {
                ForEach(FirmwareTarget.allCases) { target in Text(target.name).tag(target) }
            }.pickerStyle(.segmented).disabled(model.busy)
                .onChange(of: model.target) { _ in model.confirmation = ""; model.ready = false }
            Text(model.target == .custom
                 ? "Adds the direct RGB protocol used by Lighting Studio. Installs only over the approved stock firmware."
                 : "Restores the approved stock application from custom v0.2 or retired v0.1. The keyboard must still respond over USB.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Quit Lighting Studio") { model.closeStudio() }
                Button("Inspect keyboard") { model.inspect() }.buttonStyle(.borderedProminent).disabled(!model.filesVerified)
            }.disabled(model.busy)
            if let state = model.state {
                Label(state.description, systemImage: "keyboard").font(.callout.weight(.semibold))
            }
            Divider()
            if model.alreadyInstalled {
                Label("This firmware is already installed. No update is needed.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("Experimental firmware. Use wired USB, a stable direct port and Mac power. Close other keyboard tools. Keep the cable connected during upload and reboot. Software recovery is not guaranteed if USB stops responding.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Toggle("The keyboard is wired, my Mac is on power, and I’m ready to update", isOn: $model.ready)
                Text("To install, type: \(model.target.phrase)").font(.caption).textSelection(.enabled)
                TextField("Confirmation phrase", text: $model.confirmation).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Firmware confirmation phrase")
                Button(model.target == .custom ? "Install custom firmware" : "Restore stock firmware") { model.install() }
                    .buttonStyle(.borderedProminent).tint(.orange).disabled(!model.canInstall)
            }
            if model.busy { ProgressView(value: model.progress) }
            Text(model.status).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Lighting Studio") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/GMK104 RGB Controller.app"))
                }.disabled(model.busy)
                if let logURL = model.logURL {
                    Button("Show install log") { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }
                }
            }
        }.padding(26).frame(width: 620).disabled(model.flashing)
            .onAppear { model.verifyFiles() }
    }
}
private struct FirmwareInstallerApp: App {
    @NSApplicationDelegateAdaptor(FirmwareAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("GMK104 Firmware Installer") { FirmwareView() }
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
@main private enum FirmwareEntry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty { FirmwareInstallerApp.main(); return }
        do {
            guard arguments == ["--dry-run"] || arguments == ["--inspect"] else {
                throw ControllerError.message("Use --dry-run for offline packet verification or --inspect for read-only USB inspection. Flashing requires the app's confirmation screen.")
            }
            for target in FirmwareTarget.allCases {
                let plan = try FirmwareModel.plan(target)
                print("PASS \(target.name): SHA256 \(plan.imageHash); stream \(plan.streamHash); \(plan.reports.count) reports")
            }
            if arguments == ["--inspect"] { print(try FirmwareInstaller.inspect().description); print("READ-ONLY INSPECTION PASSED. No OTA START was sent.") }
            else { print("OFFLINE DRY RUN PASSED. No HID device was enumerated or opened.") }
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
}
