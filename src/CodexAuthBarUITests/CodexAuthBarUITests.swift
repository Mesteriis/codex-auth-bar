import XCTest

@MainActor
final class CodexAuthBarUITests: XCTestCase {
    func testMenuBarAppLaunches() {
        let app = XCUIApplication()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app.launchEnvironment["CODEX_HOME"] = temporary.path
        app.launch()
        XCTAssertEqual(app.state, .runningBackground)
    }

    func testMenuBarPopoverSupportsKeyboardNavigation() throws {
        let app = XCUIApplication()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app.launchEnvironment["CODEX_HOME"] = temporary.path
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
        search.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["CodexAuthBar.previous"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["CodexAuthBar.manage"].waitForExistence(timeout: 2))
    }
}
