import SwiftUI
import WidgetKit
import CodexAuthCore

@main
struct CodexAuthWidgetBundle: WidgetBundle {
    var body: some Widget { CodexAccountsWidget() }
}

struct CodexAccountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CodexWidgetContract.kind, provider: PlaceholderProvider()) { entry in
            Text("Codex Auth Bar")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Codex Accounts")
        .description("Shows remaining Codex account limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { .init(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(.init(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now)], policy: .never))
    }
}
