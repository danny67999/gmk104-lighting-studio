import Foundation
import Security
import Darwin

/// The elevated process accepts only a fixed firmware operation. No executable,
/// image path, output path, shell text or arbitrary HID command crosses this boundary.
struct FirmwareOperation: Codable {
    enum Action: String, Codable { case inspect, install }
    let action: Action
    let nonce: UUID
    let target: FirmwareTarget?
    let expected: FirmwareDeviceState?
    let confirmation: String?

    func validated() throws -> Self {
        if action == .inspect {
            try require(target == nil && expected == nil && confirmation == nil, "Invalid inspection request.")
        } else {
            guard let target, let expected else { throw ControllerError.message("Missing firmware installation identity.") }
            #if GMK104_V08_LOCAL_TEST
            try require((target == .storageSurvey && expected.crc == FirmwareTarget.onboardProfilePreview.crc) ||
                        (target == .onboardProfilePreview && expected.crc == FirmwareTarget.storageSurvey.crc),
                        "The v0.8 trial accepts only v0.7 to v0.8 or v0.8 to v0.7. Nothing was flashed.")
            #elseif GMK104_V07_LOCAL_TEST
            try require((target == .onboardProfilePreview && expected.crc == FirmwareTarget.nativeRippleFixed.crc) ||
                        (target == .nativeRippleFixed && expected.crc == FirmwareTarget.onboardProfilePreview.crc),
                        "The local trial app accepts only v0.6 to v0.7 or v0.7 to v0.6. Nothing was flashed.")
            #endif
            try require(confirmation == target.phrase && target.accepts(source: expected.crc), "The firmware request is not an approved transition.")
            try require(expected.otaID != 0 && expected.viaID != 0 && expected.usbID != 0 && expected.location != 0,
                        "The keyboard attachment identity is missing.")
        }
        return self
    }
    func encoded() throws -> String { try JSONEncoder().encode(validated()).base64EncodedString() }
    static func decode(_ value: String) throws -> Self {
        try require(value.utf8.count <= 4096, "Firmware request is too large.")
        guard let data = Data(base64Encoded: value) else { throw ControllerError.message("Invalid firmware request encoding.") }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
}

struct FirmwareOperationEvent: Codable {
    enum Kind: String, Codable { case log, progress, result, error, logFile }
    let nonce: UUID
    let kind: Kind
    let message: String
    var progress: Double?
    var state: FirmwareDeviceState?

