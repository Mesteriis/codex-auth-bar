import AppKit
import CodexAuthCore
import Darwin
import Foundation

enum ProcessError: LocalizedError {
    case codexNotFound
    case commandFailed(String)
    case desktopDidNotTerminate
    case profileUnsupported
    case incompatibleCredentialStore(CredentialStoreMode)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: "Codex CLI was not found. Install it or choose its path in Settings."
        case let .commandFailed(message): "Codex command failed: \(message)"
        case .desktopDidNotTerminate: "Codex App did not terminate; the account was not changed."
        case .profileUnsupported: "This Codex CLI does not support --profile."
        case let .incompatibleCredentialStore(mode):
            "Codex credential storage is \(mode.rawValue). Set cli_auth_credentials_store = \"file\" at the top level of config.toml before switching accounts. Codex Auth Bar will not change this setting automatically."
        }
    }
}

struct DiagnosticsArtifact: Sendable {
    var identifier: UUID
    var processIdentifier: pid_t
}

actor CodexProcessController: CodexProcessControlling {
    private let home: CodexHome
    private var managedDesktopPID: pid_t?
    private var diagnosticsProcess: Process?
    private var diagnosticsBuffers: [UUID: DiagnosticsBuffer] = [:]
    private var loginProcess: Process?
    private let explicitExecutable: URL?

    init(home: CodexHome, explicitExecutable: URL? = nil) {
        self.home = home
        self.explicitExecutable = explicitExecutable
    }

    func capabilities() async throws -> CodexCapabilities {
        let executable = try resolveExecutable()
        let version = try run(executable, ["--version"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let help = try run(executable, ["--help"]).output
        let supportsDoctor = help.contains("doctor")
        var credentialStore: CredentialStoreMode = .unknown
        if supportsDoctor {
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = home.root.path
            if let report = try? run(executable, ["doctor", "--json"], environment: environment).output {
                credentialStore = (try? DoctorReportParser.credentialStore(from: Data(report.utf8))) ?? .unknown
            }
        }
        if credentialStore == .unknown {
            let config = home.root.appending(path: "config.toml")
            if let contents = try? String(contentsOf: config, encoding: .utf8) {
                credentialStore = CredentialStoreConfigParser.mode(in: contents)
            }
        }
        return CodexCapabilities(
            executable: executable,
            version: version,
            supportsProfiles: help.contains("--profile"),
            supportsDoctorJSON: supportsDoctor,
            credentialStore: credentialStore
        )
    }

    func ensureFileCredentialStore() async throws {
        let result = try await capabilities()
        if result.credentialStore == .unknown, !result.supportsDoctorJSON {
            return
        }
        guard result.credentialStore.permitsFileSwitching else {
            throw ProcessError.incompatibleCredentialStore(result.credentialStore)
        }
    }

    func performLogin(_ method: LoginMethod) async throws -> LoginArtifact {
        try await performLogin(method, onOutput: { _ in })
    }

    func performLogin(_ method: LoginMethod, onOutput: @escaping @Sendable (String) -> Void) async throws -> LoginArtifact {
        let executable = try resolveExecutable()
        try SecureDirectory.create(home.accounts)
        let scratch = home.accounts.appending(path: "login-\(UUID().uuidString)", directoryHint: .isDirectory)
        try SecureDirectory.create(scratch)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let config = home.root.appending(path: "config.toml")
        if FileManager.default.fileExists(atPath: config.path) { try? FileManager.default.copyItem(at: config, to: scratch.appending(path: "config.toml")) }
        var arguments = ["-c", "cli_auth_credentials_store=\"file\"", "login"]
        var input: Data?
        switch method {
        case .browser: break
        case .deviceCode: arguments.append("--device-auth")
        case let .apiKey(key): arguments.append("--with-api-key"); input = Data((key + "\n").utf8)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = scratch.path
        try await runLogin(
            executable,
            arguments,
            environment: environment,
            input: input,
            onOutput: onOutput
        )
        let auth = scratch.appending(path: "auth.json")
        guard FileManager.default.fileExists(atPath: auth.path) else { throw ProcessError.commandFailed("login produced no auth.json") }
        let artifacts = FileManager.default.temporaryDirectory.appending(path: "CodexAuthBar/LoginArtifacts", directoryHint: .isDirectory)
        try SecureDirectory.create(artifacts)
        let artifact = artifacts.appending(path: "\(UUID().uuidString).auth.json")
        try FileManager.default.copyItem(at: auth, to: artifact)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: artifact.path)
        return LoginArtifact(authURL: artifact)
    }

    func isDesktopRunning() async -> Bool {
        await MainActor.run { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty }
    }

    func isManagedDesktopRunning() async -> Bool {
        guard let managedDesktopPID else { return false }
        return await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
                .contains(where: { $0.processIdentifier == managedDesktopPID })
        }
    }

    func terminateDesktopApp(timeout: Duration) async throws {
        let apps = await MainActor.run { NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex") }
        for app in apps { _ = await MainActor.run { app.terminate() } }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !(await isDesktopRunning()) { managedDesktopPID = nil; return }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw ProcessError.desktopDidNotTerminate
    }

    func launchDesktopApp(_ request: CodexLaunchRequest) async throws {
        var args = ["--env", "CODEX_HOME=\(request.codexHome.path)"]
        if let cliPath = request.cliPath { args += ["--env", "CODEX_CLI_PATH=\(cliPath.path)"] }
        args += ["-b", request.bundleIdentifier]
        _ = try run(URL(fileURLWithPath: "/usr/bin/open"), args)
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let pid = await MainActor.run {
                NSRunningApplication.runningApplications(withBundleIdentifier: request.bundleIdentifier).first?.processIdentifier
            }
            if let pid {
                managedDesktopPID = request.cliPath == nil ? nil : pid
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ProcessError.commandFailed("Codex.app did not start")
    }

    func cancelLogin() {
        loginProcess?.terminate()
    }

    func launchDiagnostics(cliPath: URL?) async throws -> DiagnosticsArtifact {
        guard let appURL = await MainActor.run(body: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") }),
              let executable = Bundle(url: appURL)?.executableURL
        else { throw ProcessError.commandFailed("Codex.app was not found") }
        let identifier = UUID()
        let buffer = DiagnosticsBuffer()
        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.root.path
        if let cliPath { environment["CODEX_CLI_PATH"] = cliPath.path }
        process.environment = environment
        process.standardOutput = buffer.stdout
        process.standardError = buffer.stderr
        buffer.startReading()
        try process.run()
        diagnosticsProcess = process
        diagnosticsBuffers[identifier] = buffer
        managedDesktopPID = cliPath == nil ? nil : process.processIdentifier
        return DiagnosticsArtifact(identifier: identifier, processIdentifier: process.processIdentifier)
    }

    func diagnosticOutput(_ artifact: DiagnosticsArtifact) throws -> String {
        guard let buffer = diagnosticsBuffers[artifact.identifier] else { return "Diagnostics session ended." }
        let (stdout, stderr) = buffer.snapshot()
        return redact("STDOUT\n\(stdout)\n\nSTDERR\n\(stderr)")
    }

    func finishDiagnostics(_ artifact: DiagnosticsArtifact) -> String {
        let output = (try? diagnosticOutput(artifact)) ?? "Diagnostics session ended."
        diagnosticsBuffers.removeValue(forKey: artifact.identifier)?.stopReading()
        if diagnosticsProcess?.processIdentifier == artifact.processIdentifier { diagnosticsProcess = nil }
        return output
    }

    func diagnosticsAreRunning(_ artifact: DiagnosticsArtifact) -> Bool {
        diagnosticsProcess?.processIdentifier == artifact.processIdentifier && diagnosticsProcess?.isRunning == true
    }

    func launchTerminal(profile: ProfileName) async throws {
        let capabilities = try await capabilities()
        let directory = FileManager.default.temporaryDirectory.appending(path: "CodexAuthBar", directoryHint: .isDirectory)
        try SecureDirectory.create(directory)
        let script = directory.appending(path: "launch-\(UUID().uuidString).command")
        try TerminalCommandBuilder.script(codex: capabilities.executable, profile: profile).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        _ = try run(URL(fileURLWithPath: "/usr/bin/open"), [script.path])
    }

    private func resolveExecutable() throws -> URL {
        var candidates: [URL] = []
        if let explicitExecutable { candidates.append(explicitExecutable) }
        if let explicit = UserDefaults.standard.string(forKey: "codexCLIPath"), !explicit.isEmpty {
            candidates.append(URL(fileURLWithPath: explicit))
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            candidates.append(app.appending(path: "Contents/Resources/codex"))
        }
        candidates += [
            "~/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js",
            "/usr/local/lib/node_modules/@openai/codex/bin/codex.js",
        ].map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { URL(fileURLWithPath: String($0)).appending(path: "codex") }
        }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw ProcessError.codexNotFound }
        return found
    }

    private func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil, input: Data? = nil) throws -> (output: String, error: String) {
        let process = Process()
        let stdout = Pipe(); let stderr = Pipe(); let stdin = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = stdout; process.standardError = stderr
        if let environment { process.environment = environment }
        if input != nil { process.standardInput = stdin }
        try process.run()
        if let input { stdin.fileHandleForWriting.write(input); try? stdin.fileHandleForWriting.close() }
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw ProcessError.commandFailed(redact(error)) }
        return (output, error)
    }

    private func runLogin(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        input: Data?,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        let buffer = DiagnosticsBuffer(maximumBytes: 128 * 1024)
        let process = Process()
        let stdin = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = buffer.stdout
        process.standardError = buffer.stderr
        if input != nil { process.standardInput = stdin }
        buffer.startReading()
        defer { buffer.stopReading() }
        try process.run()
        loginProcess = process
        defer { loginProcess = nil }
        if let input {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }
        while process.isRunning {
            let (stdout, stderr) = buffer.snapshot()
            let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            if !output.isEmpty { onOutput(redact(output)) }
            try await Task.sleep(for: .milliseconds(250))
        }
        process.waitUntilExit()
        let (stdout, stderr) = buffer.snapshot()
        let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        onOutput(redact(output))
        guard process.terminationStatus == 0 else { throw ProcessError.commandFailed(redact(output)) }
    }

    private func redact(_ text: String) -> String {
        SecretRedactor.redact(text)
    }

}

