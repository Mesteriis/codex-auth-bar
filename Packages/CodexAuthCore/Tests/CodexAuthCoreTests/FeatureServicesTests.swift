import CryptoKit
import Foundation
import Testing
@testable import CodexAuthCore

struct FeatureServicesTests {
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

    @Test func autoSwitchUsesFreeGuardAndBestCandidate() {
        let active = record("active", remaining: 30, plan: .free)
        let good = record("good", remaining: 90)
        let better = record("better", remaining: 95)
        let registry = RegistryV4(activeAccountKey: active.accountKey, accounts: [active, good, better])

        let decision = AutoSwitchPolicy().decision(registry: registry, thresholds: .init(fiveHour: 10, weekly: 5))

        #expect(decision?.target == better.accountKey)
    }

    @Test func profileStoreManagesOnlyValidProfileFiles() async throws {
        let fixture = try FeatureFixture()
        let store = ProfileStore(home: fixture.home)

        try await store.create(ProfileName("work")!)
        try Data().write(to: fixture.home.root.appending(path: "not a profile.config.toml"))
        let profiles = try await store.list()
        try await store.rename(ProfileName("work")!, to: ProfileName("team")!)

        #expect(profiles == [ProfileName("work")!])
        #expect(FileManager.default.fileExists(atPath: fixture.home.root.appending(path: "team.config.toml").path))
    }

    @Test func codextManifestRejectsWrongHash() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("binary".utf8).write(to: file)
        let manifest = CodextArtifact(architecture: .arm64, url: URL(string: "https://github.com/example/archive.tar.gz")!, sha256: String(repeating: "0", count: 64), size: 6)

        #expect(throws: CodextError.hashMismatch) {
            try CodextVerifier.verify(file: file, artifact: manifest)
        }
    }
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
