import XCTest

final class CodexAuthBarTests: XCTestCase {
    func testApplicationBundleIdentifierContract() {
        XCTAssertEqual("com.mesteriis.CodexAuthBar", "com.mesteriis.CodexAuthBar")
    }
}
