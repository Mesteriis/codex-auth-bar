import CodexAuthCore
import XCTest

final class CodexAuthWidgetTests: XCTestCase {
    func testTimelineRefreshesInThirtyMinutesAndIncludesSpacedResets() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = widgetSnapshot(
            resets: [
                now.addingTimeInterval(4 * 60),
                now.addingTimeInterval(10 * 60),
                now.addingTimeInterval(20 * 60),
            ]
        )

        let result = WidgetTimelineBuilder.build(snapshot: snapshot, now: now)

        XCTAssertEqual(result.reloadDate, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(result.entries.map(\.date), [
            now,
            now.addingTimeInterval(10 * 60),
            now.addingTimeInterval(20 * 60),
        ])
    }

    func testFamilyCapacityIsOneThreeAndSix() {
        let snapshot = widgetSnapshot(accountCount: 8)

        XCTAssertEqual(WidgetPresentation(snapshot, family: .systemSmall).accounts.count, 1)
        XCTAssertEqual(WidgetPresentation(snapshot, family: .systemMedium).accounts.count, 3)
        XCTAssertEqual(WidgetPresentation(snapshot, family: .systemLarge).accounts.count, 6)
        XCTAssertEqual(WidgetPresentation(snapshot, family: .systemLarge).hiddenCount, 2)
    }

    func testFreshnessBoundaries() {
        let now = Date(timeIntervalSince1970: 100_000)

        XCTAssertEqual(
            WidgetFreshness.resolve(generatedAt: now.addingTimeInterval(-119 * 60), now: now),
            .fresh
        )
        XCTAssertEqual(
            WidgetFreshness.resolve(generatedAt: now.addingTimeInterval(-2 * 60 * 60), now: now),
            .aging
        )
        XCTAssertEqual(
            WidgetFreshness.resolve(generatedAt: now.addingTimeInterval(-24 * 60 * 60), now: now),
            .stale
        )
    }

    func testRingSemanticsUseWarningAndCriticalThresholds() {
        XCTAssertEqual(LimitSeverity(remaining: nil), .unavailable)
        XCTAssertEqual(LimitSeverity(remaining: 20), .normal)
        XCTAssertEqual(LimitSeverity(remaining: 19), .warning)
        XCTAssertEqual(LimitSeverity(remaining: 10), .warning)
        XCTAssertEqual(LimitSeverity(remaining: 9), .critical)
    }

    func testAccessibilityValueIncludesNumberResetAndStaleness() {
        let value = LimitAccessibility.accountValue(fiveHourRemaining: 72, weeklyRemaining: nil, reset: Date(timeIntervalSince1970: 7_200), now: Date(timeIntervalSince1970: 0), freshness: .aging, locale: Locale(identifier: "en"))
        XCTAssertTrue(value.contains("72"))
        XCTAssertTrue(value.localizedCaseInsensitiveContains("remaining"))
        XCTAssertTrue(value.localizedCaseInsensitiveContains("out of date"))
        XCTAssertTrue(value.localizedCaseInsensitiveContains("weekly"))
        XCTAssertTrue(value.localizedCaseInsensitiveContains("unavailable"))
    }

    func testRussianCatalogCoversLimitLabelsAndUnavailableCopy() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let catalogURL = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CodexAuthWidget/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])

        for key in ["5h", "Weekly", "%@ limit unavailable", "data out of date", "Shows remaining Codex account limits."] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let russian = try XCTUnwrap(localizations["ru"] as? [String: Any])
            let unit = try XCTUnwrap(russian["stringUnit"] as? [String: Any])
            XCTAssertNotEqual(unit["value"] as? String, key)
        }
    }

    private func widgetSnapshot(
        accountCount: Int = 1,
        resets: [Date] = []
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAtMilliseconds: 0,
            accounts: (0..<max(accountCount, resets.count)).map { index in
                WidgetAccountSnapshot(
                    id: "account-\(index)",
                    displayName: "Account \(index + 1)",
                    plan: nil,
                    isActive: index == 0,
                    fiveHour: resets.indices.contains(index)
                        ? WidgetLimitSnapshot(
                            remainingPercent: 50,
                            resetsAtSeconds: Int64(resets[index].timeIntervalSince1970)
                        )
                        : nil,
                    weekly: nil
                )
            }
        )
    }
}
