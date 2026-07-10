import Foundation

public enum ImportFormat: Sendable { case automatic, standard, cpa, purge }

public struct ImportRequest: Sendable {
    public var source: URL
    public var format: ImportFormat
    public var alias: String?
    public var activate: Bool

    public init(source: URL, format: ImportFormat = .automatic, alias: String? = nil, activate: Bool = false) {
        self.source = source
        self.format = format
        self.alias = alias
        self.activate = activate
    }
}

public struct ImportEvent: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable { case imported, updated, skipped }
    public var source: String
    public var outcome: Outcome
    public var detail: String
}

public struct ImportReport: Codable, Equatable, Sendable {
    public var events: [ImportEvent]
    public var importedAccountKeys: [AccountKey]
}

public enum ExportFormat: Sendable { case standard, cpa }

public struct ExportRequest: Sendable {
    public var destination: URL?
    public var format: ExportFormat
    public init(destination: URL? = nil, format: ExportFormat = .standard) {
        self.destination = destination
        self.format = format
    }
}

public struct ExportReport: Equatable, Sendable {
    public var exportedCount: Int
    public var skippedCount: Int
    public var destination: URL
}

public struct RemovalReport: Equatable, Sendable {
    public var removedAccountKeys: [AccountKey]
    public var promotedAccountKey: AccountKey?
}

