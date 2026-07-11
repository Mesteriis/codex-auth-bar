import SwiftUI
import WidgetKit
import CodexAuthCore

@main
struct CodexAuthWidgetBundle: WidgetBundle {
    var body: some Widget { CodexAccountsWidget() }
}

struct CodexAccountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CodexWidgetContract.kind, provider: CodexWidgetProvider()) { entry in
            CodexAccountsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Codex Accounts")
        .description("Shows remaining Codex account limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct CodexAccountsWidgetView: View {
    let entry: CodexWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.loadState {
        case .missing:
            ContentUnavailableView("No widget data", systemImage: "clock")
        case .invalid:
            ContentUnavailableView("Widget data unavailable", systemImage: "exclamationmark.triangle")
        case .loaded:
            let presentation = WidgetPresentation(entry.snapshot, family: family, now: entry.date)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(presentation.accounts) { account in
                    HStack {
                        Text(account.account.displayName).lineLimit(1)
                        Spacer()
                        if let percent = account.fiveHourRemainingPercent {
                            Text(percent / 100, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                    }
                }
                if presentation.hiddenCount > 0 {
                    Text("+\(presentation.hiddenCount) more")
                }
                if presentation.freshness == .stale {
                    Text("Data is stale")
                }
            }
        }
    }
}
