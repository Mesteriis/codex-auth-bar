import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: CodexWidgetEntry

    var body: some View {
        let presentation = WidgetPresentation(entry.snapshot, family: .systemSmall, now: entry.date)
        if let account = presentation.accounts.first {
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader(freshness: presentation.freshness)
                Text(safeName(account.account.displayName))
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                if let plan = account.account.plan {
                    Text(plan.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack { Spacer(); DualLimitRing(fiveHourRemaining: account.fiveHourRemainingPercent, weeklyRemaining: account.weeklyRemainingPercent, diameter: 92); Spacer() }
                ResetFooter(reset: account.nearestReset, now: entry.date, freshness: presentation.freshness)
            }
            .accessibilityElement(children: .contain)
        } else {
            WidgetEmptyState()
        }
    }
}

func safeName(_ name: String) -> String { String(name.prefix(30)) }

struct WidgetHeader: View {
    let freshness: WidgetFreshness?

    var body: some View {
        HStack(spacing: 5) {
            Label { Text(String(localized: "Codex Accounts")) } icon: { Image(systemName: "chart.pie") }
                .font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 2)
            if let freshness, freshness != .fresh {
                Label { Text(String(localized: freshness == .stale ? "Stale" : "Data out of date")) } icon: { Image(systemName: freshness == .stale ? "exclamationmark.triangle.fill" : "clock") }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(freshness == .stale ? .red : .orange)
                    .accessibilityLabel(String(localized: freshness == .stale ? "Stale data" : "Data out of date"))
            }
        }
    }
}

struct ResetFooter: View {
    let reset: Date?
    let now: Date
    let freshness: WidgetFreshness?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
            if let reset {
                let formatter = RelativeDateTimeFormatter()
                let relative = formatter.localizedString(for: reset, relativeTo: now)
                Text(String(format: String(localized: "Resets %@"), relative))
            } else {
                Text("Unavailable")
            }
            Spacer()
            if freshness == .aging { Image(systemName: "clock.badge.exclamationmark") }
        }
        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
}
