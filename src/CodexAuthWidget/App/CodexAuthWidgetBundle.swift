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
            CodexAuthWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex Accounts")
        .description(String(localized: "Shows remaining Codex account limits."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
