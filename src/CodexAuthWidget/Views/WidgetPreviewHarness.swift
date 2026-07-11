import CodexAuthCore
import SwiftUI
import WidgetKit

enum WidgetPreviewHarness {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static func entry(remaining: Double? = 72, freshnessAge: TimeInterval = 0, count: Int = 1) -> CodexWidgetEntry {
        let accounts = (0..<count).map { index in
            WidgetAccountSnapshot(
                id: "preview-\(index)",
                displayName: "Precision Ledger Account \(index + 1)",
                plan: .plus,
                isActive: index == 0,
                fiveHour: remaining.map { WidgetLimitSnapshot(remainingPercent: $0, resetsAtSeconds: Int64(now.addingTimeInterval(7_200).timeIntervalSince1970)) },
                weekly: remaining.map { WidgetLimitSnapshot(remainingPercent: $0, resetsAtSeconds: Int64(now.addingTimeInterval(86_400).timeIntervalSince1970)) }
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
        entry(count: accountCount(for: family))
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
