import Darwin
import Foundation

public struct RegistrySnapshot: Sendable {
    public var registry: RegistryV4
    public var fingerprint: FileFingerprint

    public init(registry: RegistryV4, fingerprint: FileFingerprint) {
        self.registry = registry
        self.fingerprint = fingerprint
    }
}

public enum RecoveryResult: Equatable, Sendable {
    case nothingToRecover
    case journalRemoved
    case registryReconciled
    case manualInterventionRequired
}

private struct TransactionJournal: Codable, Sendable {
    var targetAccountKey: AccountKey
    var previousAccountKey: AccountKey?
    var targetAuthSHA256: String
    var stage: String
}

public actor RegistryStore {
    public let home: CodexHome

    public init(home: CodexHome) { self.home = home }

    public func load() throws -> RegistrySnapshot {
        try SecureFiles.ensurePrivateDirectory(home.accounts)
        guard FileManager.default.fileExists(atPath: home.registry.path) else {
            return RegistrySnapshot(registry: RegistryV4(), fingerprint: .missing)
        }
        let data = try Data(contentsOf: home.registry)
        return RegistrySnapshot(registry: try RegistryCodec.decode(data), fingerprint: try SecureFiles.fingerprint(home.registry))
    }

    @discardableResult
    public func commit(_ registry: RegistryV4, expected: FileFingerprint) throws -> FileFingerprint {
        try withLock {
            let current = try SecureFiles.fingerprint(home.registry)
            guard current == expected else { throw StorageError.concurrentModification }
            let data = try RegistryCodec.encode(registry)
            _ = try SecureFiles.backupIfChanged(current: home.registry, replacement: data, directory: home.accounts, baseName: "registry.json")
            try SecureFiles.atomicWrite(data, to: home.registry)
            return try SecureFiles.fingerprint(home.registry)
        }
    }

    public func writeJournal(target: AccountKey, previous: AccountKey?, targetAuthSHA256: String, stage: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(TransactionJournal(
            targetAccountKey: target,
            previousAccountKey: previous,
            targetAuthSHA256: targetAuthSHA256,
            stage: stage
        ))
        try SecureFiles.atomicWrite(data, to: home.transactionJournal)
    }

    public func removeJournal() throws {
        if FileManager.default.fileExists(atPath: home.transactionJournal.path) {
            try FileManager.default.removeItem(at: home.transactionJournal)
        }
    }

    public func recoverPendingTransaction() throws -> RecoveryResult {
        guard FileManager.default.fileExists(atPath: home.transactionJournal.path) else { return .nothingToRecover }
        let journal = try JSONDecoder().decode(TransactionJournal.self, from: Data(contentsOf: home.transactionJournal))
        guard FileManager.default.fileExists(atPath: home.auth.path),
              FileManager.default.fileExists(atPath: home.snapshot(for: journal.targetAccountKey).path)
        else { return .manualInterventionRequired }
        let active = try SecureFiles.fingerprint(home.auth)
        let target = try SecureFiles.fingerprint(home.snapshot(for: journal.targetAccountKey))
        guard active.sha256 == target.sha256 else { return .manualInterventionRequired }
        var loaded = try load()
        if loaded.registry.activeAccountKey != journal.targetAccountKey {
            loaded.registry.previousActiveAccountKey = journal.previousAccountKey
            loaded.registry.activeAccountKey = journal.targetAccountKey
            loaded.registry.activeAccountActivatedAtMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
            _ = try commit(loaded.registry, expected: loaded.fingerprint)
            try removeJournal()
            return .registryReconciled
        }
        try removeJournal()
        return .journalRemoved
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try SecureFiles.ensurePrivateDirectory(home.accounts)
        let descriptor = open(home.lock.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw StorageError.cannotOpen(home.lock.path) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw StorageError.cannotOpen(home.lock.path) }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
}
