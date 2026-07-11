import Darwin
import Foundation

public struct RegistrySnapshot: Codable, Equatable, Sendable {
    public var registry: RegistryV4
    public var fingerprint: FileFingerprint

    public init(registry: RegistryV4, fingerprint: FileFingerprint) {
        self.registry = registry
        self.fingerprint = fingerprint
    }
}

public enum RecoveryResult: String, Codable, Equatable, Sendable {
    case nothingToRecover
    case journalRemoved
    case registryReconciled
    case manualInterventionRequired
}

private struct TransactionJournal: Codable, Sendable {
    var targetAccountKey: AccountKey
    var previousAccountKey: AccountKey?
    var targetAuthSHA256: String
    var previousAuthSHA256: String?
    var stage: String
}

private struct LegacyAccountMetadata: Decodable {
    var plan: PlanType?
    var createdAt: Int64
    var lastUsedAt: Int64?
    var lastUsage: RateLimitSnapshot?
    var lastUsageAt: Int64?

    init(
        plan: PlanType? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970),
        lastUsedAt: Int64? = nil,
        lastUsage: RateLimitSnapshot? = nil,
        lastUsageAt: Int64? = nil
    ) {
        self.plan = plan
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.lastUsage = lastUsage
        self.lastUsageAt = lastUsageAt
    }

    enum CodingKeys: String, CodingKey {
        case plan
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decodeIfPresent(PlanType.self, forKey: .plan)
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt) ?? Int64(Date().timeIntervalSince1970)
        lastUsedAt = try container.decodeIfPresent(Int64.self, forKey: .lastUsedAt)
        lastUsage = try container.decodeIfPresent(RateLimitSnapshot.self, forKey: .lastUsage)
        lastUsageAt = try container.decodeIfPresent(Int64.self, forKey: .lastUsageAt)
    }
}

