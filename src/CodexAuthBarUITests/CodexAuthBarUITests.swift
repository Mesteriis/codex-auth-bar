import XCTest

@MainActor
final class CodexAuthBarUITests: XCTestCase {
    func testMenuBarAppLaunches() {
        let app = XCUIApplication()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        app.launchEnvironment["CODEX_HOME"] = temporary.path
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertEqual(app.state, .runningBackground)
    }

    func testMenuBarPopoverSupportsKeyboardNavigation() throws {
        let app = XCUIApplication()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try seedRegistry(at: temporary)
        app.launchEnvironment["CODEX_HOME"] = temporary.path
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let appStatusItem = app.menuBars.statusItems["Codex Auth Bar"]
        let systemStatusItem = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
            .menuBars.statusItems["Codex Auth Bar"]
        let statusItem = appStatusItem.waitForExistence(timeout: 3) ? appStatusItem : systemStatusItem
        guard statusItem.waitForExistence(timeout: 5) else {
            throw XCTSkip("The host did not expose MenuBarExtra through XCTest accessibility")
        }
        statusItem.click()

        let search = app.textFields["CodexAuthBar.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("work")
        let accountButton = app.buttons["CodexAuthBar.account.test-user::test-account"]
        XCTAssertTrue(accountButton.waitForExistence(timeout: 2))
        XCTAssertTrue(
            ["Switch to work", "Переключиться на work"].contains(accountButton.label),
            "Unexpected VoiceOver label: \(accountButton.label)"
        )
        search.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["CodexAuthBar.previous"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["CodexAuthBar.manage"].waitForExistence(timeout: 2))
    }

    private func seedRegistry(at home: URL) throws {
        let accounts = home.appendingPathComponent("accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: accounts, withIntermediateDirectories: true)
        let registry: [String: Any] = [
            "schema_version": 4,
            "interval_seconds": 60,
            "accounts": [[
                "account_key": "test-user::test-account",
                "chatgpt_account_id": "test-account",
                "chatgpt_user_id": "test-user",
                "email": "work@example.com",
                "alias": "work",
                "auth_mode": "chatgpt",
                "created_at": 1,
            ]],
        ]
        try JSONSerialization.data(withJSONObject: registry)
            .write(to: accounts.appendingPathComponent("registry.json"))
    }
}
