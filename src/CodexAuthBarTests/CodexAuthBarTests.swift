import CodexAuthCore
import XCTest
@testable import CodexAuthBar

final class CodexAuthBarTests: XCTestCase {
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
