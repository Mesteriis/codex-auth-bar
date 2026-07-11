import SwiftUI

enum LimitSeverity: Equatable {
    case normal
    case warning
    case critical
    case unavailable

    init(remaining: Double?) {
        guard let remaining else { self = .unavailable; return }
        if remaining < 10 { self = .critical }
        else if remaining < 20 { self = .warning }
        else { self = .normal }
    }

    var color: Color {
        switch self {
        case .normal: .indigo
        case .warning: .orange
        case .critical: .red
        case .unavailable: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .normal: "checkmark"
        case .warning: "exclamationmark"
        case .critical: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark"
        }
    }
}

enum LimitAccessibility {
    static func accountValue(
        fiveHourRemaining: Double?,
        weeklyRemaining: Double?,
        reset: Date?,
        now: Date,
        freshness: WidgetFreshness?,
        locale: Locale = .current
    ) -> String {
        let fiveHour = value(title: String(localized: "5h", locale: locale), remaining: fiveHourRemaining, locale: locale)
        let weekly = value(title: String(localized: "Weekly", locale: locale), remaining: weeklyRemaining, locale: locale)
        var result = String(
            format: String(localized: "%@, %@", locale: locale),
            locale: locale,
            fiveHour,
            weekly
        )
        if let reset {
            let relative = RelativeDateTimeFormatter()
            relative.locale = locale
            result += ", " + String(
                format: String(localized: "resets %@", locale: locale),
                locale: locale,
                relative.localizedString(for: reset, relativeTo: now)
            )
        }
        if freshness == .aging || freshness == .stale {
            result += ", " + String(localized: "data out of date", locale: locale)
        }
        return result
    }

    static func value(
        title: String,
        remaining: Double?,
        locale: Locale = .current
    ) -> String {
        guard let remaining else {
            return String(
                format: String(localized: "%@ limit unavailable", locale: locale),
                locale: locale,
                title
            )
        }
        let format = String(localized: "%@ limit, %d percent remaining", locale: locale)
        return String(format: format, locale: locale, title, Int(remaining))
    }
}

enum WidgetStrings {
    static func percent(_ remaining: Double?) -> String {
        guard let remaining else { return String(localized: "Unavailable") }
        return String(format: String(localized: "%d%%"), Int(remaining))
    }

    static func pairLegend(fiveHour: Double?, weekly: Double?) -> String {
        String(
            format: String(localized: "%@ · %@"),
            String(localized: "5h"),
            String(localized: "Weekly")
        )
    }
}

struct LimitRing: View {
    let title: LocalizedStringKey
    let remaining: Double?
    let diameter: CGFloat
    let lineWidth: CGFloat

    private var severity: LimitSeverity { LimitSeverity(remaining: remaining) }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            if let remaining {
                Circle()
                    .trim(from: 0, to: min(max(remaining / 100, 0), 1))
                    .stroke(severity.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            VStack(spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(WidgetStrings.percent(remaining))
                    .font(.caption.monospacedDigit().weight(.semibold))
                if severity != .normal {
                    Image(systemName: severity.symbol).font(.system(size: 8, weight: .bold))
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

struct DualLimitRing: View {
    let fiveHourRemaining: Double?
    let weeklyRemaining: Double?
    let diameter: CGFloat

    var body: some View {
        ZStack {
            RingStroke(remaining: weeklyRemaining, inset: 0, lineWidth: 7)
            RingStroke(remaining: fiveHourRemaining, inset: 11, lineWidth: 7)
            VStack(spacing: 3) {
                Text(WidgetStrings.percent(fiveHourRemaining))
                    .font(.title3.monospacedDigit().weight(.bold))
                Text(WidgetStrings.pairLegend(fiveHour: fiveHourRemaining, weekly: weeklyRemaining)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Limits")))
        .accessibilityValue(Text(LimitAccessibility.accountValue(fiveHourRemaining: fiveHourRemaining, weeklyRemaining: weeklyRemaining, reset: nil, now: .now, freshness: nil)))
    }
}

private struct RingStroke: View {
    let remaining: Double?
    let inset: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Circle()
            .inset(by: inset)
            .stroke(.quaternary, lineWidth: lineWidth)
            .overlay {
                if let remaining {
                    Circle()
                        .inset(by: inset)
                        .trim(from: 0, to: min(max(remaining / 100, 0), 1))
                        .stroke(LimitSeverity(remaining: remaining).color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else {
                    Circle().inset(by: inset).stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
    }
}
