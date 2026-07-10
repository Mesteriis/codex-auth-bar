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
}
