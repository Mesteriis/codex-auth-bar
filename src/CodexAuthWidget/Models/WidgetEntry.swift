import CodexAuthCore
import Foundation
import WidgetKit

struct CodexWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let loadState: WidgetLoadState
    /// Preview-only presentation data; production timeline entries leave this nil.
    let previewHealthSummary: WidgetHealthSummary?

    init(
        date: Date,
        snapshot: WidgetSnapshot?,
        loadState: WidgetLoadState,
        previewHealthSummary: WidgetHealthSummary? = nil
    ) {
        self.date = date
        self.snapshot = snapshot
        self.loadState = loadState
        self.previewHealthSummary = previewHealthSummary
    }
}

struct WidgetHealthSummary {
    let healthy: Int
    let low: Int
    let stale: Int
}

enum WidgetLoadState: Equatable {
    case loaded
    case missing
    case invalid
}

enum WidgetFreshness: Equatable {
    case fresh
    case aging
    case stale

    static func resolve(generatedAt: Date, now: Date) -> Self {
        let age = now.timeIntervalSince(generatedAt)
        if age >= 24 * 60 * 60 { return .stale }
        if age >= 2 * 60 * 60 { return .aging }
        return .fresh
    }
}

struct WidgetTimelineResult {
    let entries: [CodexWidgetEntry]
    let reloadDate: Date
}

struct WidgetAccountPresentation: Identifiable {
    let account: WidgetAccountSnapshot
    let fiveHourRemainingPercent: Double?
    let weeklyRemainingPercent: Double?
    let nearestReset: Date?

    var id: String { account.id }
}

struct WidgetPresentation {
    let accounts: [WidgetAccountPresentation]
    let hiddenCount: Int
    let freshness: WidgetFreshness?
    let now: Date

    init(_ snapshot: WidgetSnapshot?, family: WidgetFamily, now: Date = .now) {
        let capacity: Int
        switch family {
        case .systemSmall: capacity = 1
        case .systemMedium: capacity = 3
        case .systemLarge: capacity = 6
        default: capacity = 1
        }

        let all = snapshot?.accounts ?? []
        accounts = all.prefix(capacity).map { account in
            let resetDates = [account.fiveHour?.resetsAtSeconds, account.weekly?.resetsAtSeconds]
                .compactMap { $0 }
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
                .filter { $0 > now }

            return WidgetAccountPresentation(
                account: account,
                fiveHourRemainingPercent: account.fiveHour?.effectiveRemainingPercent(at: now),
                weeklyRemainingPercent: account.weekly?.effectiveRemainingPercent(at: now),
                nearestReset: resetDates.min()
            )
        }
        hiddenCount = max(0, all.count - capacity)
        self.now = now
        freshness = snapshot.map {
            WidgetFreshness.resolve(
                generatedAt: Date(timeIntervalSince1970: TimeInterval($0.generatedAtMilliseconds) / 1_000),
                now: now
            )
        }
    }
}

enum WidgetTimelineBuilder {
    static let normalRefresh: TimeInterval = 30 * 60
    static let minimumSpacing: TimeInterval = 5 * 60

    static func build(snapshot: WidgetSnapshot?, now: Date) -> WidgetTimelineResult {
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        let resetDates = (snapshot?.accounts ?? []).flatMap { account in
            [account.fiveHour?.resetsAtSeconds, account.weekly?.resetsAtSeconds]
                .compactMap { $0 }
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
        .filter { $0 > now && $0 <= horizon }
        .sorted()

        var dates = [now]
        for reset in resetDates where reset.timeIntervalSince(dates.last!) >= minimumSpacing {
            dates.append(reset)
        }

        let loadState: WidgetLoadState = snapshot == nil ? .missing : .loaded
        return WidgetTimelineResult(
            entries: dates.map { CodexWidgetEntry(date: $0, snapshot: snapshot, loadState: loadState) },
            reloadDate: now.addingTimeInterval(normalRefresh)
        )
    }
}

extension CodexWidgetEntry {
    static func preview(date: Date) -> Self {
        Self(date: date, snapshot: nil, loadState: .missing)
    }
}
