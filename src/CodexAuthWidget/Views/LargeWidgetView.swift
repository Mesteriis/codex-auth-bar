import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: CodexWidgetEntry

    var body: some View {
        let presentation = WidgetPresentation(entry.snapshot, family: .systemLarge, now: entry.date)
        VStack(alignment: .leading, spacing: 7) {
            HStack { WidgetHeader(freshness: presentation.freshness); Spacer(); Text("\(presentation.accounts.count) accounts").font(.caption).foregroundStyle(.secondary) }
            if presentation.accounts.isEmpty { WidgetEmptyState() }
            else {
                ForEach(presentation.accounts) { account in
                    LedgerRow(account: account, now: entry.date, freshness: presentation.freshness)
                }
                if presentation.hiddenCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                        Text(String(format: String(localized: "+ %d more in Codex Auth Bar"), presentation.hiddenCount))
                    }
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("+ \(presentation.hiddenCount) more in Codex Auth Bar")
                }
            }
        }
    }
}

private struct LedgerRow: View {
    let account: WidgetAccountPresentation
    let now: Date
    let freshness: WidgetFreshness?

    var body: some View {
        HStack(spacing: 10) {
            Text(safeName(account.account.displayName)).font(.subheadline.weight(.medium)).lineLimit(1).frame(width: 130, alignment: .leading)
            LimitRing(title: "5h", remaining: account.fiveHourRemainingPercent, diameter: 40, lineWidth: 5)
            LimitRing(title: "Weekly", remaining: account.weeklyRemainingPercent, diameter: 40, lineWidth: 5)
            ResetFooter(reset: account.nearestReset, now: now, freshness: freshness).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(safeName(account.account.displayName)))
        .accessibilityValue(Text(LimitAccessibility.value(title: "5h", remaining: account.fiveHourRemainingPercent, reset: account.nearestReset, now: now, freshness: freshness)))
    }
}
