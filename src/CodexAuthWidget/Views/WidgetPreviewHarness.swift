import CodexAuthCore
import SwiftUI
import WidgetKit

enum WidgetPreviewHarness {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static func entry(remaining: Double? = 72, freshnessAge: TimeInterval = 0, count: Int = 1) -> CodexWidgetEntry {
        let names = ["Personal", "Work", "Research Lab", "Client Projects", "Long Account Name Example", "Legacy Sandbox"]
        let plans: [PlanType?] = [.pro, .team, .enterprise, .team, .pro, .free]
        let fiveHour = [72.0, 38.0, 91.0, 18.0, 57.0, nil]
        let weekly = [46.0, 80.0, 63.0, 22.0, 34.0, nil]
        let resetHours = [62.0, 131.0, 30.0, 6.7, 81.0, nil]
        let accounts = (0..<count).map { index in
            let fixtureIndex = index % names.count
            let fiveHourRemaining = remaining == 72 ? fiveHour[fixtureIndex] : remaining
            let weeklyRemaining = remaining == 72 ? weekly[fixtureIndex] : remaining
            return WidgetAccountSnapshot(
                id: "preview-\(index)",
                displayName: names[fixtureIndex],
                plan: plans[fixtureIndex],
                isActive: index == 0,
                fiveHour: fiveHourRemaining.map { WidgetLimitSnapshot(remainingPercent: $0, resetsAtSeconds: Int64(now.addingTimeInterval((resetHours[fixtureIndex] ?? 2) * 3_600).timeIntervalSince1970)) },
                weekly: weeklyRemaining.map { WidgetLimitSnapshot(remainingPercent: $0, resetsAtSeconds: Int64(now.addingTimeInterval((resetHours[fixtureIndex] ?? 24) * 3_600).timeIntervalSince1970)) }
            )
        }
        let snapshot = WidgetSnapshot(generatedAtMilliseconds: Int64(now.addingTimeInterval(-freshnessAge).timeIntervalSince1970 * 1_000), accounts: accounts)
        return CodexWidgetEntry(date: now, snapshot: snapshot, loadState: .loaded)
    }
    static let healthy = entry(count: 7)
    static let warning = entry(remaining: 19)
    static let critical = entry(remaining: 9)
    static let unavailable = entry(remaining: nil)
    static let empty = CodexWidgetEntry(date: now, snapshot: nil, loadState: .missing)
    static let stale = entry(freshnessAge: 86_400, count: 7)

    static func healthy(family: WidgetFamily) -> CodexWidgetEntry {
        CodexWidgetEntry(
            date: now,
            snapshot: entry(count: accountCount(for: family)).snapshot,
            loadState: .loaded,
            previewHealthSummary: family == .systemLarge
                ? WidgetHealthSummary(healthy: 3, low: 1, stale: 1)
                : nil
        )
    }

    @ViewBuilder
    static func view(
        family: WidgetFamily,
        colorScheme: ColorScheme
    ) -> some View {
        CodexAuthWidgetView(entry: healthy(family: family), previewFamily: family)
            .environment(\.colorScheme, colorScheme)
    }

    private static func accountCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 3
        case .systemLarge: 6
        default: 1
        }
    }
}

#Preview("Small · Healthy", as: .systemSmall) {
    CodexAccountsWidget()
} timeline: {
    WidgetPreviewHarness.healthy
}

#Preview("Medium · Warning", as: .systemMedium) {
    CodexAccountsWidget()
} timeline: {
    WidgetPreviewHarness.warning
}

#Preview("Large · Stale", as: .systemLarge) {
    CodexAccountsWidget()
} timeline: {
    WidgetPreviewHarness.stale
}

#Preview("Widget View · Dark") {
    CodexAuthWidgetView(entry: WidgetPreviewHarness.warning).preferredColorScheme(.dark)
}

#Preview("Widget View · Critical") {
    CodexAuthWidgetView(entry: WidgetPreviewHarness.critical)
}
