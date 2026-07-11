import CryptoKit
import Foundation
import Testing
@testable import CodexAuthCore

struct FeatureServicesTests {
    @Test func importsAPIKeyUsingVerifiedIdentityWithoutRegistrySecret() async throws {
        let fixture = try FeatureFixture()
        let source = fixture.root.appending(path: "api-key.json")
        try Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-synthetic-test"}"#.utf8).write(to: source)
        let repository = AccountRepository(
            home: fixture.home,
            apiKeyIdentityResolver: StubAPIKeyResolver(identity: APIKeyIdentity(id: "api-user", email: "KEY@Example.com"))
        )

        let report = try await repository.importAccounts(ImportRequest(source: source))
        let key = try #require(report.importedAccountKeys.first)
        let state = try await repository.state(refresh: .stored)
        let encodedRegistry = try RegistryCodec.encode(state.registry)

        #expect(key.rawValue.hasPrefix("apikey::api-user::"))
        #expect(state.registry.accounts.first?.email == "key@example.com")
        #expect(state.registry.accounts.first?.authMode == .apiKey)
        #expect(!String(decoding: encodedRegistry, as: UTF8.self).contains("sk-synthetic-test"))
        #expect(String(decoding: try Data(contentsOf: fixture.home.snapshot(for: key)), as: UTF8.self).contains("sk-synthetic-test"))
    }

    @Test func accountNameRefreshUpdatesAndClearsOnlyMatchingUserScope() async throws {
        let fixture = try FeatureFixture()
        var first = record("team-1", remaining: 80, plan: .team)
        var second = record("team-2", remaining: 80, plan: .team)
        var outside = record("outside", remaining: 80, plan: .team)
        first.accountName = nil
        second.accountName = "Old name"
        outside.chatGPTUserID = "other-user"
        outside.accountName = "Keep me"
        let store = RegistryStore(home: fixture.home)
        let loaded = try await store.load()
        _ = try await store.commit(RegistryV4(activeAccountKey: first.accountKey, accounts: [first, second, outside]), expected: loaded.fingerprint)
        let repository = AccountRepository(home: fixture.home, store: store)

        try await repository.refreshAccountNames(using: StubUsageFetcher(names: ["team-1": "Production"]))
        let state = try await repository.state(refresh: .stored)

        #expect(state.registry.accounts.first(where: { $0.accountKey == first.accountKey })?.accountName == "Production")
        #expect(state.registry.accounts.first(where: { $0.accountKey == second.accountKey })?.accountName == nil)
        #expect(state.registry.accounts.first(where: { $0.accountKey == outside.accountKey })?.accountName == "Keep me")
    }

