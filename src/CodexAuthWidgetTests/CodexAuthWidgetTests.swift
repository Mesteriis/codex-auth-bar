import AppKit
import CodexAuthCore
import SwiftUI
import WidgetKit
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

    func testLedgerContentUsesAProtectedHorizontalInset() {
        XCTAssertEqual(WidgetLayoutMetrics.ledgerHorizontalInset, 12)
        XCTAssertGreaterThan(WidgetLayoutMetrics.ledgerHorizontalInset, 0)
    }

    func testPreviewLedgerIncludesReferenceLikeVariety() throws {
        let accounts = try XCTUnwrap(WidgetPreviewHarness.healthy(family: .systemLarge).snapshot?.accounts)
        XCTAssertEqual(accounts.map(\.plan), [.pro, .team, .enterprise, .team, .pro, .free])
        XCTAssertEqual(accounts.map { $0.fiveHour?.remainingPercent }, [72, 38, 91, 18, 57, nil])
        XCTAssertEqual(accounts.map { $0.weekly?.remainingPercent }, [46, 80, 63, 22, 34, nil])
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

        for key in ["5h", "Weekly", "ACCOUNT", "PLAN", "RESETS", "%@ limit unavailable", "data out of date", "Shows remaining Codex account limits."] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let russian = try XCTUnwrap(localizations["ru"] as? [String: Any])
            let unit = try XCTUnwrap(russian["stringUnit"] as? [String: Any])
            XCTAssertNotEqual(unit["value"] as? String, key)
        }
        XCTAssertNotNil(strings["Codex Auth Bar"])
    }

    @MainActor
    func testRenderSmallPrecisionLedger() throws {
        try assertRenderAttachment(for: .systemSmall, name: "widget-small-dark")
    }

    @MainActor
    func testRenderMediumPrecisionLedger() throws {
        try assertRenderAttachment(for: .systemMedium, name: "widget-medium-dark")
    }

    @MainActor
    func testRenderLargePrecisionLedger() throws {
        try assertRenderAttachment(for: .systemLarge, name: "widget-large-dark")
    }

    @MainActor
    private func assertRenderAttachment(for family: WidgetFamily, name: String) throws {
        let size = WidgetRenderFixture.size(for: family)
        XCTAssertEqual(
            WidgetPreviewHarness.healthy(family: family).snapshot?.accounts.count,
            WidgetRenderFixture.accountCount(for: family)
        )
        let view = WidgetPreviewHarness.view(family: family, colorScheme: .dark)
        let renderer = ImageRenderer(
            content: ZStack {
                WidgetRenderFixture.darkCanvas
                view
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = WidgetRenderFixture.scale

        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(
            NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        )
        XCTAssertFalse(png.isEmpty)

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

private enum WidgetRenderFixture {
    static let scale: CGFloat = 2
    static let darkCanvas = Color(red: 0.10, green: 0.12, blue: 0.16)

    static func size(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall:
            CGSize(width: 158, height: 158)
        case .systemMedium:
            CGSize(width: 338, height: 158)
        case .systemLarge:
            CGSize(width: 338, height: 354)
        default:
            CGSize(width: 158, height: 158)
        }
    }

    static func accountCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 3
        case .systemLarge: 6
        default: 1
        }
    }
}
