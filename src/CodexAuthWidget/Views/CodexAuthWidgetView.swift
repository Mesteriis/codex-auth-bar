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
        ZStack {
            WidgetMaterialSurface()
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
            .padding(WidgetLayoutMetrics.surfaceInset)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(URL(string: "codexauthbar://accounts"))
    }
}

private struct WidgetMaterialSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
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
