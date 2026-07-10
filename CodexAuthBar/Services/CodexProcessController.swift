import AppKit
import CodexAuthCore
import Foundation

enum ProcessError: LocalizedError {
    case codexNotFound
    case commandFailed(String)
    case desktopDidNotTerminate
    case profileUnsupported

    var errorDescription: String? {
        switch self {
        case .codexNotFound: "Codex CLI was not found. Install it or choose its path in Settings."
        case let .commandFailed(message): "Codex command failed: \(message)"
        case .desktopDidNotTerminate: "Codex App did not terminate; the account was not changed."
        case .profileUnsupported: "This Codex CLI does not support --profile."
        }
    }
}

actor CodexProcessController: CodexProcessControlling {
    private let home: CodexHome
    init(home: CodexHome) { self.home = home }

    func capabilities() async throws -> CodexCapabilities {
        let executable = try resolveExecutable()
        let version = try run(executable, ["--version"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let help = try run(executable, ["--help"]).output
        return CodexCapabilities(executable: executable, version: version, supportsProfiles: help.contains("--profile"), supportsDoctorJSON: help.contains("doctor"))
    }

    func performLogin(_ method: LoginMethod) async throws -> LoginArtifact {
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
        _ = try run(executable, arguments, environment: environment, input: input)
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

    func terminateDesktopApp(timeout: Duration) async throws {
        let apps = await MainActor.run { NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex") }
        for app in apps { _ = await MainActor.run { app.terminate() } }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !(await isDesktopRunning()) { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw ProcessError.desktopDidNotTerminate
    }

    func launchDesktopApp(_ request: CodexLaunchRequest) async throws {
        var args = ["--env", "CODEX_HOME=\(request.codexHome.path)"]
        if let cliPath = request.cliPath { args += ["--env", "CODEX_CLI_PATH=\(cliPath.path)"] }
        args += ["-b", request.bundleIdentifier]
        _ = try run(URL(fileURLWithPath: "/usr/bin/open"), args)
    }

    func launchTerminal(profile: ProfileName) async throws {
        let capabilities = try await capabilities()
        let directory = FileManager.default.temporaryDirectory.appending(path: "CodexAuthBar", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appending(path: "launch-\(UUID().uuidString).command")
        try TerminalCommandBuilder.script(codex: capabilities.executable, profile: profile).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        _ = try run(URL(fileURLWithPath: "/usr/bin/open"), [script.path])
    }

    private func resolveExecutable() throws -> URL {
        var candidates: [URL] = []
        if let explicit = UserDefaults.standard.string(forKey: "codexCLIPath") { candidates.append(URL(fileURLWithPath: explicit)) }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            candidates.append(app.appending(path: "Contents/Resources/codex"))
        }
        candidates += ["~/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"].map {
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

    private func redact(_ text: String) -> String {
        text.replacingOccurrences(of: #"eyJ[A-Za-z0-9._-]+"#, with: "<redacted-token>", options: .regularExpression)
            .replacingOccurrences(of: #"sk-[A-Za-z0-9_-]+"#, with: "<redacted-key>", options: .regularExpression)
    }
}

private enum SecureDirectory {
    static func create(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}