private final class DiagnosticsBuffer: @unchecked Sendable {
    let stdout = Pipe()
    let stderr = Pipe()
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private let maximumBytes: Int

    init(maximumBytes: Int = 512 * 1024) {
        self.maximumBytes = maximumBytes
    }

    func startReading() {
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, toStandardError: false)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, toStandardError: true)
        }
    }

    func stopReading() {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        try? stdout.fileHandleForReading.close()
        try? stderr.fileHandleForReading.close()
    }

    func snapshot() -> (String, String) {
        lock.lock()
        defer { lock.unlock() }
        return (String(decoding: stdoutData, as: UTF8.self), String(decoding: stderrData, as: UTF8.self))
    }

    private func append(_ data: Data, toStandardError: Bool) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if toStandardError {
            stderrData.append(data)
            if stderrData.count > maximumBytes { stderrData.removeFirst(stderrData.count - maximumBytes) }
        } else {
            stdoutData.append(data)
            if stdoutData.count > maximumBytes { stdoutData.removeFirst(stdoutData.count - maximumBytes) }
        }
    }
}

private enum SecureDirectory {
    static func create(_ url: URL) throws {
        var status = stat()
        if lstat(url.path, &status) != 0 {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard lstat(url.path, &status) == 0 else { throw ProcessError.commandFailed("Cannot secure \(url.path)") }
        }
        guard (status.st_mode & S_IFMT) == S_IFDIR, chmod(url.path, 0o700) == 0 else {
            throw ProcessError.commandFailed("Unsafe directory: \(url.path)")
        }
    }
}
