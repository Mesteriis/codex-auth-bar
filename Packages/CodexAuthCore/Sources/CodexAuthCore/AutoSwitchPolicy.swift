import Foundation

public struct AutoSwitchThresholds: Equatable, Sendable {
    public var fiveHour: Double
    public var weekly: Double
    public init(fiveHour: Double = 10, weekly: Double = 5) {
        self.fiveHour = fiveHour
        self.weekly = weekly
    }
}

public struct AutoSwitchDecision: Equatable, Sendable {
    public var source: AccountKey
    public var target: AccountKey
}

public struct AutoSwitchPolicy: Sendable {
    public init() {}

    public func decision(registry: RegistryV4, thresholds: AutoSwitchThresholds, now: Date = .now) -> AutoSwitchDecision? {
        guard let activeKey = registry.activeAccountKey,
              let active = registry.accounts.first(where: { $0.accountKey == activeKey })
        else { return nil }
        let remaining5h = active.lastUsage?.primary?.remainingPercent(at: now)
        let remainingWeekly = active.lastUsage?.secondary?.remainingPercent(at: now)
        let fiveHourThreshold = active.resolvedPlan == .free ? max(35, thresholds.fiveHour) : thresholds.fiveHour
        let shouldSwitch = (remaining5h.map { $0 < fiveHourThreshold } ?? false)
            || (remainingWeekly.map { $0 < thresholds.weekly } ?? false)
        guard shouldSwitch else { return nil }
        let activeScore = score(active, now: now)
        guard let best = registry.accounts
            .filter({ $0.accountKey != activeKey })
            .max(by: { score($0, now: now) < score($1, now: now) }),
              score(best, now: now) > activeScore
        else { return nil }
        return AutoSwitchDecision(source: activeKey, target: best.accountKey)
    }

    public func rankedCandidates(registry: RegistryV4, now: Date = .now) -> [AccountRecord] {
        registry.accounts
            .filter { $0.accountKey != registry.activeAccountKey }
            .sorted { score($0, now: now) > score($1, now: now) }
    }

    private func score(_ account: AccountRecord, now: Date) -> Score {
        let windows = [account.lastUsage?.primary, account.lastUsage?.secondary].compactMap { $0?.remainingPercent(at: now) }
        return Score(value: windows.min() ?? 100, lastUsageAt: account.lastUsageAt ?? -1, createdAt: account.createdAt)
    }
}

private struct Score: Comparable {
    var value: Double
    var lastUsageAt: Int64
    var createdAt: Int64
    static func < (lhs: Score, rhs: Score) -> Bool {
        if lhs.value != rhs.value { return lhs.value < rhs.value }
        if lhs.lastUsageAt != rhs.lastUsageAt { return lhs.lastUsageAt < rhs.lastUsageAt }
        return lhs.createdAt < rhs.createdAt
    }
}
