import CodexAuthCore
import Foundation

actor CodextManager {
    static let version = "codext-v0.144.1-a8c9398"

    private var artifact: CodextArtifact {
        #if arch(arm64)
        CodextArtifact(
            architecture: .arm64,
            url: URL(string: "https://github.com/Loongphy/codext/releases/download/codext-v0.144.1-a8c9398/codext-darwin-arm64-0.144.1-a8c9398.tar.gz")!,
            sha256: "bd6e06cc9093994af1f3c59943a2423199d998b0c304c6836022a22ce860df82",
            size: 140_116_278
        )
        #else
        CodextArtifact(
            architecture: .x64,
            url: URL(string: "https://github.com/Loongphy/codext/releases/download/codext-v0.144.1-a8c9398/codext-darwin-x64-0.144.1-a8c9398.tar.gz")!,
            sha256: "f57b2050e2e5ce89367c2bc9bfbcb04062979014e722f27fe746424fd975e8ea",
            size: 146_668_708
        )
        #endif
    }

    func installedCLI() async throws -> URL {
        if let custom = UserDefaults.standard.string(forKey: "codextPath"), FileManager.default.isExecutableFile(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        let base = try applicationSupport().appending(path: "codext/\(Self.version)", directoryHint: .isDirectory)
        let executable = base.appending(path: "codext")
        if FileManager.default.isExecutableFile(atPath: executable.path) { return executable }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let archive = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".tar.gz")
        defer { try? FileManager.default.removeItem(at: archive) }
        let (downloaded, response) = try await URLSession.shared.download(from: artifact.url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw CodextError.untrustedOrigin }
        try FileManager.default.moveItem(at: downloaded, to: archive)
        try CodextVerifier.verify(file: archive, artifact: artifact)
        let entries = try run("/usr/bin/tar", ["-tzf", archive.path]).split(separator: "\n").map(String.init)
        guard Set(entries) == Set(["codext", "codex-code-mode-host"]), entries.allSatisfy({ !$0.contains("..") && !$0.hasPrefix("/") }) else {
            throw CodextError.unsafeArchive
        }
        _ = try run("/usr/bin/tar", ["-xzf", archive.path, "-C", base.path])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.appending(path: "codex-code-mode-host").path)
        return executable
    }

    private func applicationSupport() throws -> URL {
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "CodexAuthBar", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(); let output = Pipe(); let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = error
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CodextError.unsafeArchive }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
