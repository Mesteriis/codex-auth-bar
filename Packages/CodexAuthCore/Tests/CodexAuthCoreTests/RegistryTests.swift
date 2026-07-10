import Foundation
import Testing
@testable import CodexAuthCore

struct RegistryTests {
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

    @Test func profileNamesRejectTraversal() {
        #expect(ProfileName("work") != nil)
        #expect(ProfileName("team_2") != nil)
        #expect(ProfileName("../work") == nil)
        #expect(ProfileName("") == nil)
        #expect(ProfileName("work.config") == nil)
    }
}
