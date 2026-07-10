import Foundation
import Testing
@testable import CodexAuthCore

struct StorageAndWorkflowTests {
    @Test func commitUsesPrivatePermissionsAndDetectsConcurrentEdit() async throws {
        let fixture = try TemporaryCodexHome()
        let store = RegistryStore(home: fixture.home)
        let initial = try await store.load()
        let firstFingerprint = try await store.commit(RegistryV4(), expected: initial.fingerprint)

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.home.registry.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(mode == 0o600)

        try Data("{}".utf8).write(to: fixture.home.registry)
        await #expect(throws: StorageError.concurrentModification) {
            _ = try await store.commit(RegistryV4(), expected: firstFingerprint)
        }
    }

    @Test func switchUpdatesAuthPreviousAndBackup() async throws {
        let fixture = try TemporaryCodexHome()
        let first = account("first", email: "first@example.com")
        let second = account("second", email: "second@example.com")
        try fixture.writeSnapshot(first.accountKey, text: "first-auth")
        try fixture.writeSnapshot(second.accountKey, text: "second-auth")
        try Data("first-auth".utf8).write(to: fixture.home.auth)

        let store = RegistryStore(home: fixture.home)
        let loaded = try await store.load()
        _ = try await store.commit(
            RegistryV4(activeAccountKey: first.accountKey, accounts: [first, second]),
            expected: loaded.fingerprint
        )
        let repository = AccountRepository(home: fixture.home, store: store)

        let receipt = try await repository.switchAccount(to: second.accountKey)
        let state = try await repository.state(refresh: .stored)

        #expect(receipt.selectedAccountKey == second.accountKey)
        #expect(String(decoding: try Data(contentsOf: fixture.home.auth), as: UTF8.self) == "second-auth")
        #expect(state.registry.activeAccountKey == second.accountKey)
        #expect(state.registry.previousActiveAccountKey == first.accountKey)
        #expect(try fixture.authBackups().count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.home.transactionJournal.path))
    }

    @Test func aliasesAreUniqueCaseInsensitively() async throws {
        let fixture = try TemporaryCodexHome()
        let first = account("first", email: "first@example.com", alias: "Work")
        let second = account("second", email: "second@example.com")
        let store = RegistryStore(home: fixture.home)
        let loaded = try await store.load()
        _ = try await store.commit(RegistryV4(accounts: [first, second]), expected: loaded.fingerprint)
        let repository = AccountRepository(home: fixture.home, store: store)

        await #expect(throws: AccountError.duplicateAlias) {
            try await repository.setAlias("work", for: second.accountKey)
        }
        await #expect(throws: AccountError.invalidAlias) {
            try await repository.setAlias("123", for: second.accountKey)
        }
    }

    @Test func cleanPreservesExportDirectory() async throws {
        let fixture = try TemporaryCodexHome()
        try FileManager.default.createDirectory(at: fixture.home.exportBackup, withIntermediateDirectories: true)
        try Data("export".utf8).write(to: fixture.home.exportBackup.appending(path: "saved.auth.json"))
        try Data("stale".utf8).write(to: fixture.home.accounts.appending(path: "stale.auth.json"))
        let store = RegistryStore(home: fixture.home)
        let loaded = try await store.load()
        _ = try await store.commit(RegistryV4(), expected: loaded.fingerprint)
        let repository = AccountRepository(home: fixture.home, store: store)

        let report = try await repository.clean()

        #expect(report.deletedFiles.contains("stale.auth.json"))
        #expect(FileManager.default.fileExists(atPath: fixture.home.exportBackup.appending(path: "saved.auth.json").path))
    }
}

private func account(_ id: String, email: String, alias: String = "") -> AccountRecord {
    AccountRecord(
        accountKey: AccountKey("user::\(id)"),
        chatGPTAccountID: id,
        chatGPTUserID: "user",
        email: email,
        alias: alias,
        authMode: .chatgpt,
        createdAt: 1
    )
}

private struct TemporaryCodexHome {
    let root: URL
    let home: CodexHome

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        home = CodexHome(root: root)
        try FileManager.default.createDirectory(at: home.accounts, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    func writeSnapshot(_ key: AccountKey, text: String) throws {
        try Data(text.utf8).write(to: home.snapshot(for: key))
    }

    func authBackups() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: home.accounts, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("auth.json.bak.") }
    }
}
