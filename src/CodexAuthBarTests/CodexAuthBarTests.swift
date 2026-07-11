import XCTest

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
}