public actor RegistryStore {
    public let home: CodexHome

    public init(home: CodexHome) { self.home = home }

    public func load() throws -> RegistrySnapshot {
        try SecureFiles.ensurePrivateDirectory(home.accounts)
        guard FileManager.default.fileExists(atPath: home.registry.path) else {
            return RegistrySnapshot(registry: RegistryV4(), fingerprint: .missing)
        }
        let data = try SecureFiles.readRegularFile(home.registry)
        guard data.count <= AuthParser.maximumBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw RegistryError.invalidJSON }
        let version = (object["schema_version"] as? NSNumber)?.intValue
            ?? (object["version"] as? NSNumber)?.intValue
            ?? (object["active_email"] == nil ? RegistryV4.currentSchemaVersion : 2)
        guard version <= RegistryV4.currentSchemaVersion else { throw RegistryError.unsupportedSchema(version) }
        let registry = version == 2 ? try migrateV2(object) : try RegistryCodec.decode(data)
        let needsRewrite = version < RegistryV4.currentSchemaVersion
            || object["live"] != nil || object["api"] != nil || object["auto_switch"] != nil
            || object.keys.contains("previous_active_account_key") == false
        guard needsRewrite else {
            return RegistrySnapshot(registry: registry, fingerprint: try SecureFiles.fingerprint(home.registry))
        }

        let original = try SecureFiles.fingerprint(home.registry)
        let normalized = try RegistryCodec.encode(registry)
        let fingerprint = try withLock {
            guard try SecureFiles.fingerprint(home.registry) == original else { throw StorageError.concurrentModification }
            _ = try SecureFiles.backupIfChanged(
                current: home.registry,
                replacement: normalized,
                directory: home.accounts,
                baseName: "registry.json"
            )
            try SecureFiles.atomicWrite(normalized, to: home.registry)
            return try SecureFiles.fingerprint(home.registry)
        }
        return RegistrySnapshot(registry: registry, fingerprint: fingerprint)
    }

    private func migrateV2(_ object: [String: Any]) throws -> RegistryV4 {
        let activeEmail = (object["active_email"] as? String)?.lowercased()
        let legacyAccounts = object["accounts"] as? [[String: Any]] ?? []
        var records: [AccountRecord] = []
        var activeKey: AccountKey?

        for legacy in legacyAccounts {
            guard let email = (legacy["email"] as? String)?.lowercased() else { throw AuthError.missingEmail }
            let source = try legacySnapshot(for: email)
            let authData = try SecureFiles.readRegularFile(source)
            let info = try AuthParser.parse(authData)
            guard info.authMode == .chatgpt,
                  info.email == email,
                  let key = info.accountKey,
                  let accountID = info.chatGPTAccountID,
                  let userID = info.chatGPTUserID
            else { throw AuthError.missingUserID }
            let metadata = decodeLegacyMetadata(legacy)
            let record = AccountRecord(
                accountKey: key,
                chatGPTAccountID: accountID,
                chatGPTUserID: userID,
                email: email,
                alias: legacy["alias"] as? String ?? "",
                plan: info.plan ?? metadata.plan,
                authMode: info.authMode,
                createdAt: metadata.createdAt,
                lastUsedAt: metadata.lastUsedAt,
                lastUsage: metadata.lastUsage,
                lastUsageAt: metadata.lastUsageAt
            )
            let destination = home.snapshot(for: key)
            if (try? SecureFiles.readRegularFile(destination)) != authData {
                try SecureFiles.atomicWrite(authData, to: destination)
            }
            let expectedLegacy = home.accounts.appending(path: legacySnapshotFileName(email))
            if source.standardizedFileURL == expectedLegacy.standardizedFileURL,
               source.standardizedFileURL != destination.standardizedFileURL
            {
                try? FileManager.default.removeItem(at: source)
            }
            records.append(record)
            if email == activeEmail { activeKey = key }
        }
        records.sort {
            if $0.email != $1.email { return $0.email < $1.email }
            return $0.accountKey.rawValue < $1.accountKey.rawValue
        }
        let interval = (object["interval_seconds"] as? NSNumber)?.uint16Value ?? 60
        return RegistryV4(
            activeAccountKey: activeKey,
            activeAccountActivatedAtMilliseconds: activeKey == nil ? nil : 0,
            intervalSeconds: interval,
            accounts: records
        )
    }

    private func legacySnapshot(for email: String) throws -> URL {
        let expected = home.accounts.appending(path: legacySnapshotFileName(email))
        if FileManager.default.fileExists(atPath: expected.path) { return expected }
        let candidates = try FileManager.default.contentsOfDirectory(at: home.accounts, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".auth.json") }
        for candidate in candidates {
            guard let data = try? SecureFiles.readRegularFile(candidate),
                  let info = try? AuthParser.parse(data), info.email == email
            else { continue }
            return candidate
        }
        if let data = try? SecureFiles.readRegularFile(home.auth),
           let info = try? AuthParser.parse(data), info.email == email
        {
            return home.auth
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func legacySnapshotFileName(_ email: String) -> String {
        Data(email.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") + ".auth.json"
    }

    private func decodeLegacyMetadata(_ object: [String: Any]) -> LegacyAccountMetadata {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let decoded = try? JSONDecoder().decode(LegacyAccountMetadata.self, from: data)
        else { return LegacyAccountMetadata() }
        return decoded
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

    public func writeJournal(
        target: AccountKey,
        previous: AccountKey?,
        targetAuthSHA256: String,
        previousAuthSHA256: String? = nil,
        stage: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(TransactionJournal(
            targetAccountKey: target,
            previousAccountKey: previous,
            targetAuthSHA256: targetAuthSHA256,
            previousAuthSHA256: previousAuthSHA256,
            stage: stage
        ))
        try SecureFiles.atomicWrite(data, to: home.transactionJournal)
    }

    public func removeJournal() throws {
        try SecureFiles.removeRegularFile(home.transactionJournal)
    }

    public func recoverPendingTransaction() throws -> RecoveryResult {
        guard FileManager.default.fileExists(atPath: home.transactionJournal.path) else { return .nothingToRecover }
        let journal = try JSONDecoder().decode(TransactionJournal.self, from: SecureFiles.readRegularFile(home.transactionJournal))
        let authExists = FileManager.default.fileExists(atPath: home.auth.path)
        if journal.stage == "prepared" {
            if !authExists, journal.previousAccountKey == nil {
                try removeJournal()
                return .journalRemoved
            }
            if let previous = journal.previousAccountKey,
               authExists,
               FileManager.default.fileExists(atPath: home.snapshot(for: previous).path),
               try SecureFiles.fingerprint(home.auth).sha256 == SecureFiles.fingerprint(home.snapshot(for: previous)).sha256
            {
                try removeJournal()
                return .journalRemoved
            }
            if let previousHash = journal.previousAuthSHA256,
               authExists,
               try SecureFiles.fingerprint(home.auth).sha256 == previousHash
            {
                try removeJournal()
                return .journalRemoved
            }
        }
        guard authExists,
              FileManager.default.fileExists(atPath: home.snapshot(for: journal.targetAccountKey).path)
        else { return .manualInterventionRequired }
        let active = try SecureFiles.fingerprint(home.auth)
        let target = try SecureFiles.fingerprint(home.snapshot(for: journal.targetAccountKey))
        if active.sha256 != target.sha256 {
            if let previousHash = journal.previousAuthSHA256, active.sha256 == previousHash {
                try removeJournal()
                return .journalRemoved
            }
            if let previous = journal.previousAccountKey,
               FileManager.default.fileExists(atPath: home.snapshot(for: previous).path),
               active.sha256 == (try SecureFiles.fingerprint(home.snapshot(for: previous))).sha256
            {
                try removeJournal()
                return .journalRemoved
            }
            return .manualInterventionRequired
        }
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
        let descriptor = open(home.lock.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw StorageError.cannotOpen(home.lock.path) }
        defer { close(descriptor) }
        guard fchmod(descriptor, 0o600) == 0 else { throw StorageError.cannotWrite(home.lock.path) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw StorageError.cannotOpen(home.lock.path) }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
}
