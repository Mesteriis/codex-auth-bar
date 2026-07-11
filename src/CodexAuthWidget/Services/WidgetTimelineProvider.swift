import CodexAuthCore
import Darwin
import Foundation
import Security
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
        var stores: [WidgetSnapshotStore] = []
        if !RuntimeWidgetCodeSignature.hasTeamIdentifier {
            stores.append(
                WidgetSnapshotStore(
                    containerURL: CodexWidgetContract.localUnsignedContainerURL(userID: getuid())
                )
            )
        } else if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: CodexWidgetContract.appGroup
        ) {
            stores.append(WidgetSnapshotStore(containerURL: containerURL))
        }

        return WidgetSnapshotLoader(stores: stores).load(now: now)
    }
}

private enum RuntimeWidgetCodeSignature {
    static var hasTeamIdentifier: Bool {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess,
              let code
        else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let staticCode
        else { return false }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else { return false }

        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String != nil
    }
}

struct WidgetSnapshotLoader {
    let stores: [WidgetSnapshotStore]

    func load(now: Date) -> SnapshotLoadResult {
        var foundInvalidStore = false

        for store in stores {
            do {
                let snapshot = try store.load()
                let generatedAt = Date(
                    timeIntervalSince1970: TimeInterval(snapshot.generatedAtMilliseconds) / 1_000
                )
                if generatedAt > now {
                    foundInvalidStore = true
                    continue
                }
                return .loaded(snapshot)
            } catch WidgetSnapshotStoreError.missing {
                continue
            } catch {
                foundInvalidStore = true
            }
        }

        return foundInvalidStore ? .invalid : .missing
    }
}

enum SnapshotLoadResult {
    case loaded(WidgetSnapshot)
    case missing
    case invalid
}
