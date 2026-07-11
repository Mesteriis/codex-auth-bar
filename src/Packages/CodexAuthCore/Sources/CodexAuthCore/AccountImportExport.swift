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
        if request.format != .purge { _ = try? await syncActiveAuth() }
        for attempt in 0..<3 {
            do { return try await importAccountsAttempt(request) }
            catch StorageError.concurrentModification {
                if attempt < 2 { continue }
                throw AccountError.concurrentModification
            }
        }
        throw AccountError.concurrentModification
    }

    private func importAccountsAttempt(_ request: ImportRequest) async throws -> ImportReport {
        var sources: [(String, Data)] = []
        var preliminaryEvents: [ImportEvent] = []
        var isDirectory: ObjCBool = false
        let sourceExists = FileManager.default.fileExists(atPath: request.source.path, isDirectory: &isDirectory)
        if request.format == .purge, sourceExists, isDirectory.boolValue {
            let result = try await purgeSources(in: request.source)
            sources = result.sources
            preliminaryEvents = result.events
        } else if sourceExists, isDirectory.boolValue {
            let urls = try FileManager.default.contentsOfDirectory(at: request.source, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in urls {
                do {
                    sources.append((url.lastPathComponent, try SecureFiles.readRegularFile(url)))
                } catch {
                    preliminaryEvents.append(.init(
                        source: url.lastPathComponent,
                        outcome: .skipped,
                        detail: String(describing: error)
                    ))
                }
            }
        } else {
            let data = try SecureFiles.readRegularFile(request.source)
            if let object = try? JSONSerialization.jsonObject(with: data), let array = object as? [Any] {
                sources = try array.enumerated().map { ("\(request.source.lastPathComponent)[\($0.offset)]", try JSONSerialization.data(withJSONObject: $0.element)) }
            } else {
                sources = [(request.source.lastPathComponent, data)]
            }
        }

        var loaded = try await store.load()
        if request.format == .purge {
            loaded.registry = RegistryV4(intervalSeconds: loaded.registry.intervalSeconds)
        }
        var events = preliminaryEvents
        var imported: [AccountKey] = []
        let applyAlias = !isDirectory.boolValue && sources.count == 1 ? request.alias ?? "" : ""

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

                if !applyAlias.isEmpty {
                    guard !applyAlias.allSatisfy(\.isNumber),
                          !applyAlias.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                    else { throw AccountError.invalidAlias }
                    if loaded.registry.accounts.contains(where: {
                        $0.accountKey != key && !$0.alias.isEmpty
                            && $0.alias.caseInsensitiveCompare(applyAlias) == .orderedSame
                    }) {
                        throw AccountError.duplicateAlias
                    }
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
        if request.format == .purge {
            loaded.registry.accounts.sort {
                if $0.email != $1.email { return $0.email < $1.email }
                return $0.accountKey.rawValue < $1.accountKey.rawValue
            }
        }
        _ = try await store.commit(loaded.registry, expected: loaded.fingerprint)
        if request.format == .purge {
            _ = try? await syncActiveAuth()
            let rebuilt = try await store.load().registry
            if rebuilt.activeAccountKey == nil, let first = rebuilt.accounts.first?.accountKey {
                _ = try await switchAccount(to: first)
            }
        } else if request.activate, let key = imported.last {
            _ = try await switchAccount(to: key)
        }
        return ImportReport(events: events, importedAccountKeys: imported)
    }

    private func purgeSources(in directory: URL) async throws -> (sources: [(String, Data)], events: [ImportEvent]) {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            $0.lastPathComponent.hasSuffix(".auth.json") || $0.lastPathComponent.hasPrefix("auth.json.bak.")
        }
        var selected: [AccountKey: PurgeCandidate] = [:]
        var events: [ImportEvent] = []

        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                let data = try SecureFiles.readRegularFile(url)
                let info = try AuthParser.parse(data)
                let key: AccountKey
                if info.authMode == .apiKey {
                    guard let apiKey = info.openAIAPIKey else { throw AuthError.missingAccessToken }
                    let identity = try await apiKeyIdentityResolver.identity(apiKey: apiKey)
                    key = Self.apiKeyAccountKey(identityID: identity.id, apiKey: apiKey)
                } else {
                    guard let accountKey = info.accountKey else { throw AuthError.missingUserID }
                    key = accountKey
                }
                let canonical = CodexHome.snapshotFileName(for: key)
                let rank: Int
                if url.lastPathComponent == canonical {
                    rank = 2
                } else if url.lastPathComponent.hasPrefix("auth.json.bak.") {
                    rank = 1
                } else {
                    rank = 0
                }
                let candidate = PurgeCandidate(
                    name: url.lastPathComponent,
                    data: data,
                    key: key,
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    rank: rank
                )
                if let current = selected[key] {
                    if current < candidate {
                        events.append(.init(source: current.name, outcome: .skipped, detail: "SupersededByNewerSnapshot"))
                        selected[key] = candidate
                    } else {
                        events.append(.init(source: candidate.name, outcome: .skipped, detail: "SupersededByNewerSnapshot"))
                    }
                } else {
                    selected[key] = candidate
                }
            } catch {
                events.append(.init(source: url.lastPathComponent, outcome: .skipped, detail: String(describing: error)))
            }
        }

        let candidates = selected.values.sorted {
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.key.rawValue < $1.key.rawValue
        }
        return (candidates.map { ($0.name, $0.data) }, events)
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
            let original = try SecureFiles.readRegularFile(source)
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
        _ = try? await syncActiveAuth()
        for attempt in 0..<3 {
            do { return try await removeAttempt(keys) }
            catch StorageError.concurrentModification {
                if attempt < 2 { continue }
                throw AccountError.concurrentModification
            }
        }
        throw AccountError.concurrentModification
    }

    private func removeAttempt(_ keys: Set<AccountKey>) async throws -> RemovalReport {
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
                canReplaceLiveAuth = try SecureFiles.readRegularFile(home.auth) == SecureFiles.readRegularFile(activeSnapshot)
            } else {
                canReplaceLiveAuth = false
            }
            promoted = registry.accounts.max(by: { candidateScore($0) < candidateScore($1) })?.accountKey
            registry.activeAccountKey = promoted
            registry.previousActiveAccountKey = nil
            if let promoted, canReplaceLiveAuth {
                let data = try SecureFiles.readRegularFile(home.snapshot(for: promoted))
                _ = try SecureFiles.backupIfChanged(current: home.auth, replacement: data, directory: home.accounts, baseName: "auth.json")
                try SecureFiles.copyPreservingDestinationMode(data, to: home.auth)
            } else if promoted == nil, canReplaceLiveAuth, FileManager.default.fileExists(atPath: home.auth.path) {
                _ = try SecureFiles.backupIfChanged(
                    current: home.auth,
                    replacement: Data(),
                    directory: home.accounts,
                    baseName: "auth.json"
                )
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

private struct PurgeCandidate: Sendable {
    var name: String
    var data: Data
    var key: AccountKey
    var modifiedAt: Date
    var rank: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        return lhs.name < rhs.name
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
