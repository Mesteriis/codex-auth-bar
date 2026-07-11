import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: CodexWidgetEntry

    var body: some View {
        let presentation = WidgetPresentation(entry.snapshot, family: .systemSmall, now: entry.date)
        if let account = presentation.accounts.first {
            VStack(alignment: .leading, spacing: 2) {
                WidgetHeader(freshness: presentation.freshness, generatedAt: entry.snapshot.map { Date(timeIntervalSince1970: TimeInterval($0.generatedAtMilliseconds) / 1_000) }, now: entry.date)
                HStack(spacing: 4) {
                    Text(safeName(account.account.displayName))
                        .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    if let plan = account.account.plan {
                        Text(plan.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack {
                    Spacer(minLength: 0)
                    DualLimitRing(
                        fiveHourRemaining: account.fiveHourRemainingPercent,
                        weeklyRemaining: account.weeklyRemainingPercent,
                        reset: account.nearestReset,
                        now: entry.date,
                        freshness: presentation.freshness,
                        diameter: 64
                    )
                    Spacer(minLength: 0)
                }
                SmallLimitLegend(fiveHour: account.fiveHourRemainingPercent, weekly: account.weeklyRemainingPercent)
                ResetFooter(reset: account.nearestReset, now: entry.date, freshness: presentation.freshness, includesLabel: true)
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
    let generatedAt: Date?
    let now: Date

    var body: some View {
        HStack(spacing: 5) {
            Text(String(localized: "Codex Auth Bar"))
                .font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 2)
            if let generatedAt {
                Text(WidgetStrings.compactRecency(since: generatedAt, now: now))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(freshness == .stale ? .red : freshness == .aging ? .orange : .secondary)
                    .accessibilityLabel(String(format: String(localized: "Updated %@"), WidgetStrings.relativeTime(since: generatedAt, now: now)))
            }
        }
    }
}

struct SmallLimitLegend: View {
    let fiveHour: Double?
    let weekly: Double?

    var body: some View {
        HStack(spacing: 5) {
            LimitLegendItem(color: LimitSeverity(remaining: fiveHour).color(for: .fiveHour), label: String(localized: "5h limit"), accessibilityValue: WidgetStrings.percent(fiveHour))
            Text("|").foregroundStyle(.tertiary)
            LimitLegendItem(color: LimitSeverity(remaining: weekly).color(for: .weekly), label: String(localized: "W"), accessibilityValue: WidgetStrings.percent(weekly), accessibilityLabel: String(localized: "Weekly"))
        }
        .font(.caption2.monospacedDigit())
        .frame(maxWidth: .infinity)
    }
}

private struct LimitLegendItem: View {
    let color: Color
    let label: String
    let accessibilityValue: String
    var accessibilityLabel: String?

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityValue(accessibilityValue)
    }
}

struct ResetFooter: View {
    let reset: Date?
    let now: Date
    let freshness: WidgetFreshness?
    var includesLabel = false

    var body: some View {
        HStack(spacing: 4) {
            if includesLabel { Image(systemName: "arrow.clockwise") }
            if let reset {
                let compact = WidgetStrings.compactReset(until: reset, now: now)
                Text(includesLabel ? String(format: String(localized: "Reset %@"), compact) : compact)
            } else {
                Text("Unavailable")
            }
            if freshness == .aging { Image(systemName: "clock.badge.exclamationmark") }
        }
        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Reset"))
        .accessibilityValue(reset.map { WidgetStrings.relativeTime(until: $0, now: now) } ?? String(localized: "Unavailable"))
    }
}