    @Test func stateActiveRemoteHonorsRefreshPolicy() async throws {
        let fixture = try FeatureFixture()
        let account = record("remote", remaining: 10, plan: .plus)
        let store = RegistryStore(home: fixture.home)
        let loaded = try await store.load()
        _ = try await store.commit(
            RegistryV4(activeAccountKey: account.accountKey, accounts: [account]),
            expected: loaded.fingerprint
        )
        let refreshed = RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 25),
            planType: .pro
        )
        let repository = AccountRepository(
            home: fixture.home,
            store: store,
            usageFetcher: StubUsageFetcher(names: [:], usageResult: .success(refreshed))
        )

        let state = try await repository.state(refresh: .activeRemote)

        #expect(state.registry.accounts.first?.lastUsage == refreshed)
        #expect(state.registry.accounts.first?.lastUsageAt != nil)
    }

    @Test func stateSyncsExternallyChangedAuthIntoRegistry() async throws {
        let fixture = try FeatureFixture()
        let auth = try authData(email: "external@example.com", userID: "external-user", accountID: "external-account")
        try auth.write(to: fixture.home.auth)
        let repository = AccountRepository(home: fixture.home)

        let state = try await repository.state(refresh: .stored)
        let record = try #require(state.registry.accounts.first)

        #expect(record.accountKey == AccountKey("external-user::external-account"))
        #expect(state.registry.activeAccountKey == record.accountKey)
        #expect(try Data(contentsOf: fixture.home.snapshot(for: record.accountKey)) == auth)
    }

    @Test func purgeSelectsNewestSnapshotAndSafelyActivatesIt() async throws {
        let fixture = try FeatureFixture()
        let old = try authData(email: "old@example.com", userID: "purge-user", accountID: "purge-account")
        let newest = try authData(email: "new@example.com", userID: "purge-user", accountID: "purge-account")
        let key = AccountKey("purge-user::purge-account")
        let canonical = fixture.home.snapshot(for: key)
        let backup = fixture.home.accounts.appending(path: "auth.json.bak.20260711")
        try old.write(to: canonical)
        try newest.write(to: backup)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: canonical.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: backup.path)
        let staleLiveAuth = Data(#"{"broken":true}"#.utf8)
        try staleLiveAuth.write(to: fixture.home.auth)
        let repository = AccountRepository(home: fixture.home)

        let report = try await repository.importAccounts(
            ImportRequest(source: fixture.home.accounts, format: .purge)
        )
        let state = try await repository.state(refresh: .stored)
        let recovered = try #require(state.registry.accounts.first)
        let backupFiles = try FileManager.default.contentsOfDirectory(at: fixture.home.accounts, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("auth.json.bak.") && $0 != backup }

        #expect(report.importedAccountKeys == [key])
        #expect(state.registry.accounts.count == 1)
        #expect(recovered.email == "new@example.com")
        #expect(state.registry.activeAccountKey == key)
        #expect(try Data(contentsOf: fixture.home.auth) == newest)
        #expect(try backupFiles.contains { try Data(contentsOf: $0) == staleLiveAuth })
    }

    @Test func cpaConversionPreservesTokens() throws {
        let idToken = makeJWT(email: "import@example.com", userID: "u", accountID: "a")
        let cpa = try JSONSerialization.data(withJSONObject: [
            "id_token": idToken,
            "access_token": "access",
            "refresh_token": "refresh",
        ])

        let standard = try CPAConverter.toStandard(cpa)
        let roundTrip = try CPAConverter.fromStandard(standard)
        let object = try #require(try JSONSerialization.jsonObject(with: roundTrip) as? [String: Any])

        #expect(object["access_token"] as? String == "access")
        #expect(object["refresh_token"] as? String == "refresh")
    }

    @Test func importWritesByteIdenticalSnapshotAndExportCopiesIt() async throws {
        let fixture = try FeatureFixture()
        let auth = try authData(email: "import@example.com", userID: "u", accountID: "a")
        let source = fixture.root.appending(path: "source.json")
        try auth.write(to: source)
        let repository = AccountRepository(home: fixture.home)

        let report = try await repository.importAccounts(ImportRequest(source: source, alias: "work"))
        let key = try #require(report.importedAccountKeys.first)
        let exported = fixture.root.appending(path: "export", directoryHint: .isDirectory)
        let exportReport = try await repository.exportAccounts(ExportRequest(destination: exported))

        #expect(try Data(contentsOf: fixture.home.snapshot(for: key)) == auth)
        #expect(exportReport.exportedCount == 1)
        #expect(FileManager.default.fileExists(atPath: exported.appending(path: CodexHome.snapshotFileName(for: key)).path))
    }

    @Test func failedImportLeavesLiveAuthByteIdentical() async throws {
        let fixture = try FeatureFixture()
        let original = try authData(email: "live@example.com", userID: "live-user", accountID: "live-account")
        try original.write(to: fixture.home.auth)
        let invalid = fixture.root.appending(path: "invalid.json")
        try Data(#"{"broken":true}"#.utf8).write(to: invalid)
        let repository = AccountRepository(home: fixture.home)

        let report = try await repository.importAccounts(ImportRequest(source: invalid, activate: true))

        #expect(report.importedAccountKeys.isEmpty)
        #expect(report.events.first?.outcome == .skipped)
        #expect(try Data(contentsOf: fixture.home.auth) == original)
    }

    @Test func removeActivePromotesBestRemainingAccount() async throws {
        let fixture = try FeatureFixture()
        let weak = record("weak", remaining: 5)
        let best = record("best", remaining: 80)
        let medium = record("medium", remaining: 50)
        for account in [weak, best, medium] { try Data(account.email.utf8).write(to: fixture.home.snapshot(for: account.accountKey)) }
        try Data(weak.email.utf8).write(to: fixture.home.auth)
        let store = RegistryStore(home: fixture.home)
        let loaded = try await store.load()
        _ = try await store.commit(RegistryV4(activeAccountKey: weak.accountKey, accounts: [weak, best, medium]), expected: loaded.fingerprint)
        let repository = AccountRepository(home: fixture.home, store: store)

        let report = try await repository.remove([weak.accountKey])
        let state = try await repository.state(refresh: .stored)

        #expect(report.promotedAccountKey == best.accountKey)
        #expect(state.registry.activeAccountKey == best.accountKey)
        #expect(String(decoding: try Data(contentsOf: fixture.home.auth), as: UTF8.self) == best.email)
    }

    @Test func removeLeavesExternallyChangedAuthUntouched() async throws {
        let fixture = try FeatureFixture()
        let active = record("active", remaining: 5)
        let replacement = record("replacement", remaining: 80)
        for account in [active, replacement] { try Data(account.email.utf8).write(to: fixture.home.snapshot(for: account.accountKey)) }
        try Data("external-untracked-auth".utf8).write(to: fixture.home.auth)
        let store = RegistryStore(home: fixture.home)
        let loaded = try await store.load()
        _ = try await store.commit(RegistryV4(activeAccountKey: active.accountKey, accounts: [active, replacement]), expected: loaded.fingerprint)
        let repository = AccountRepository(home: fixture.home, store: store)

        _ = try await repository.remove([active.accountKey])

        #expect(String(decoding: try Data(contentsOf: fixture.home.auth), as: UTF8.self) == "external-untracked-auth")
    }

    @Test func usageParserMapsFiveHourWeeklyAndCredits() throws {
        let data = Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":18000,"reset_at":1000},"secondary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_at":2000}},"credits":{"has_credits":true,"unlimited":false,"balance":"12"},"rate_limit_reset_credits":{"available_count":3}}"#.utf8)

        let snapshot = try #require(UsageParser.parse(data))

        #expect(snapshot.primary?.windowMinutes == 300)
        #expect(snapshot.secondary?.windowMinutes == 10_080)
        #expect(snapshot.credits?.balance == "12")
        #expect(snapshot.resetCredits == 3)
    }

    @Test func usageServiceUsesURLProtocolStubAndMapsUnauthorizedWithoutNetwork() async throws {
        let fixture = try FeatureFixture()
        let account = record("stub", remaining: 50)
        try authData(email: account.email, userID: "u", accountID: "stub")
            .write(to: fixture.home.snapshot(for: account.accountKey))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.statusCode = 401
        StubURLProtocol.body = Data()
        let service = ChatGPTUsageService(home: fixture.home, session: URLSession(configuration: configuration))

        let result = await service.usage(for: account)

        guard case let .status(code) = result else {
            Issue.record("Expected HTTP status result")
            return
        }
        #expect(code == 401)
        #expect(StubURLProtocol.lastHost == "chatgpt.com")
    }

    @Test func localUsageIgnoresPreActivationEventsAndPersistsSignature() async throws {
        let fixture = try FeatureFixture()
        let account = record("local", remaining: 50)
        let sessions = fixture.home.root.appending(path: "sessions/2026/07/11", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let rollout = sessions.appending(path: "rollout-test.jsonl")
        let old = #"{"timestamp":"2026-07-11T00:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":90,"window_minutes":300}}}}"#
        let current = #"{"timestamp":"2026-07-11T00:02:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":25,"window_minutes":300}}}}"#
        try Data("\(old)\n\(current)\n".utf8).write(to: rollout)
        let activated = Int64(ISO8601DateFormatter().date(from: "2026-07-11T00:01:00Z")!.timeIntervalSince1970 * 1_000)
        let scanned = try LocalUsageScanner.newest(home: fixture.home, activatedAtMilliseconds: activated)
        let event = try #require(scanned)
        let store = RegistryStore(home: fixture.home)
        let loaded = try await store.load()
        _ = try await store.commit(RegistryV4(activeAccountKey: account.accountKey, accounts: [account]), expected: loaded.fingerprint)
        let repository = AccountRepository(home: fixture.home, store: store)

        try await repository.updateLocalUsage(event, for: account.accountKey)
        try await repository.updateLocalUsage(event, for: account.accountKey)
        let state = try await store.load().registry

        #expect(state.accounts.first?.lastUsage?.primary?.usedPercent == 25)
        #expect(state.accounts.first?.lastLocalRollout == event.signature)
    }

    @Test func autoSwitchUsesFreeGuardAndBestCandidate() {
        let active = record("active", remaining: 30, plan: .free)
        let good = record("good", remaining: 90)
        let better = record("better", remaining: 95)
        let registry = RegistryV4(activeAccountKey: active.accountKey, accounts: [active, good, better])

        let decision = AutoSwitchPolicy().decision(registry: registry, thresholds: .init(fiveHour: 10, weekly: 5))

        #expect(decision?.target == better.accountKey)
        #expect(AutoSwitchPolicy().rankedCandidates(registry: registry).map(\.accountKey) == [better.accountKey, good.accountKey])
    }

    @Test func profileStoreManagesOnlyValidProfileFiles() async throws {
        let fixture = try FeatureFixture()
        let store = ProfileStore(home: fixture.home)

        try await store.create(ProfileName("work")!)
        try Data().write(to: fixture.home.root.appending(path: "not a profile.config.toml"))
        let target = fixture.root.appending(path: "external.toml")
        try Data("external".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: fixture.home.root.appending(path: "linked.config.toml"),
            withDestinationURL: target
        )
        let profiles = try await store.list()
        try await store.rename(ProfileName("work")!, to: ProfileName("team")!)

        #expect(profiles == [ProfileName("work")!])
        #expect(FileManager.default.fileExists(atPath: fixture.home.root.appending(path: "team.config.toml").path))
    }

    @Test func terminalProfileCommandShellQuotesExecutableAndSelfDeletes() {
        let profile = ProfileName("work")!
        let executable = URL(fileURLWithPath: "/tmp/cod'ex")

        let command = TerminalCommandBuilder.command(codex: executable, profile: profile)
        let script = TerminalCommandBuilder.script(codex: executable, profile: profile)

        #expect(command == #"'/tmp/cod'\''ex' --profile 'work'"#)
        #expect(script.contains(#"rm -f -- "$self""#))
        #expect(script.contains("exec \(command)"))
    }

    @Test func codextManifestRejectsWrongHash() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("binary".utf8).write(to: file)
        let manifest = CodextArtifact(architecture: .arm64, url: URL(string: "https://github.com/example/archive.tar.gz")!, sha256: String(repeating: "0", count: 64), size: 6)

        #expect(throws: CodextError.hashMismatch) {
            try CodextVerifier.verify(file: file, artifact: manifest)
        }
    }

    @Test func codextArchiveRejectsTraversalAndUnexpectedFiles() throws {
        #expect(throws: CodextError.unsafeArchive) {
            try CodextArchiveValidator.validate(entries: ["codext", "../codex-code-mode-host"])
        }
        #expect(throws: CodextError.unsafeArchive) {
            try CodextArchiveValidator.validate(entries: ["codext", "codex-code-mode-host", "extra"])
        }
        #expect(throws: CodextError.unsafeArchive) {
            try CodextArchiveValidator.validateVerboseListing([
                "lrwxr-xr-x user/group 0 date codext",
                "-rwxr-xr-x user/group 1 date codex-code-mode-host",
            ])
        }
        try CodextArchiveValidator.validate(entries: ["codex-code-mode-host", "codext"])
        try CodextArchiveValidator.validateVerboseListing([
            "-rwxr-xr-x user/group 1 date codext",
            "-rwxr-xr-x user/group 1 date codex-code-mode-host",
        ])
    }

    @Test func doctorReportParsesCredentialStoreWithoutDependingOnCheckLayout() throws {
        let report = Data(#"{"checks":{"auth.credentials":{"details":{"auth storage mode":"Keyring"}}}}"#.utf8)
        let alternate = Data(#"{"diagnostics":[{"credential_store":"ephemeral"}]}"#.utf8)

        #expect(try DoctorReportParser.credentialStore(from: report) == .keyring)
        #expect(try DoctorReportParser.credentialStore(from: alternate) == .ephemeral)
        #expect(try DoctorReportParser.credentialStore(from: Data(#"{"checks":{}}"#.utf8)) == .unknown)
    }
}

private struct StubAPIKeyResolver: APIKeyIdentityResolving {
    let identity: APIKeyIdentity
    func identity(apiKey: String) async throws -> APIKeyIdentity { identity }
}

private struct StubUsageFetcher: UsageFetching {
    let names: [String: String]
    var usageResult: UsageFetchResult = .missingAuth
    func usage(for account: AccountRecord) async -> UsageFetchResult { usageResult }
    func accountNames(for scope: UserScope) async -> AccountNameFetchResult { .success(names) }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastHost: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastHost = request.url?.host
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct FeatureFixture {
    let root: URL
    let home: CodexHome

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        home = CodexHome(root: root.appending(path: ".codex", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: home.accounts, withIntermediateDirectories: true)
    }
}

private func authData(email: String, userID: String, accountID: String) throws -> Data {
    let token = makeJWT(email: email, userID: userID, accountID: accountID)
    return try JSONSerialization.data(withJSONObject: [
        "auth_mode": "chatgpt",
        "tokens": ["id_token": token, "access_token": "access", "account_id": accountID],
    ], options: [.sortedKeys])
}

private func makeJWT(email: String, userID: String, accountID: String) -> String {
    let payload: [String: Any] = [
        "email": email,
        "chatgpt_user_id": userID,
        "https://api.openai.com/auth": ["chatgpt_account_id": accountID],
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    let encoded = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return "header.\(encoded).signature"
}

private func record(_ id: String, remaining: Double, plan: PlanType = .pro) -> AccountRecord {
    AccountRecord(
        accountKey: AccountKey("u::\(id)"),
        chatGPTAccountID: id,
        chatGPTUserID: "u",
        email: "\(id)@example.com",
        plan: plan,
        authMode: .chatgpt,
        createdAt: Int64(remaining),
        lastUsage: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 100 - remaining, windowMinutes: 300),
            secondary: RateLimitWindow(usedPercent: 100 - remaining, windowMinutes: 10_080),
            planType: plan
        ),
        lastUsageAt: Int64(remaining)
    )
}
