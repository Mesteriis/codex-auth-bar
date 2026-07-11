import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: CodexWidgetEntry

    var body: some View {
        let presentation = WidgetPresentation(entry.snapshot, family: .systemLarge, now: entry.date)
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(freshness: presentation.freshness, generatedAt: entry.snapshot.map { Date(timeIntervalSince1970: TimeInterval($0.generatedAtMilliseconds) / 1_000) }, now: entry.date)
            HealthSummary(accounts: presentation.accounts, previewSummary: entry.previewHealthSummary)
            if presentation.accounts.isEmpty { WidgetEmptyState() }
            else {
                LargeColumnHeaders()
                ForEach(Array(presentation.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Divider() }
                    LargeLedgerRow(account: account, now: entry.date, freshness: presentation.freshness)
                }
            }
        }
    }
}

private struct HealthSummary: View {
    let accounts: [WidgetAccountPresentation]
    let previewSummary: WidgetHealthSummary?

    var body: some View {
        let computedLow = accounts.filter { account in
            [account.fiveHourRemainingPercent, account.weeklyRemainingPercent].contains { LimitSeverity(remaining: $0) == .warning || LimitSeverity(remaining: $0) == .critical }
        }.count
        let unavailable = accounts.filter { $0.fiveHourRemainingPercent == nil || $0.weeklyRemainingPercent == nil }.count
        let summary = previewSummary ?? WidgetHealthSummary(
            healthy: max(0, accounts.count - computedLow - unavailable),
            low: computedLow,
            stale: 0
        )
        return HStack(spacing: 4) {
            Text(String(format: String(localized: "%d healthy"), summary.healthy)).foregroundStyle(.blue)
            Text("·").foregroundStyle(.secondary)
            Text(String(format: String(localized: "%d low"), summary.low)).foregroundStyle(.orange)
            Text("·").foregroundStyle(.secondary)
            Text(String(format: String(localized: "%d stale"), summary.stale)).foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityLabel(String(format: String(localized: "%d healthy, %d low, %d stale"), summary.healthy, summary.low, summary.stale))
    }
}

private struct LargeColumnHeaders: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("ACCOUNT").frame(width: 100, alignment: .leading)
            Text("PLAN").frame(width: 55, alignment: .leading)
            Divider().frame(height: 15).padding(.trailing, 4)
            Text("5h").frame(width: 44)
            Text("W").frame(width: 44)
            Text("RESETS").frame(width: 62, alignment: .trailing)
        }
        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Account, plan, 5 hour limit, Weekly limit, resets"))
    }
}

private struct LargeLedgerRow: View {
    let account: WidgetAccountPresentation
    let now: Date
    let freshness: WidgetFreshness?

    var body: some View {
        HStack(spacing: 0) {
            AccountCell(account: account, showsPlan: false).frame(width: 100, alignment: .leading)
            Text(account.account.plan?.label ?? String(localized: "Unavailable"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(width: 55, alignment: .leading)
            Divider().frame(height: 38).padding(.trailing, 4)
            LedgerLimitCell(title: "5h", accessibilityTitle: String(localized: "5h"), kind: .fiveHour, remaining: account.fiveHourRemainingPercent).frame(width: 44)
            LedgerLimitCell(title: "W", accessibilityTitle: String(localized: "Weekly"), kind: .weekly, remaining: account.weeklyRemainingPercent).frame(width: 44)
            ResetFooter(reset: account.nearestReset, now: now, freshness: freshness).frame(width: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(safeName(account.account.displayName)))
        .accessibilityValue(Text(AccountAccessibility.value(account: account, now: now, freshness: freshness)))
    }
}

enum AccountAccessibility {
    static func value(account: WidgetAccountPresentation, now: Date, freshness: WidgetFreshness?) -> String {
        let plan = account.account.plan?.label ?? String(localized: "Unavailable")
        let status = statusText(for: account)
        let limits = LimitAccessibility.accountValue(
            fiveHourRemaining: account.fiveHourRemainingPercent,
            weeklyRemaining: account.weeklyRemainingPercent,
            reset: account.nearestReset,
            now: now,
            freshness: freshness
        )
        return String(format: String(localized: "%@, %@, %@"), plan, status, limits)
    }

    private static func statusText(for account: WidgetAccountPresentation) -> String {
        if account.fiveHourRemainingPercent == nil || account.weeklyRemainingPercent == nil { return String(localized: "Unavailable") }
        if [account.fiveHourRemainingPercent, account.weeklyRemainingPercent].contains(where: { LimitSeverity(remaining: $0) != .normal }) { return String(localized: "Low") }
        return String(localized: "Healthy")
    }
}

struct AccountCell: View {
    let account: WidgetAccountPresentation
    var showsPlan = true

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(account.statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(safeName(account.account.displayName)).font(.subheadline.weight(.medium)).lineLimit(1)
                if showsPlan, account.account.plan != nil { Text(account.account.plan!.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}

private extension WidgetAccountPresentation {
    var statusColor: Color {
        if fiveHourRemainingPercent == nil || weeklyRemainingPercent == nil { return .secondary }
        if [fiveHourRemainingPercent, weeklyRemainingPercent].contains(where: { LimitSeverity(remaining: $0) == .critical }) { return .red }
        if [fiveHourRemainingPercent, weeklyRemainingPercent].contains(where: { LimitSeverity(remaining: $0) == .warning }) { return .orange }
        return .blue
    }
}
