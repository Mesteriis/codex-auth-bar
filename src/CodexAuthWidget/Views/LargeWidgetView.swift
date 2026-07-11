import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: CodexWidgetEntry

    var body: some View {
        let presentation = WidgetPresentation(entry.snapshot, family: .systemLarge, now: entry.date)
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(freshness: presentation.freshness, generatedAt: entry.snapshot.map { Date(timeIntervalSince1970: TimeInterval($0.generatedAtMilliseconds) / 1_000) }, now: entry.date)
            HealthSummary(accounts: presentation.accounts)
            if presentation.accounts.isEmpty { WidgetEmptyState() }
            else {
                LargeColumnHeaders()
                ForEach(Array(presentation.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Divider() }
                    LargeLedgerRow(account: account, now: entry.date, freshness: presentation.freshness)
                }
            }
        }
        .padding(.horizontal, WidgetLayoutMetrics.ledgerHorizontalInset)
    }
}

private struct HealthSummary: View {
    let accounts: [WidgetAccountPresentation]

    var body: some View {
        let low = accounts.filter { account in
            [account.fiveHourRemainingPercent, account.weeklyRemainingPercent].contains { LimitSeverity(remaining: $0) == .warning || LimitSeverity(remaining: $0) == .critical }
        }.count
        let unavailable = accounts.filter { $0.fiveHourRemainingPercent == nil || $0.weeklyRemainingPercent == nil }.count
        let healthy = max(0, accounts.count - low - unavailable)
        return HStack(spacing: 4) {
            Text(String(format: String(localized: "%d healthy"), healthy)).foregroundStyle(.indigo)
            Text("·").foregroundStyle(.secondary)
            Text(String(format: String(localized: "%d low"), low)).foregroundStyle(.orange)
            Text("·").foregroundStyle(.secondary)
            Text(String(format: String(localized: "%d unavailable"), unavailable)).foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityLabel(String(format: String(localized: "%d healthy, %d low, %d unavailable"), healthy, low, unavailable))
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
            LimitRing(title: "5h", accessibilityTitle: String(localized: "5h"), remaining: account.fiveHourRemainingPercent, diameter: 36, lineWidth: 3).frame(width: 44)
            LimitRing(title: "W", accessibilityTitle: String(localized: "Weekly"), remaining: account.weeklyRemainingPercent, diameter: 36, lineWidth: 3).frame(width: 44)
            ResetFooter(reset: account.nearestReset, now: now, freshness: freshness).frame(width: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(safeName(account.account.displayName)))
        .accessibilityValue(Text(LimitAccessibility.accountValue(fiveHourRemaining: account.fiveHourRemainingPercent, weeklyRemaining: account.weeklyRemainingPercent, reset: account.nearestReset, now: now, freshness: freshness)))
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
        return .indigo
    }
}