    func validate(for operation: FirmwareOperation) throws {
        try require(nonce == operation.nonce && message.utf8.count <= 2048, "The installer received an invalid helper response.")
        if let progress { try require(progress.isFinite && (0...1).contains(progress), "Invalid installation progress.") }
        if kind == .result {
            guard let state else { throw ControllerError.message("The helper did not verify the keyboard after reboot.") }
            try require((FirmwareTarget.allCases.map(\.crc) + [0xC077F2F5, 0xD79CC2E1]).contains(state.crc), "Unapproved firmware result.")
            if operation.action == .install {
                try require(state.crc == operation.target?.crc && state.location == operation.expected?.location,
                            "Firmware or USB port did not match the approved installation.")
            }
        }
        if kind == .logFile {
            try require(message == FirmwareOperationLog.path(for: operation.nonce), "Unexpected installation log location.")
        }
    }
}

/// Logs survive a UI crash. Only the helper writes this root-owned directory;
/// paths are fixed and every final component is opened without following links.
final class FirmwareOperationLog {
    private let fd: Int32
    private let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static func path(for nonce: UUID) -> String { "/Library/Logs/GMK104/Firmware-\(nonce.uuidString).log" }
    init(nonce: UUID) throws {
        let parent = open("/Library/Logs", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        try require(parent >= 0, "Cannot open the system log directory. Nothing was flashed.")
        defer { close(parent) }
        if mkdirat(parent, "GMK104", 0o755) != 0 {
            try require(errno == EEXIST, "Cannot create the firmware log directory. Nothing was flashed.")
        }
        let directory = openat(parent, "GMK104", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        try require(directory >= 0, "The firmware log directory is unavailable. Nothing was flashed.")
        defer { close(directory) }
        var info = stat()
        try require(fstat(directory, &info) == 0 && info.st_uid == 0 && (info.st_mode & 0o022) == 0,
                    "The firmware log directory is not protected. Nothing was flashed.")
        fd = openat(directory, "Firmware-\(nonce.uuidString).log", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        try require(fd >= 0, "Cannot create a new firmware log. Nothing was flashed.")
    }
    deinit { fsync(fd); close(fd) }
    @discardableResult func append(_ message: String) -> Bool {
        let data = Data("\(timestamp.string(from: Date())) \(message)\n".utf8)
        let written = data.withUnsafeBytes { bytes in Darwin.write(fd, bytes.baseAddress, bytes.count) }
        if message.contains("START") || message.contains("END") || message.contains("STOPPED") || message.contains("VERIFIED") { fsync(fd) }
        return written == data.count
    }
}

enum FirmwareAuthorizedHelper {
    /// Entry point in the same signed executable, before AppKit starts. The OS
    /// authorization service launches it once; it installs no daemon or login item.
    static func run(encoded: String) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        var operation: FirmwareOperation?
        var log: FirmwareOperationLog?
        func emit(_ event: FirmwareOperationEvent) -> Bool {
            guard let data = try? JSONEncoder().encode(event) else { return false }
            do { try FileHandle.standardOutput.write(contentsOf: data + Data([10])); return true }
            catch { return false }
        }
        do {
            let request = try FirmwareOperation.decode(encoded); operation = request
            try require(geteuid() == 0, "Administrator approval is required. Open the firmware installer app.")
            let file = try FirmwareOperationLog(nonce: request.nonce); log = file
            try require(file.append("HELPER START action=\(request.action.rawValue)"), "Cannot write the firmware log. Nothing was flashed.")
            try require(emit(.init(nonce: request.nonce, kind: .logFile, message: FirmwareOperationLog.path(for: request.nonce))),
                        "The installer window disconnected before installation. Nothing was flashed.")
            let result: FirmwareDeviceState
            if request.action == .inspect {
                result = try FirmwareInstaller.inspect(exclusive: true)
            } else {
                let target = request.target!, expected = request.expected!
                guard let resource = Bundle.main.resourceURL?.appendingPathComponent(target.file) else {
                    throw ControllerError.message("The bundled firmware is missing.")
                }
                let plan = try FirmwarePlan(target: target, data: Data(contentsOf: resource))
                result = try FirmwareInstaller.install(plan: plan, expected: expected, confirmation: request.confirmation!, log: { message in
                    file.append(message)
                    _ = emit(.init(nonce: request.nonce, kind: .log, message: message))
                }, progress: { value, message in
                    _ = emit(.init(nonce: request.nonce, kind: .progress, message: message, progress: value))
                })
            }
            file.append("VERIFIED \(result.description)")
            _ = emit(.init(nonce: request.nonce, kind: .result, message: result.description, state: result))
            return 0
        } catch {
            log?.append("STOPPED: \(error.localizedDescription)")
            if let operation { _ = emit(.init(nonce: operation.nonce, kind: .error, message: error.localizedDescription)) }
            else { fputs("Invalid firmware helper request. Nothing was flashed.\n", stderr) }
            return 1
        }
    }
}

enum FirmwareAdministrator {
    /// This unsigned beta uses the documented one-shot Authorization Services
    /// launcher, which still works on supported Macs. It is deprecated: migrate
    /// to SMAppService with matching Apple-issued signing identities for release.
    /// Never substitute a shell, sudo command or a caller-provided executable.
    static func perform(_ operation: FirmwareOperation,
                        receive: @escaping (FirmwareOperationEvent) -> Void) throws -> FirmwareDeviceState {
        _ = try operation.validated()
        guard let executable = Bundle.main.executableURL else { throw ControllerError.message("The installer executable is missing.") }
        var staticCode: SecStaticCode?
        try require(SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
                    "Cannot verify the installed app. Download a fresh copy.")
        try require(SecStaticCodeCheckValidity(staticCode!, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
                    "The installer’s signature is invalid. Download a fresh copy.")
        var authorization: AuthorizationRef?
        try require(AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess,
                    "macOS could not prepare administrator approval. Nothing was flashed.")
        guard let authorization else { throw ControllerError.message("Administrator approval is unavailable.") }
        defer { AuthorizationFree(authorization, [.destroyRights]) }
        let approval = kAuthorizationRightExecute.withCString { name -> OSStatus in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { items in
                var rights = AuthorizationRights(count: 1, items: items)
                return AuthorizationCopyRights(authorization, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
            }
        }
        if approval == errAuthorizationCanceled || approval == errAuthorizationDenied {
            throw ControllerError.message("Administrator approval was cancelled or denied. Nothing was flashed.")
        }
        try require(approval == errAuthorizationSuccess, "macOS administrator approval failed (\(approval)). Nothing was flashed.")
        var arguments = [strdup("--authorized-operation"), strdup(try operation.encoded()), nil]
        defer { arguments.forEach { free($0) } }
        var pipe: UnsafeMutablePointer<FILE>?
        let started = arguments.withUnsafeMutableBufferPointer { args in
            executable.path.withCString { path in
                GMKRunAuthorizedTool(authorization, path, args.baseAddress!, &pipe)
            }
        }
        try require(started == errAuthorizationSuccess && pipe != nil,
                    "macOS could not start the firmware helper (\(started)). Nothing was flashed.")
        guard let pipe else { throw ControllerError.message("The firmware helper connection is missing.") }
        defer { fclose(pipe) }
        let fd = fileno(pipe)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let deadline = ProcessInfo.processInfo.systemUptime + 15 * 60
        var buffered = Data(), result: FirmwareDeviceState?, helperError: String?
        var buffer = [UInt8](repeating: 0, count: 8192)
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let available = poll(&descriptor, 1, 1000)
            if available < 0 && errno == EINTR { continue }
            try require(available >= 0, "Lost the firmware helper connection. Inspect the keyboard before retrying.")
            if available == 0 { continue }
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw ControllerError.message("Lost the firmware helper connection. Inspect before retrying.")
            }
            buffered.append(contentsOf: buffer.prefix(count))
            while let newline = buffered.firstIndex(of: 10) {
                let line = Data(buffered[..<newline]); buffered.removeSubrange(...newline)
                try require(line.count <= 4096, "The helper response was too large. Inspect before retrying.")
                let event = try JSONDecoder().decode(FirmwareOperationEvent.self, from: line)
                try event.validate(for: operation)
                receive(event)
                if event.kind == .result { result = event.state }
                if event.kind == .error { helperError = event.message }
            }
            try require(buffered.count <= 4096, "Invalid helper response. Inspect before retrying.")
        }
        if let helperError { throw ControllerError.message(helperError) }
        guard let result, buffered.isEmpty else {
            throw ControllerError.message("The helper did not return a verified result. Keep USB connected, check the installation log, and inspect before retrying.")
        }
        return result
    }
}
