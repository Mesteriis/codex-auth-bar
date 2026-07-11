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
        .padding(.horizontal, WidgetLayoutMetrics.ledgerHorizontalInset)
    }
}

struct CompactLedgerRow: View {
    let account: WidgetAccountPresentation
    let now: Date
    let freshness: WidgetFreshness?

    var body: some View {
        HStack(spacing: 8) {
            DualLimitRing(
                fiveHourRemaining: account.fiveHourRemainingPercent,
                weeklyRemaining: account.weeklyRemainingPercent,
                reset: account.nearestReset,
                now: now,
                freshness: freshness,
                diameter: 38
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(safeName(account.account.displayName)).font(.subheadline.weight(.medium)).lineLimit(1)
                ResetFooter(reset: account.nearestReset, now: now, freshness: freshness)
            }
            Spacer(minLength: 0)
            LimitLegend(fiveHour: account.fiveHourRemainingPercent, weekly: account.weeklyRemainingPercent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(safeName(account.account.displayName)))
        .accessibilityValue(Text(LimitAccessibility.accountValue(fiveHourRemaining: account.fiveHourRemainingPercent, weeklyRemaining: account.weeklyRemainingPercent, reset: account.nearestReset, now: now, freshness: freshness)))
    }
}

struct LimitLegend: View {
    let fiveHour: Double?
    let weekly: Double?
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(String(format: String(localized: "%@ %@"), String(localized: "5h"), WidgetStrings.percent(fiveHour)))
            Text(String(format: String(localized: "%@ %@"), String(localized: "Weekly"), WidgetStrings.percent(weekly)))
        }
        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }
}
