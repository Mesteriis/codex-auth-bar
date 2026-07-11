import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: CodexWidgetEntry

    var body: some View {
        let presentation = WidgetPresentation(entry.snapshot, family: .systemMedium, now: entry.date)
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(freshness: presentation.freshness, generatedAt: entry.snapshot.map { Date(timeIntervalSince1970: TimeInterval($0.generatedAtMilliseconds) / 1_000) }, now: entry.date)
            Divider()
            if presentation.accounts.isEmpty { WidgetEmptyState() }
            else {
                MediumColumnHeaders()
                ForEach(Array(presentation.accounts.enumerated()), id: \.element.id) { index, account in
                    MediumLedgerRow(account: account, now: entry.date, freshness: presentation.freshness)
                    if index < presentation.accounts.count - 1 { Divider() }
                }
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, WidgetLayoutMetrics.ledgerHorizontalInset)
    }
}

private struct MediumColumnHeaders: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("ACCOUNT").frame(maxWidth: .infinity, alignment: .leading)
            Text("5h").frame(width: 46)
            Text("W").frame(width: 46)
            Text("RESETS").frame(width: 72, alignment: .trailing)
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
            LedgerLimitCell(title: "5h", accessibilityTitle: String(localized: "5h"), kind: .fiveHour, remaining: account.fiveHourRemainingPercent)
                .frame(width: 46)
            LedgerLimitCell(title: "W", accessibilityTitle: String(localized: "Weekly"), kind: .weekly, remaining: account.weeklyRemainingPercent)
                .frame(width: 46)
            ResetFooter(reset: account.nearestReset, now: now, freshness: freshness)
                .frame(width: 72, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(safeName(account.account.displayName)))
        .accessibilityValue(Text(AccountAccessibility.value(account: account, now: now, freshness: freshness)))
    }
}

struct LedgerLimitCell: View {
    let title: String
    let accessibilityTitle: String
    let kind: LimitKind
    let remaining: Double?

    var body: some View {
        HStack(spacing: 2) {
            LimitRing(title: title, accessibilityTitle: accessibilityTitle, kind: kind, remaining: remaining, diameter: 20, lineWidth: 2)
            Text(WidgetStrings.percent(remaining))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(LimitSeverity(remaining: remaining).color(for: kind))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(LimitAccessibility.value(title: accessibilityTitle, remaining: remaining))
    }
}
