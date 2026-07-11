import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: CodexWidgetEntry

    var body: some View {
        let presentation = WidgetPresentation(entry.snapshot, family: .systemMedium, now: entry.date)
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(freshness: presentation.freshness)
            if presentation.accounts.isEmpty { WidgetEmptyState() }
            else {
                ForEach(presentation.accounts) { account in
                    CompactLedgerRow(account: account, now: entry.date, freshness: presentation.freshness)
                }
            }
        }
    }
}

struct CompactLedgerRow: View {
    let account: WidgetAccountPresentation
    let now: Date
    let freshness: WidgetFreshness?

    var body: some View {
        HStack(spacing: 8) {
            DualLimitRing(fiveHourRemaining: account.fiveHourRemainingPercent, weeklyRemaining: account.weeklyRemainingPercent, diameter: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(safeName(account.account.displayName)).font(.subheadline.weight(.medium)).lineLimit(1)
                ResetFooter(reset: account.nearestReset, now: now, freshness: freshness)
            }
            Spacer(minLength: 0)
            LimitLegend(fiveHour: account.fiveHourRemainingPercent, weekly: account.weeklyRemainingPercent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(safeName(account.account.displayName)))
        .accessibilityValue(Text(LimitAccessibility.value(title: "5h", remaining: account.fiveHourRemainingPercent, reset: account.nearestReset, now: now, freshness: freshness)))
    }
}

struct LimitLegend: View {
    let fiveHour: Double?
    let weekly: Double?
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("5h \(fiveHour.map { "\(Int($0))%" } ?? "—")")
            Text("Weekly \(weekly.map { "\(Int($0))%" } ?? "—")")
        }
        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }
}
