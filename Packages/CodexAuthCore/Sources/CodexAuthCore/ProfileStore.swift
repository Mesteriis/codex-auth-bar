import Foundation

public enum ProfileError: Error, Equatable, Sendable { case alreadyExists, notFound }

public actor ProfileStore {
    public let home: CodexHome
    public init(home: CodexHome) { self.home = home }

    public func list() throws -> [ProfileName] {
        guard FileManager.default.fileExists(atPath: home.root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: home.root, includingPropertiesForKeys: nil)
            .compactMap { url -> ProfileName? in
                let suffix = ".config.toml"
                guard url.lastPathComponent.hasSuffix(suffix) else { return nil }
                return ProfileName(String(url.lastPathComponent.dropLast(suffix.count)))
            }
            .sorted { $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending }
    }

    public func create(_ name: ProfileName) throws {
        try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
        let url = profileURL(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw ProfileError.alreadyExists }
        try SecureFiles.atomicWrite(Data(), to: url)
    }

    public func rename(_ old: ProfileName, to new: ProfileName) throws {
        let source = profileURL(old)
        let destination = profileURL(new)
        guard FileManager.default.fileExists(atPath: source.path) else { throw ProfileError.notFound }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ProfileError.alreadyExists }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func delete(_ name: ProfileName) throws {
        let url = profileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProfileError.notFound }
        try FileManager.default.removeItem(at: url)
    }

    public func profileURL(_ name: ProfileName) -> URL { home.root.appending(path: "\(name.rawValue).config.toml") }
}

public enum TerminalCommandBuilder {
    public static func command(codex: URL, profile: ProfileName) -> String {
        "\(shellQuote(codex.path)) --profile \(shellQuote(profile.rawValue))"
    }

    public static func script(codex: URL, profile: ProfileName) -> String {
        "#!/bin/zsh\nself=$0\nrm -f -- \"$self\"\nexec \(command(codex: codex, profile: profile))\n"
    }

    private static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
