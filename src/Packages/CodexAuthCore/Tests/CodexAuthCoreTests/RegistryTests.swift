import Foundation
import Testing
@testable import CodexAuthCore

struct RegistryTests {
    @Test func migratesV2SnapshotsToRecordKeysAndRewritesRegistry() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let home = CodexHome(root: root)
        try FileManager.default.createDirectory(at: home.accounts, withIntermediateDirectories: true)
        let email = "legacy@example.com"
        let legacyName = Data(email.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") + ".auth.json"
        let auth = try registryAuthData(email: email, userID: "legacy-user", accountID: "legacy-account")
        let legacySnapshot = home.accounts.appending(path: legacyName)
        try auth.write(to: legacySnapshot)
        try Data(#"{"version":2,"active_email":"legacy@example.com","accounts":[{"email":"legacy@example.com","alias":"work","created_at":10}]}"#.utf8).write(to: home.registry)
        let store = RegistryStore(home: home)

        let loaded = try await store.load()
        let record = try #require(loaded.registry.accounts.first)
        let rewritten = String(decoding: try Data(contentsOf: home.registry), as: UTF8.self)

        #expect(record.accountKey == AccountKey("legacy-user::legacy-account"))
        #expect(record.alias == "work")
        #expect(loaded.registry.activeAccountKey == record.accountKey)
        #expect(try Data(contentsOf: home.snapshot(for: record.accountKey)) == auth)
        #expect(!FileManager.default.fileExists(atPath: legacySnapshot.path))
        #expect(rewritten.contains(#""schema_version" : 4"#))
        #expect(try registryBackups(home).count == 1)
    }

    @Test func migratesV3LiveIntervalAndRemovesObsoleteBlocks() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let home = CodexHome(root: root)
        try FileManager.default.createDirectory(at: home.accounts, withIntermediateDirectories: true)
        let data = Data(#"{"version":3,"active_account_key":"u::a","live":{"interval_seconds":90},"api":{"enabled":false},"auto_switch":{"enabled":true},"accounts":[{"account_key":"u::a","chatgpt_account_id":"a","chatgpt_user_id":"u","email":"user@example.com","alias":"","created_at":1}]}"#.utf8)
        try data.write(to: home.registry)
        let store = RegistryStore(home: home)

        let loaded = try await store.load()
        let rewritten = String(decoding: try Data(contentsOf: home.registry), as: UTF8.self)

        #expect(loaded.registry.intervalSeconds == 90)
        #expect(loaded.registry.schemaVersion == 4)
        #expect(rewritten.contains(#""schema_version" : 4"#))
        #expect(!rewritten.contains(#""live""#))
        #expect(!rewritten.contains(#""api""#))
        #expect(!rewritten.contains(#""auto_switch""#))
        #expect(try registryBackups(home).count == 1)
    }

    @Test func registryV4RoundTripsSnakeCaseFields() throws {
        let record = AccountRecord(
            accountKey: AccountKey("user::account"),
            chatGPTAccountID: "account",
            chatGPTUserID: "user",
            email: "user@example.com",
            alias: "work",
            accountName: "Workspace",
            plan: .team,
            authMode: .chatgpt,
            createdAt: 100,
            lastUsedAt: 200
        )
        let registry = RegistryV4(
            activeAccountKey: record.accountKey,
            previousActiveAccountKey: nil,
            activeAccountActivatedAtMilliseconds: 300_000,
            intervalSeconds: 60,
            accounts: [record]
        )

        let data = try RegistryCodec.encode(registry)
        let text = String(decoding: data, as: UTF8.self)
        let decoded = try RegistryCodec.decode(data)

        #expect(text.contains("\"schema_version\""))
        #expect(text.contains("\"active_account_key\""))
        #expect(decoded == registry)
    }

    @Test func rejectsFutureSchema() throws {
        let data = Data(#"{"schema_version":5,"accounts":[]}"#.utf8)

        #expect(throws: RegistryError.unsupportedSchema(5)) {
            try RegistryCodec.decode(data)
        }
    }

    @Test func storeRejectsFutureSchemaWithoutChangingAnyBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let home = CodexHome(root: root)
        try FileManager.default.createDirectory(at: home.accounts, withIntermediateDirectories: true)
        let original = Data(#"{"schema_version":5,"accounts":[],"future":"preserve"}"#.utf8)
        try original.write(to: home.registry)
        let store = RegistryStore(home: home)

        await #expect(throws: RegistryError.unsupportedSchema(5)) {
            _ = try await store.load()
        }

        #expect(try Data(contentsOf: home.registry) == original)
        #expect(try registryBackups(home).isEmpty)
    }

    @Test func profileNamesRejectTraversal() {
        #expect(ProfileName("work") != nil)
        #expect(ProfileName("team_2") != nil)
        #expect(ProfileName("../work") == nil)
        #expect(ProfileName("") == nil)
        #expect(ProfileName("work.config") == nil)
    }
}

private func registryBackups(_ home: CodexHome) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: home.accounts, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("registry.json.bak.") }
}

private func registryAuthData(email: String, userID: String, accountID: String) throws -> Data {
    let payload: [String: Any] = [
        "email": email,
        "chatgpt_user_id": userID,
        "https://api.openai.com/auth": ["chatgpt_account_id": accountID],
    ]
    let payloadData = try JSONSerialization.data(withJSONObject: payload)
    let encoded = payloadData.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return try JSONSerialization.data(withJSONObject: [
        "auth_mode": "chatgpt",
        "tokens": ["id_token": "header.\(encoded).signature", "access_token": "access", "account_id": accountID],
    ], options: [.sortedKeys])
}
