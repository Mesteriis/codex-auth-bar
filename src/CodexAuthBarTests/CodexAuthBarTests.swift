import CodexAuthCore
import XCTest
@testable import CodexAuthBar

final class CodexAuthBarTests: XCTestCase {
    func testAutomaticWidgetReloadsAreCoalescedForFifteenMinutes() async throws {
        let store = RecordingWidgetStore()
        let reloader = RecordingWidgetReloader()
        let publisher = WidgetSnapshotPublisher(
            store: store,
            reloader: reloader,
            fallbackName: { "Account \($0)" }
        )

        try await publisher.publish(
            registry: syntheticWidgetRegistry(alias: "First"),
            reason: .automatic,
            now: Date(timeIntervalSince1970: 0)
        )
        try await publisher.publish(
            registry: syntheticWidgetRegistry(alias: "Second"),
            reason: .automatic,
            now: Date(timeIntervalSince1970: 14 * 60)
        )
        try await publisher.publish(
            registry: syntheticWidgetRegistry(alias: "Third"),
            reason: .automatic,
            now: Date(timeIntervalSince1970: 15 * 60)
        )

        let reloadCount = await reloader.reloadCount
        let writeCount = await store.writeCount
        XCTAssertEqual(reloadCount, 2)
        XCTAssertEqual(writeCount, 3)
    }

    func testManualRefreshReloadsAndAdvancesFreshnessEvenWhenValuesMatch() async throws {
        let store = RecordingWidgetStore()
        let reloader = RecordingWidgetReloader()
        let publisher = WidgetSnapshotPublisher(
            store: store,
            reloader: reloader,
            fallbackName: { "Account \($0)" }
        )
        let registry = syntheticWidgetRegistry(alias: "Personal")

        try await publisher.publish(
            registry: registry,
            reason: .manualRefresh,
            now: Date(timeIntervalSince1970: 0)
        )
        try await publisher.publish(
            registry: registry,
            reason: .manualRefresh,
            now: Date(timeIntervalSince1970: 60)
        )

        let writeCount = await store.writeCount
        let reloadCount = await reloader.reloadCount
        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(reloadCount, 2)
    }

    func testConcurrentAutomaticPublishesReserveOneReloadWindow() async throws {
        let store = CoordinatedWidgetStore()
        let reloader = BlockingWidgetReloader()
        let publisher = WidgetSnapshotPublisher(
            store: store,
            reloader: reloader,
            fallbackName: { "Account \($0)" }
        )

        let first = Task {
            try await publisher.publish(
                registry: syntheticWidgetRegistry(alias: "First"),
                reason: .automatic,
                now: Date(timeIntervalSince1970: 0)
            )
        }
        await reloader.waitForFirstReload()

        let second = Task {
            try await publisher.publish(
                registry: syntheticWidgetRegistry(alias: "Second"),
                reason: .automatic,
                now: Date(timeIntervalSince1970: 1)
            )
        }
        await store.waitForWriteCount(2)
        await Task.yield()

        let reloadCountWhileBlocked = await reloader.reloadCount
        XCTAssertEqual(reloadCountWhileBlocked, 1)
        await reloader.releaseFirstReload()
        try await first.value
        try await second.value
    }

    func testForcedPublishDuringReloadDrainsFollowUpReload() async throws {
        let store = CoordinatedWidgetStore()
        let reloader = BlockingWidgetReloader()
        let publisher = WidgetSnapshotPublisher(
            store: store,
            reloader: reloader,
            fallbackName: { "Account \($0)" }
        )

        let first = Task {
            try await publisher.publish(
                registry: syntheticWidgetRegistry(alias: "First"),
                reason: .automatic,
                now: Date(timeIntervalSince1970: 0)
            )
        }
        await reloader.waitForFirstReload()

        let second = Task {
            try await publisher.publish(
                registry: syntheticWidgetRegistry(alias: "Second"),
                reason: .structural,
                now: Date(timeIntervalSince1970: 1)
            )
        }
        await store.waitForWriteCount(2)
        await reloader.releaseFirstReload()
        try await first.value
        try await second.value

        let reloadCount = await reloader.reloadCount
        XCTAssertEqual(reloadCount, 2)
    }

