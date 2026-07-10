import Foundation

public struct CodexHome: Hashable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public static func resolve(
        preference: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> CodexHome {
        if let preference { return CodexHome(root: preference) }
        if let override = environment["CODEX_HOME"], !override.isEmpty {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: override, isDirectory: &isDirectory), isDirectory.boolValue {
                return CodexHome(root: URL(fileURLWithPath: override, isDirectory: true))
            }
        }
        return CodexHome(root: fileManager.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory))
    }

    public var auth: URL { root.appending(path: "auth.json") }
    public var accounts: URL { root.appending(path: "accounts", directoryHint: .isDirectory) }
    public var registry: URL { accounts.appending(path: "registry.json") }
    public var exportBackup: URL { accounts.appending(path: "backup", directoryHint: .isDirectory) }
    public var lock: URL { accounts.appending(path: ".codex-auth-bar.lock") }
    public var transactionJournal: URL { accounts.appending(path: ".codex-auth-bar.transaction.json") }

    public func snapshot(for key: AccountKey) -> URL {
        accounts.appending(path: Self.snapshotFileName(for: key))
    }

    public static func snapshotFileName(for key: AccountKey) -> String {
        let value = key.rawValue
        let safe = value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) ||
            (byte >= 65 && byte <= 90) ||
            (byte >= 97 && byte <= 122) ||
            byte == 45 || byte == 95 || byte == 46
        }
        if safe { return value + ".auth.json" }
        let encoded = Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return encoded + ".auth.json"
    }
}
