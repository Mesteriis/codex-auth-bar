import CryptoKit
import Foundation

public enum RefreshPolicy: Sendable {
    case stored
    case activeLocal
    case activeRemote
    case allRemote
}

public struct AccountState: Sendable {
    public var registry: RegistryV4
    public init(registry: RegistryV4) { self.registry = registry }
}

public struct SwitchReceipt: Equatable, Sendable {
    public var selectedAccountKey: AccountKey
    public var previousAccountKey: AccountKey?
    public var backupURL: URL?
}

public struct CleanReport: Equatable, Sendable {
    public var deletedFiles: [String]
    public init(deletedFiles: [String]) { self.deletedFiles = deletedFiles }
}

public enum AccountError: Error, Equatable, Sendable {
    case accountNotFound
    case snapshotMissing
    case noPreviousAccount
    case invalidAlias
    case duplicateAlias
    case concurrentModification
}

public actor AccountRepository {
    public let home: CodexHome
    let store: RegistryStore

    public init(home: CodexHome, store: RegistryStore? = nil) {
        self.home = home
        self.store = store ?? RegistryStore(home: home)
    }

    public func state(refresh: RefreshPolicy) async throws -> AccountState {
        AccountState(registry: try await store.load().registry)
    }

    public func switchAccount(to key: AccountKey) async throws -> SwitchReceipt {
        let loaded = try await store.load()
        guard let index = loaded.registry.accounts.firstIndex(where: { $0.accountKey == key }) else {
            throw AccountError.accountNotFound
        }
        let snapshotURL = home.snapshot(for: key)
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { throw AccountError.snapshotMissing }
        let targetData = try Data(contentsOf: snapshotURL)
        let targetHash = SHA256.hash(data: targetData).map { String(format: "%02x", $0) }.joined()
        let previous = loaded.registry.activeAccountKey
        try await store.writeJournal(target: key, previous: previous, targetAuthSHA256: targetHash, stage: "prepared")

        let backup = try SecureFiles.backupIfChanged(current: home.auth, replacement: targetData, directory: home.accounts, baseName: "auth.json")
        try SecureFiles.copyPreservingDestinationMode(targetData, to: home.auth)
        try await store.writeJournal(target: key, previous: previous, targetAuthSHA256: targetHash, stage: "auth_replaced")

        var registry = loaded.registry
        if registry.activeAccountKey != key {
            registry.previousActiveAccountKey = registry.activeAccountKey
        }
        registry.activeAccountKey = key
        registry.activeAccountActivatedAtMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
        registry.accounts[index].lastUsedAt = Int64(Date().timeIntervalSince1970)
        do {
            _ = try await store.commit(registry, expected: loaded.fingerprint)
        } catch StorageError.concurrentModification {
            throw AccountError.concurrentModification
        }
        try await store.removeJournal()
        return SwitchReceipt(selectedAccountKey: key, previousAccountKey: previous, backupURL: backup)
    }

    public func switchToPrevious() async throws -> SwitchReceipt {
        let loaded = try await store.load()
        guard let previous = loaded.registry.previousActiveAccountKey,
              loaded.registry.accounts.contains(where: { $0.accountKey == previous })
        else { throw AccountError.noPreviousAccount }
        return try await switchAccount(to: previous)
    }

    public func setAlias(_ alias: String?, for key: AccountKey) async throws {
        let value = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !value.isEmpty {
            guard !value.allSatisfy(\.isNumber), !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw AccountError.invalidAlias
            }
        }
        for _ in 0..<3 {
            let loaded = try await store.load()
            guard let index = loaded.registry.accounts.firstIndex(where: { $0.accountKey == key }) else {
                throw AccountError.accountNotFound
            }
            if loaded.registry.accounts.contains(where: {
                $0.accountKey != key && !$0.alias.isEmpty && $0.alias.caseInsensitiveCompare(value) == .orderedSame
            }) { throw AccountError.duplicateAlias }
            var registry = loaded.registry
            registry.accounts[index].alias = value
            do {
                _ = try await store.commit(registry, expected: loaded.fingerprint)
                return
            } catch StorageError.concurrentModification {
                continue
            }
        }
        throw AccountError.concurrentModification
    }

    public func clean() async throws -> CleanReport {
        let loaded = try await store.load()
        let allowed = Set(loaded.registry.accounts.map { CodexHome.snapshotFileName(for: $0.accountKey) })
        var deleted: [String] = []
        let entries = try FileManager.default.contentsOfDirectory(at: home.accounts, includingPropertiesForKeys: nil)
        for entry in entries {
            let name = entry.lastPathComponent
            if entry == home.exportBackup || name == "registry.json" || name.hasPrefix(".codex-auth-bar") { continue }
            if name.hasSuffix(".auth.json"), !allowed.contains(name) {
                try FileManager.default.removeItem(at: entry)
                deleted.append(name)
            }
        }
        try SecureFiles.pruneBackups(in: home.accounts, baseName: "auth.json", keeping: 5)
        try SecureFiles.pruneBackups(in: home.accounts, baseName: "registry.json", keeping: 5)
        return CleanReport(deletedFiles: deleted.sorted())
    }

    public func updateUsage(_ snapshot: RateLimitSnapshot, for key: AccountKey) async throws {
        for _ in 0..<3 {
            let loaded = try await store.load()
            guard let index = loaded.registry.accounts.firstIndex(where: { $0.accountKey == key }) else { throw AccountError.accountNotFound }
            var registry = loaded.registry
            registry.accounts[index].lastUsage = snapshot
            registry.accounts[index].lastUsageAt = Int64(Date().timeIntervalSince1970)
            do {
                _ = try await store.commit(registry, expected: loaded.fingerprint)
                return
            } catch StorageError.concurrentModification { continue }
        }
        throw AccountError.concurrentModification
    }
}
