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
    let apiKeyIdentityResolver: any APIKeyIdentityResolving

    public init(
        home: CodexHome,
        store: RegistryStore? = nil,
        apiKeyIdentityResolver: any APIKeyIdentityResolving = APIKeyIdentityService()
    ) {
        self.home = home
        self.store = store ?? RegistryStore(home: home)
        self.apiKeyIdentityResolver = apiKeyIdentityResolver
    }

    public func state(refresh: RefreshPolicy) async throws -> AccountState {
        _ = try? await syncActiveAuth()
        return AccountState(registry: try await store.load().registry)
    }

    @discardableResult
    public func syncActiveAuth() async throws -> Bool {
        guard FileManager.default.fileExists(atPath: home.auth.path) else { return false }
        let data = try Data(contentsOf: home.auth)
        guard let info = try? AuthParser.parse(data) else { return false }

        for _ in 0..<3 {
            let loaded = try await store.load()
            var registry = loaded.registry
            let record: AccountRecord
            let key: AccountKey

            if info.authMode == .apiKey {
                if let existing = registry.accounts.first(where: { account in
                    guard account.authMode == .apiKey,
                          let snapshot = try? Data(contentsOf: home.snapshot(for: account.accountKey))
                    else { return false }
                    return snapshot == data
                }) {
                    record = existing
                    key = existing.accountKey
                } else {
                    guard let apiKey = info.openAIAPIKey else { return false }
                    let identity = try await apiKeyIdentityResolver.identity(apiKey: apiKey)
                    key = Self.apiKeyAccountKey(identityID: identity.id, apiKey: apiKey)
                    record = Self.apiKeyRecord(key: key, identity: identity, apiKey: apiKey)
                }
            } else {
                guard let resolvedKey = info.accountKey,
                      let accountID = info.chatGPTAccountID,
                      let userID = info.chatGPTUserID,
                      let email = info.email
                else { return false }
                key = resolvedKey
                record = AccountRecord(
                    accountKey: key,
                    chatGPTAccountID: accountID,
                    chatGPTUserID: userID,
                    email: email,
                    plan: info.plan,
                    authMode: info.authMode
                )
            }

            let existingIndex = registry.accounts.firstIndex { $0.accountKey == key }
            var changed = registry.activeAccountKey != key
            if let existingIndex {
                let existing = registry.accounts[existingIndex]
                registry.accounts[existingIndex].email = record.email
                registry.accounts[existingIndex].plan = record.plan
                registry.accounts[existingIndex].authMode = record.authMode
                registry.accounts[existingIndex].chatGPTAccountID = record.chatGPTAccountID
                registry.accounts[existingIndex].chatGPTUserID = record.chatGPTUserID
                changed = changed || existing.email != record.email || existing.plan != record.plan || existing.authMode != record.authMode
            } else {
                registry.accounts.append(record)
                changed = true
            }
            let snapshot = home.snapshot(for: key)
            if (try? Data(contentsOf: snapshot)) != data {
                try SecureFiles.atomicWrite(data, to: snapshot)
                changed = true
            }
            registry.activeAccountKey = key
            registry.activeAccountActivatedAtMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
            guard changed else { return false }
            do {
                _ = try await store.commit(registry, expected: loaded.fingerprint)
                return true
            } catch StorageError.concurrentModification { continue }
        }
        throw AccountError.concurrentModification
    }

    public func refreshAccountNames(using fetcher: any UsageFetching) async throws {
        for _ in 0..<3 {
            let loaded = try await store.load()
            guard let activeKey = loaded.registry.activeAccountKey,
                  let active = loaded.registry.accounts.first(where: { $0.accountKey == activeKey })
            else { return }
            let scoped = loaded.registry.accounts.filter { $0.chatGPTUserID == active.chatGPTUserID }
            guard scoped.count > 1,
                  scoped.contains(where: { $0.resolvedPlan == .team || $0.resolvedPlan == .business })
            else { return }
            guard case let .success(names) = await fetcher.accountNames(for: UserScope(chatGPTUserID: active.chatGPTUserID, accounts: scoped)) else { return }
            var registry = loaded.registry
            for index in registry.accounts.indices where registry.accounts[index].chatGPTUserID == active.chatGPTUserID {
                let record = registry.accounts[index]
                if let name = names[record.chatGPTAccountID], !name.isEmpty {
                    registry.accounts[index].accountName = name
                } else if record.resolvedPlan == .team || record.resolvedPlan == .business || record.accountName != nil {
                    registry.accounts[index].accountName = nil
                }
            }
            do {
                _ = try await store.commit(registry, expected: loaded.fingerprint)
                return
            } catch StorageError.concurrentModification { continue }
        }
        throw AccountError.concurrentModification
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
        let priorAuth = FileManager.default.fileExists(atPath: home.auth.path) ? try Data(contentsOf: home.auth) : nil
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
        } catch {
            let liveHash = try? SecureFiles.fingerprint(home.auth).sha256
            if liveHash == targetHash {
                if let priorAuth {
                    try SecureFiles.copyPreservingDestinationMode(priorAuth, to: home.auth)
                } else if FileManager.default.fileExists(atPath: home.auth.path) {
                    try FileManager.default.removeItem(at: home.auth)
                }
                try await store.removeJournal()
            }
            if error is StorageError { throw AccountError.concurrentModification }
            throw error
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

    static func apiKeyAccountKey(identityID: String, apiKey: String) -> AccountKey {
        let digest = SHA256.hash(data: Data(apiKey.utf8)).map { String(format: "%02x", $0) }.joined()
        return AccountKey("apikey::\(identityID)::\(digest)")
    }

    static func apiKeyRecord(key: AccountKey, identity: APIKeyIdentity, apiKey: String) -> AccountRecord {
        let digest = SHA256.hash(data: Data(apiKey.utf8)).map { String(format: "%02x", $0) }.joined()
        let label = "API key \(digest.prefix(5))…\(digest.suffix(4))"
        return AccountRecord(
            accountKey: key,
            chatGPTAccountID: identity.id,
            chatGPTUserID: identity.id,
            email: identity.email,
            accountName: label,
            authMode: .apiKey
        )
    }
}
