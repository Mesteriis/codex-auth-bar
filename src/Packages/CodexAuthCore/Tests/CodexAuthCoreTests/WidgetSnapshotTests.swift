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

    @Test func rawIdentityCandidatesFallBackToOrdinalName() {
        for candidate in ["identity-key", "synthetic-account", "synthetic-user"] {
            let account = widgetAccount(
                key: "identity-key",
                email: "person@example.com",
                alias: candidate,
                fiveHourUsed: 0,
                weeklyUsed: 0
            )

            let snapshot = WidgetSnapshotProjector.project(
                RegistryV4(accounts: [account]),
                fallbackName: { "Account \($0)" }
            )

            #expect(snapshot.accounts[0].displayName == "Account 1")
        }
    }

    @Test func unsafeCallerFallbackFallsBackToOrdinalName() {
        let account = widgetAccount(
            key: "identity-key",
            email: "person@example.com",
            fiveHourUsed: 0,
            weeklyUsed: 0
        )
        let unsafeFallbacks = [
            account.email,
            account.accountKey.rawValue,
            account.chatGPTAccountID,
            account.chatGPTUserID,
            "sk-not-a-safe-widget-name",
        ]

        for fallback in unsafeFallbacks {
            let snapshot = WidgetSnapshotProjector.project(
                RegistryV4(accounts: [account]),
                fallbackName: { _ in fallback }
            )

            #expect(snapshot.accounts[0].displayName == "Account 1")
        }
    }

    @Test func expiredWindowPresentsAsFullyAvailable() {
        let limit = WidgetLimitSnapshot(remainingPercent: 7, resetsAtSeconds: 100)
        #expect(limit.effectiveRemainingPercent(at: Date(timeIntervalSince1970: 99)) == 7)
        #expect(limit.effectiveRemainingPercent(at: Date(timeIntervalSince1970: 100)) == 100)
    }

    @Test func widgetStoreRoundTripsPrivateAtomicSnapshot() throws {
        let root = try temporaryDirectory()
        let store = WidgetSnapshotStore(containerURL: root)
        let snapshot = WidgetSnapshot(
            generatedAtMilliseconds: 1,
            accounts: []
        )

        try store.write(snapshot)

        #expect(try store.load() == snapshot)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.snapshotURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func widgetStoreRejectsFutureSchemaWithoutChangingBytes() throws {
        let root = try temporaryDirectory()
        let store = WidgetSnapshotStore(containerURL: root)
        try store.write(WidgetSnapshot(generatedAtMilliseconds: 1, accounts: []))
        let original = try Data(contentsOf: store.snapshotURL)
        let future = Data(#"{"schema_version":2,"generated_at_ms":2,"accounts":[]}"#.utf8)
        try future.write(to: store.snapshotURL)

        #expect(throws: WidgetSnapshotStoreError.unsupportedSchema(2)) {
            _ = try store.load()
        }
        #expect(try Data(contentsOf: store.snapshotURL) == future)
        #expect(original != future)
    }

    @Test func widgetStoreRejectsSymlinkSnapshot() throws {
        let root = try temporaryDirectory()
        let store = WidgetSnapshotStore(containerURL: root)
        try FileManager.default.createDirectory(
            at: store.snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: store.snapshotURL,
            withDestinationURL: root.appending(path: "outside.json")
        )
        #expect(throws: StorageError.self) { _ = try store.load() }
    }
}

private func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
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
