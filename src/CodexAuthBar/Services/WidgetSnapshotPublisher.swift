import CodexAuthCore
import Foundation
import WidgetKit

enum WidgetPublishReason: Sendable {
    case startup, manualRefresh, structural, automatic

    var forcesReload: Bool { self != .automatic }
}

protocol WidgetTimelineReloading: Sendable {
    func reload() async
}

struct SystemWidgetTimelineReloader: WidgetTimelineReloading {
    func reload() async {
        WidgetCenter.shared.reloadTimelines(ofKind: CodexWidgetContract.kind)
    }
}

protocol WidgetSnapshotWriting: Sendable {
    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws
}

extension WidgetSnapshotStore: WidgetSnapshotWriting {
    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws { try write(snapshot) }
}

actor WidgetSnapshotPublisher {
    static let automaticReloadInterval: TimeInterval = 15 * 60

    private let store: any WidgetSnapshotWriting
    private let reloader: any WidgetTimelineReloading
    private let fallbackName: @Sendable (Int) -> String
    private var lastReload: Date?
    private var lastAccounts: [WidgetAccountSnapshot]?

    init(
        store: any WidgetSnapshotWriting,
        reloader: any WidgetTimelineReloading = SystemWidgetTimelineReloader(),
        fallbackName: @escaping @Sendable (Int) -> String
    ) {
        self.store = store
        self.reloader = reloader
        self.fallbackName = fallbackName
    }

    func publish(registry: RegistryV4, reason: WidgetPublishReason, now: Date = .now) async throws {
        let snapshot = WidgetSnapshotProjector.project(registry, generatedAt: now, fallbackName: fallbackName)
        let contentChanged = snapshot.accounts != lastAccounts
        guard contentChanged || reason.forcesReload else { return }

        try await store.writeSnapshot(snapshot)
        lastAccounts = snapshot.accounts

        let elapsed = lastReload.map { now.timeIntervalSince($0) } ?? .infinity
        guard reason.forcesReload || elapsed >= Self.automaticReloadInterval else { return }
        await reloader.reload()
        lastReload = now
    }
}
