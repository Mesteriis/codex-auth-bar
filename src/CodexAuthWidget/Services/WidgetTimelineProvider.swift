import CodexAuthCore
import Foundation
import WidgetKit

struct CodexWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexWidgetEntry {
        .preview(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexWidgetEntry) -> Void) {
        completion(context.isPreview ? .preview(date: .now) : loadEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexWidgetEntry>) -> Void) {
        let now = Date()
        switch loadSnapshot(now: now) {
        case .loaded(let snapshot):
            let result = WidgetTimelineBuilder.build(snapshot: snapshot, now: now)
            completion(Timeline(entries: result.entries, policy: .after(result.reloadDate)))
        case .missing, .invalid:
            let entry = loadEntry(at: now)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(WidgetTimelineBuilder.normalRefresh))))
        }
    }

    private func loadEntry(at now: Date) -> CodexWidgetEntry {
        switch loadSnapshot(now: now) {
        case .loaded(let snapshot):
            return CodexWidgetEntry(date: now, snapshot: snapshot, loadState: .loaded)
        case .missing:
            return CodexWidgetEntry(date: now, snapshot: nil, loadState: .missing)
        case .invalid:
            return CodexWidgetEntry(date: now, snapshot: nil, loadState: .invalid)
        }
    }

    private func loadSnapshot(now: Date) -> SnapshotLoadResult {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CodexWidgetContract.appGroup
        ) else {
            return .missing
        }

        do {
            let snapshot = try WidgetSnapshotStore(containerURL: containerURL).load()
            let generatedAt = Date(
                timeIntervalSince1970: TimeInterval(snapshot.generatedAtMilliseconds) / 1_000
            )
            return generatedAt > now ? .invalid : .loaded(snapshot)
        } catch WidgetSnapshotStoreError.missing {
            return .missing
        } catch {
            return .invalid
        }
    }
}

private enum SnapshotLoadResult {
    case loaded(WidgetSnapshot)
    case missing
    case invalid
}
