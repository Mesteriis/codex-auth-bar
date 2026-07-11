import SwiftUI
import WidgetKit

struct CodexAuthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexWidgetEntry
    private let previewFamily: WidgetFamily?

    init(entry: CodexWidgetEntry, previewFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = previewFamily
    }

    var body: some View {
        Group {
            switch entry.loadState {
            case .loaded:
                switch previewFamily ?? family {
                case .systemSmall: SmallWidgetView(entry: entry)
                case .systemMedium: MediumWidgetView(entry: entry)
                case .systemLarge: LargeWidgetView(entry: entry)
                default: SmallWidgetView(entry: entry)
                }
            case .missing:
                WidgetEmptyState()
            case .invalid:
                WidgetEmptyState(isInvalid: true)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "codexauthbar://accounts"))
    }
}

struct WidgetEmptyState: View {
    var isInvalid = false

    var body: some View {
        ContentUnavailableView(
            isInvalid ? "Unavailable" : "No managed accounts",
            systemImage: isInvalid ? "exclamationmark.triangle" : "person.crop.circle.badge.questionmark",
            description: Text("Open Codex Auth Bar to set up the widget")
        )
        .accessibilityElement(children: .combine)
    }
}
