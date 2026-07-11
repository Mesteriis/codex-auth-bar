import Foundation
import Testing
@testable import CodexAuthCore

@Suite struct WidgetSnapshotTests {
    @Test func projectionContainsOnlySafeFieldsAndOrdersByAttention() throws {
        let active = widgetAccount(
            key: "user-active::account-active",
            email: "active@example.com",
            alias: "Personal",
            fiveHourUsed: 28,
            weeklyUsed: 54
        )
        let low = widgetAccount(
            key: "user-low::account-low",
            email: "low@example.com",
            alias: "Client",
            fiveHourUsed: 91,
            weeklyUsed: 70
        )
        let registry = RegistryV4(
            activeAccountKey: active.accountKey,
            accounts: [low, active]
        )

        let snapshot = WidgetSnapshotProjector.project(
            registry,
            generatedAt: Date(timeIntervalSince1970: 100),
            fallbackName: { "Account \($0)" }
        )

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.accounts.map(\.displayName) == ["Personal", "Client"])
        #expect(snapshot.accounts[0].isActive)
        #expect(snapshot.accounts[0].fiveHour?.remainingPercent == 72)

        let data = try JSONEncoder().encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in [
            "active@example.com", "low@example.com", "user-active",
            "account-active", "chatgpt_account_id", "email", "auth_mode",
            "access_token", "refresh_token", "OPENAI_API_KEY",
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test func unsafeNamesFallBackWithoutLeakingIdentity() {
        let account = widgetAccount(
            key: "user::account",
            email: "person@example.com",
            alias: "person@example.com",
            accountName: "sk-not-a-safe-widget-name",
            fiveHourUsed: 130,
            weeklyUsed: -10
        )

        let snapshot = WidgetSnapshotProjector.project(
            RegistryV4(accounts: [account]),
            fallbackName: { "Account \($0)" }
        )

        #expect(snapshot.accounts[0].displayName == "Account 1")
        #expect(snapshot.accounts[0].fiveHour?.remainingPercent == 0)
        #expect(snapshot.accounts[0].weekly?.remainingPercent == 100)
    }

    @Test func expiredWindowPresentsAsFullyAvailable() {
        let limit = WidgetLimitSnapshot(remainingPercent: 7, resetsAtSeconds: 100)
        #expect(limit.effectiveRemainingPercent(at: Date(timeIntervalSince1970: 99)) == 7)
        #expect(limit.effectiveRemainingPercent(at: Date(timeIntervalSince1970: 100)) == 100)
    }
}

private func widgetAccount(
    key: AccountKey,
    email: String,
    alias: String = "",
    accountName: String? = nil,
    fiveHourUsed: Double,
    weeklyUsed: Double
) -> AccountRecord {
    AccountRecord(
        accountKey: key,
        chatGPTAccountID: "synthetic-account",
        chatGPTUserID: "synthetic-user",
        email: email,
        alias: alias,
        accountName: accountName,
        plan: .pro,
        authMode: .chatgpt,
        lastUsage: RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: fiveHourUsed),
            secondary: RateLimitWindow(usedPercent: weeklyUsed)
        )
    )
}
