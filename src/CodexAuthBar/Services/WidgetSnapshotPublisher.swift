import CodexAuthCore
import Foundation
import WidgetKit

enum WidgetPublishReason: Sendable {
    case startup, manualRefresh, structural, automatic

    var forcesReload: Bool { self != .automatic }
}

protocol WidgetTimelineReloading: Sendable {
    func reload() async throws
}

struct SystemWidgetTimelineReloader: WidgetTimelineReloading {
    func reload() async throws {
        WidgetCenter.shared.reloadTimelines(ofKind: CodexWidgetContract.kind)
    }
}

protocol WidgetSnapshotWriting: Sendable {
    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws
}

extension WidgetSnapshotStore: WidgetSnapshotWriting {
    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws { try write(snapshot) }
}

struct ReplicatingWidgetSnapshotWriter: WidgetSnapshotWriting {
    let primary: any WidgetSnapshotWriting
    let mirrors: [any WidgetSnapshotWriting]

    func writeSnapshot(_ snapshot: WidgetSnapshot) async throws {
        try await primary.writeSnapshot(snapshot)
        for mirror in mirrors {
            try? await mirror.writeSnapshot(snapshot)
        }
    }
}

actor WidgetSnapshotPublisher {
    private struct PendingReload {
        let forcesReload: Bool
        let enqueuedAt: Date
    }

    static let automaticReloadInterval: TimeInterval = 15 * 60

    private let store: any WidgetSnapshotWriting
    private let reloader: any WidgetTimelineReloading
    private let fallbackName: @Sendable (Int) -> String
    private var lastReload: Date?
    private var lastAccounts: [WidgetAccountSnapshot]?
    private var pendingReload: PendingReload?
    private var reloadInProgress = false

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
        if contentChanged || reason.forcesReload {
            try await store.writeSnapshot(snapshot)
            lastAccounts = snapshot.accounts
            pendingReload = PendingReload(
                forcesReload: reason.forcesReload || pendingReload?.forcesReload == true,
                enqueuedAt: now
            )
        }

        guard !reloadInProgress else { return }
        reloadInProgress = true
        defer { reloadInProgress = false }
        try await drainPendingReloads()
    }

    private func drainPendingReloads() async throws {
        while let pending = pendingReload {
            pendingReload = nil
            let elapsed = lastReload.map { pending.enqueuedAt.timeIntervalSince($0) } ?? .infinity
            guard pending.forcesReload || elapsed >= Self.automaticReloadInterval else {
                pendingReload = pending
                return
            }

            do {
                try await reloader.reload()
                lastReload = pending.enqueuedAt
            } catch {
                if let newerPending = pendingReload {
                    pendingReload = PendingReload(
                        forcesReload: pending.forcesReload || newerPending.forcesReload,
                        enqueuedAt: min(pending.enqueuedAt, newerPending.enqueuedAt)
                    )
                } else {
                    pendingReload = pending
                }
                throw error
            }
        }
    }
}