    func testAutomaticPublishRetriesAfterReloadFailureWithoutRewritingSnapshot() async throws {
        let store = RecordingWidgetStore()
        let reloader = FailingOnceWidgetReloader()
        let publisher = WidgetSnapshotPublisher(
            store: store,
            reloader: reloader,
            fallbackName: { "Account \($0)" }
        )
        let registry = syntheticWidgetRegistry(alias: "Personal")

        do {
            try await publisher.publish(
                registry: registry,
                reason: .automatic,
                now: Date(timeIntervalSince1970: 0)
            )
            XCTFail("Expected the injected reload to fail")
        } catch PublisherTestError.injectedFailure {}

        try await publisher.publish(
            registry: registry,
            reason: .automatic,
            now: Date(timeIntervalSince1970: 1)
        )

        let writeCount = await store.writeCount
        let reloadCount = await reloader.reloadCount
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(reloadCount, 2)
    }

    func testAutomaticPublishRetriesAfterWriteFailure() async throws {
        let store = FailingOnceWidgetStore()
        let reloader = RecordingWidgetReloader()
        let publisher = WidgetSnapshotPublisher(
            store: store,
            reloader: reloader,
            fallbackName: { "Account \($0)" }
        )
        let registry = syntheticWidgetRegistry(alias: "Personal")

        do {
            try await publisher.publish(
                registry: registry,
                reason: .automatic,
                now: Date(timeIntervalSince1970: 0)
            )
            XCTFail("Expected the injected write to fail")
        } catch PublisherTestError.injectedFailure {}

        try await publisher.publish(
            registry: registry,
            reason: .automatic,
            now: Date(timeIntervalSince1970: 1)
        )

        let writeCount = await store.writeCount
        let reloadCount = await reloader.reloadCount
        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(reloadCount, 1)
    }

    func testWidgetDeepLinkAcceptsOnlyAccountsRoute() {
        XCTAssertEqual(WidgetDeepLink(URL(string: "codexauthbar://accounts")!), .accounts)
        XCTAssertNil(WidgetDeepLink(URL(string: "https://example.com")!))
        XCTAssertNil(WidgetDeepLink(URL(string: "codexauthbar://switch/account")!))
        XCTAssertNil(WidgetDeepLink(URL(string: "codexauthbar://accounts?account=secret")!))
    }

    func testApplicationBundleIdentifierContract() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.mesteriis.CodexAuthBar")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }

