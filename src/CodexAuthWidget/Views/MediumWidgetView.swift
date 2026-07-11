import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: CodexWidgetEntry

    var body: some View {
        let presentation = WidgetPresentation(entry.snapshot, family: .systemMedium, now: entry.date)
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(freshness: presentation.freshness, generatedAt: entry.snapshot.map { Date(timeIntervalSince1970: TimeInterval($0.generatedAtMilliseconds) / 1_000) }, now: entry.date)
            if presentation.accounts.isEmpty { WidgetEmptyState() }
            else {
                MediumColumnHeaders()
                ForEach(Array(presentation.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Divider() }
                    MediumLedgerRow(account: account, now: entry.date, freshness: presentation.freshness)
                }
            }
        }
        .padding(.horizontal, WidgetLayoutMetrics.ledgerHorizontalInset)
    }
}

private struct MediumColumnHeaders: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("ACCOUNT").frame(maxWidth: .infinity, alignment: .leading)
            Text("5h").frame(width: 46)
            Text("W").frame(width: 46)
            Text("RESETS").frame(width: 66, alignment: .trailing)
        }
        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Account, 5 hour limit, Weekly limit, resets"))
    }
}

private struct MediumLedgerRow: View {
    let account: WidgetAccountPresentation
    let now: Date
    let freshness: WidgetFreshness?

    var body: some View {
        HStack(spacing: 0) {
            AccountCell(account: account)
                .frame(maxWidth: .infinity, alignment: .leading)
            LimitRing(title: "5h", accessibilityTitle: String(localized: "5h"), remaining: account.fiveHourRemainingPercent, diameter: 32, lineWidth: 3)
                .frame(width: 46)
            LimitRing(title: "W", accessibilityTitle: String(localized: "Weekly"), remaining: account.weeklyRemainingPercent, diameter: 32, lineWidth: 3)
                .frame(width: 46)
            ResetFooter(reset: account.nearestReset, now: now, freshness: freshness)
                .frame(width: 66, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(safeName(account.account.displayName)))
        .accessibilityValue(Text(LimitAccessibility.accountValue(fiveHourRemaining: account.fiveHourRemainingPercent, weeklyRemaining: account.weeklyRemainingPercent, reset: account.nearestReset, now: now, freshness: freshness)))
    }
}