public extension AccountRepository {
    func importAccounts(_ request: ImportRequest) async throws -> ImportReport {
        var sources: [(String, Data)] = []
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: request.source.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let urls = try FileManager.default.contentsOfDirectory(at: request.source, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            sources = try urls.map { ($0.lastPathComponent, try Data(contentsOf: $0)) }
        } else {
            let data = try Data(contentsOf: request.source)
            if let array = try JSONSerialization.jsonObject(with: data) as? [Any] {
                sources = try array.enumerated().map { ("\(request.source.lastPathComponent)[\($0.offset)]", try JSONSerialization.data(withJSONObject: $0.element)) }
            } else {
                sources = [(request.source.lastPathComponent, data)]
            }
        }

        if request.format == .purge {
            sources = try FileManager.default.contentsOfDirectory(at: request.source, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.lastPathComponent.hasSuffix(".auth.json") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { ($0.lastPathComponent, try Data(contentsOf: $0)) }
        }

        var loaded = try await store.load()
        if request.format == .purge { loaded.registry = RegistryV4() }
        var events: [ImportEvent] = []
        var imported: [AccountKey] = []
        let applyAlias = sources.count == 1 ? request.alias ?? "" : ""

        for (name, originalData) in sources {
            do {
                let data: Data
                switch request.format {
                case .cpa: data = try CPAConverter.toStandard(originalData)
                case .automatic:
                    data = (try? AuthParser.parse(originalData)) != nil ? originalData : try CPAConverter.toStandard(originalData)
                case .standard, .purge: data = originalData
                }
                let info = try AuthParser.parse(data)
                let key: AccountKey
                let incoming: AccountRecord
                if info.authMode == .apiKey {
                    guard let apiKey = info.openAIAPIKey else { throw AuthError.missingAccessToken }
                    let identity = try await apiKeyIdentityResolver.identity(apiKey: apiKey)
                    key = Self.apiKeyAccountKey(identityID: identity.id, apiKey: apiKey)
                    incoming = Self.apiKeyRecord(key: key, identity: identity, apiKey: apiKey)
                } else {
                    guard let resolvedKey = info.accountKey,
                          let accountID = info.chatGPTAccountID, let userID = info.chatGPTUserID,
                          let email = info.email
                    else { throw AuthError.missingUserID }
                    key = resolvedKey
                    incoming = AccountRecord(
                        accountKey: key,
                        chatGPTAccountID: accountID,
                        chatGPTUserID: userID,
                        email: email,
                        alias: applyAlias,
                        plan: info.plan,
                        authMode: info.authMode
                    )
                }

                let existingIndex = loaded.registry.accounts.firstIndex { $0.accountKey == key }
                if let existingIndex {
                    loaded.registry.accounts[existingIndex].email = incoming.email
                    loaded.registry.accounts[existingIndex].plan = incoming.plan
                    loaded.registry.accounts[existingIndex].authMode = incoming.authMode
                    loaded.registry.accounts[existingIndex].accountName = incoming.accountName ?? loaded.registry.accounts[existingIndex].accountName
                    if !applyAlias.isEmpty { loaded.registry.accounts[existingIndex].alias = applyAlias }
                } else {
                    var record = incoming
                    if !applyAlias.isEmpty { record.alias = applyAlias }
                    loaded.registry.accounts.append(record)
                }
                try SecureFiles.atomicWrite(data, to: home.snapshot(for: key))
                imported.append(key)
                events.append(ImportEvent(source: name, outcome: existingIndex == nil ? .imported : .updated, detail: incoming.email))
            } catch {
                events.append(ImportEvent(source: name, outcome: .skipped, detail: String(describing: error)))
            }
        }
        if request.format == .purge, loaded.registry.activeAccountKey == nil {
            loaded.registry.activeAccountKey = loaded.registry.accounts.first?.accountKey
        }
        _ = try await store.commit(loaded.registry, expected: loaded.fingerprint)
        if request.activate, let key = imported.last { _ = try await switchAccount(to: key) }
        return ImportReport(events: events, importedAccountKeys: imported)
    }

    func exportAccounts(_ request: ExportRequest) async throws -> ExportReport {
        let registry = try await store.load().registry
        let destination = request.destination ?? home.exportBackup
        try SecureFiles.ensurePrivateDirectory(destination)
        var exported = 0
        var skipped = 0
        for record in registry.accounts {
            let source = home.snapshot(for: record.accountKey)
            guard FileManager.default.fileExists(atPath: source.path) else { skipped += 1; continue }
            let original = try Data(contentsOf: source)
            let data: Data
            let name: String
            switch request.format {
            case .standard:
                data = original
                name = CodexHome.snapshotFileName(for: record.accountKey)
            case .cpa:
                guard let converted = try? CPAConverter.fromStandard(original) else { skipped += 1; continue }
                data = converted
                name = CodexHome.snapshotFileName(for: record.accountKey).replacingOccurrences(of: ".auth.json", with: ".json")
            }
            try SecureFiles.atomicWrite(data, to: destination.appending(path: name))
            exported += 1
        }
        return ExportReport(exportedCount: exported, skippedCount: skipped, destination: destination)
    }

    func remove(_ keys: Set<AccountKey>) async throws -> RemovalReport {
        let loaded = try await store.load()
        let existing = Set(loaded.registry.accounts.map(\.accountKey))
        let removing = keys.intersection(existing)
        var registry = loaded.registry
        registry.accounts.removeAll { removing.contains($0.accountKey) }
        var promoted: AccountKey?
        if let active = registry.activeAccountKey, removing.contains(active) {
            let activeSnapshot = home.snapshot(for: active)
            let canReplaceLiveAuth: Bool
            if !FileManager.default.fileExists(atPath: home.auth.path) {
                canReplaceLiveAuth = true
            } else if FileManager.default.fileExists(atPath: activeSnapshot.path) {
                canReplaceLiveAuth = try Data(contentsOf: home.auth) == Data(contentsOf: activeSnapshot)
            } else {
                canReplaceLiveAuth = false
            }
            promoted = registry.accounts.max(by: { candidateScore($0) < candidateScore($1) })?.accountKey
            registry.activeAccountKey = promoted
            registry.previousActiveAccountKey = nil
            if let promoted, canReplaceLiveAuth {
                let data = try Data(contentsOf: home.snapshot(for: promoted))
                _ = try SecureFiles.backupIfChanged(current: home.auth, replacement: data, directory: home.accounts, baseName: "auth.json")
                try SecureFiles.copyPreservingDestinationMode(data, to: home.auth)
            } else if promoted == nil, canReplaceLiveAuth, FileManager.default.fileExists(atPath: home.auth.path) {
                try FileManager.default.removeItem(at: home.auth)
            }
        }
        if let previous = registry.previousActiveAccountKey, removing.contains(previous) { registry.previousActiveAccountKey = nil }
        _ = try await store.commit(registry, expected: loaded.fingerprint)
        for key in removing {
            let snapshot = home.snapshot(for: key)
            if FileManager.default.fileExists(atPath: snapshot.path) { try FileManager.default.removeItem(at: snapshot) }
        }
        return RemovalReport(removedAccountKeys: Array(removing).sorted { $0.rawValue < $1.rawValue }, promotedAccountKey: promoted)
    }
}

private func candidateScore(_ account: AccountRecord, now: Date = .now) -> (Double, Int64, Int64) {
    let windows = [account.lastUsage?.primary, account.lastUsage?.secondary].compactMap { $0?.remainingPercent(at: now) }
    return (windows.min() ?? 100, account.lastUsageAt ?? -1, account.createdAt)
}

private func < (lhs: (Double, Int64, Int64), rhs: (Double, Int64, Int64)) -> Bool {
    if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
    if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
    return lhs.2 < rhs.2
}