    func testRussianLocalizationIsBundled() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let russian = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(russian.localizedString(forKey: "Accounts", value: nil, table: nil), "Аккаунты")
    }

    func testFailedLoginLeavesLiveAuthByteIdenticalAndRemovesScratch() async throws {
        let fixture = try LoginFixture(script: "echo synthetic-failure >&2\nexit 7\n")
        defer { fixture.cleanup() }
        let original = Data("live-auth-must-not-change".utf8)
        try original.write(to: fixture.home.auth)
        let controller = CodexProcessController(home: fixture.home, explicitExecutable: URL(fileURLWithPath: "/usr/bin/false"))

        do {
            _ = try await controller.performLogin(.browser)
            XCTFail("Expected the fake login to fail")
        } catch {}

        XCTAssertEqual(try Data(contentsOf: fixture.home.auth), original)
        XCTAssertTrue(try fixture.loginScratchDirectories().isEmpty)
    }

    func testCancelledLoginLeavesLiveAuthByteIdenticalAndRemovesScratch() async throws {
        let fixture = try LoginFixture(script: "sleep 10\n")
        defer { fixture.cleanup() }
        let original = Data("live-auth-must-not-change".utf8)
        try original.write(to: fixture.home.auth)
        let controller = CodexProcessController(home: fixture.home, explicitExecutable: fixture.executable)
        let login = Task { try await controller.performLogin(.browser) }
        try await Task.sleep(for: .milliseconds(150))

        await controller.cancelLogin()
        do {
            _ = try await login.value
            XCTFail("Expected the cancelled login to fail")
        } catch {}

        XCTAssertEqual(try Data(contentsOf: fixture.home.auth), original)
        XCTAssertTrue(try fixture.loginScratchDirectories().isEmpty)
    }

    func testAPIKeyLoginUsesStdinAndScratchHomeOnly() async throws {
        let fixture = try LoginFixture(script: "exit 1\n")
        defer { fixture.cleanup() }
        let evidence = fixture.root.appending(path: "stdin-evidence")
        let script = """
        #!/bin/sh
        case " $* " in *test-key*) exit 21;; esac
        if env | grep -q 'test-key'; then exit 22; fi
        IFS= read -r key
        [ "$key" = 'test-key' ] || exit 23
        printf '%s' "$key" > '\(evidence.path)'
        printf '%s' '{"OPENAI_API_KEY":"test-key"}' > "$CODEX_HOME/auth.json"
        """
        try Data(script.utf8).write(to: fixture.executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.executable.path)
        let original = Data("live-auth-must-not-change".utf8)
        try original.write(to: fixture.home.auth)
        let controller = CodexProcessController(home: fixture.home, explicitExecutable: fixture.executable)

        let artifact = try await controller.performLogin(.apiKey("test-key"))
        defer { try? FileManager.default.removeItem(at: artifact.authURL) }

        XCTAssertEqual(try String(contentsOf: evidence, encoding: .utf8), "test-key")
        XCTAssertEqual(try Data(contentsOf: fixture.home.auth), original)
        XCTAssertTrue(try fixture.loginScratchDirectories().isEmpty)
        XCTAssertTrue(try String(contentsOf: artifact.authURL, encoding: .utf8).contains("test-key"))
    }

    func testExplicitNonFileConfigIsBlockedWhenDoctorIsUnavailable() async throws {
        let fixture = try LoginFixture(script: """
        case "$1" in
          --version) echo 'codex 0.1.0' ;;
          --help) echo 'Usage: codex' ;;
          *) exit 2 ;;
        esac
        """)
        defer { fixture.cleanup() }
        try Data(#"cli_auth_credentials_store = "keyring""#.utf8)
            .write(to: fixture.home.root.appending(path: "config.toml"))
        let controller = CodexProcessController(home: fixture.home, explicitExecutable: fixture.executable)

        do {
            try await controller.ensureFileCredentialStore()
            XCTFail("Expected explicit keyring storage to block file switching")
        } catch ProcessError.incompatibleCredentialStore(.keyring) {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor RecordingWidgetStore: WidgetSnapshotWriting {
    private(set) var writeCount = 0

    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws {
        writeCount += 1
    }
}

private actor RecordingWidgetReloader: WidgetTimelineReloading {
    private(set) var reloadCount = 0

    func reload() async throws {
        reloadCount += 1
    }
}

private enum PublisherTestError: Error {
    case injectedFailure
}

private actor CoordinatedWidgetStore: WidgetSnapshotWriting {
    private(set) var writeCount = 0
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws {
        writeCount += 1
        let ready = waiters.removeValue(forKey: writeCount) ?? []
        ready.forEach { $0.resume() }
    }

    func waitForWriteCount(_ target: Int) async {
        guard writeCount < target else { return }
        await withCheckedContinuation { continuation in
            waiters[target, default: []].append(continuation)
        }
    }
}

private actor BlockingWidgetReloader: WidgetTimelineReloading {
    private(set) var reloadCount = 0
    private var firstReloadStarted: CheckedContinuation<Void, Never>?
    private var firstReloadRelease: CheckedContinuation<Void, Never>?

    func reload() async throws {
        reloadCount += 1
        if reloadCount == 1 {
            firstReloadStarted?.resume()
            firstReloadStarted = nil
            await withCheckedContinuation { firstReloadRelease = $0 }
        }
    }

    func waitForFirstReload() async {
        guard reloadCount == 0 else { return }
        await withCheckedContinuation { firstReloadStarted = $0 }
    }

    func releaseFirstReload() {
        firstReloadRelease?.resume()
        firstReloadRelease = nil
    }
}

private actor FailingOnceWidgetReloader: WidgetTimelineReloading {
    private(set) var reloadCount = 0

    func reload() async throws {
        reloadCount += 1
        if reloadCount == 1 { throw PublisherTestError.injectedFailure }
    }
}

private actor FailingOnceWidgetStore: WidgetSnapshotWriting {
    private(set) var writeCount = 0

    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws {
        writeCount += 1
        if writeCount == 1 { throw PublisherTestError.injectedFailure }
    }
}

private func syntheticWidgetRegistry(alias: String) -> RegistryV4 {
    let account = AccountRecord(
        accountKey: AccountKey("synthetic-user::synthetic-account"),
        chatGPTAccountID: "synthetic-account",
        chatGPTUserID: "synthetic-user",
        email: "person@example.com",
        alias: alias,
        plan: .pro,
        authMode: .chatgpt
    )
    return RegistryV4(activeAccountKey: account.accountKey, accounts: [account])
}

private struct LoginFixture {
    let root: URL
    let home: CodexHome
    let executable: URL

    init(script: String) throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        home = CodexHome(root: root.appending(path: ".codex", directoryHint: .isDirectory))
        executable = root.appending(path: "fake-codex")
        try FileManager.default.createDirectory(at: home.accounts, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n\(script)".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func loginScratchDirectories() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: home.accounts, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("login-") }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
