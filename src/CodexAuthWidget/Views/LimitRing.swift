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

    func color(for kind: LimitKind) -> Color {
        switch self {
        case .normal: kind.normalColor
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

enum LimitKind {
    case fiveHour
    case weekly

    var normalColor: Color {
        switch self {
        case .fiveHour: .blue
        case .weekly: .purple
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
        var result = String(format: format, locale: locale, title, Int(remaining))
        switch LimitSeverity(remaining: remaining) {
        case .warning:
            result += ", " + String(localized: "low remaining", locale: locale)
        case .critical:
            result += ", " + String(localized: "critical remaining", locale: locale)
        case .normal, .unavailable:
            break
        }
        return result
    }
}

enum WidgetStrings {
    static func percent(_ remaining: Double?) -> String {
        guard let remaining else { return String(localized: "—") }
        return String(format: String(localized: "%d%%"), Int(remaining))
    }

    static func pairLegend(fiveHour: Double?, weekly: Double?) -> String {
        String(
            format: String(localized: "%@ · %@"),
            String(localized: "5h"),
            String(localized: "W")
        )
    }

    static func relativeTime(until date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func relativeTime(since date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func compactRecency(since date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return String(localized: "now") }
        if seconds < 60 * 60 { return String(format: String(localized: "%dm"), Int(seconds / 60)) }
        return String(format: String(localized: "%dh"), Int(seconds / 3_600))
    }

    static func compactReset(until date: Date, now: Date = .now) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        if days > 0 {
            return String(format: String(localized: "%dd %dh"), days, hours)
        }
        if hours > 0 {
            return String(format: String(localized: "%dh %dm"), hours, minutes)
        }
        return String(format: String(localized: "%dm"), max(1, minutes))
    }
}

enum WidgetLayoutMetrics {
    /// The one shared content gutter for every widget family.
    static let surfaceInset: CGFloat = 12
}

struct LimitRing: View {
    let title: String
    let accessibilityTitle: String
    let kind: LimitKind
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
                    .stroke(severity.color(for: kind), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(LimitAccessibility.value(title: accessibilityTitle, remaining: remaining))
    }
}

struct DualLimitRing: View {
    let fiveHourRemaining: Double?
    let weeklyRemaining: Double?
    let reset: Date?
    let now: Date
    let freshness: WidgetFreshness?
    let diameter: CGFloat

    var body: some View {
        ZStack {
            RingStroke(remaining: weeklyRemaining, kind: .weekly, inset: 0, lineWidth: 7)
            RingStroke(remaining: fiveHourRemaining, kind: .fiveHour, inset: 11, lineWidth: 7)
            VStack(spacing: 2) {
                Text(String(localized: "5h")).font(.caption2).foregroundStyle(.secondary)
                Text(String(localized: "W")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Limits")))
        .accessibilityValue(Text(LimitAccessibility.accountValue(fiveHourRemaining: fiveHourRemaining, weeklyRemaining: weeklyRemaining, reset: reset, now: now, freshness: freshness)))
    }
}

private struct RingStroke: View {
    let remaining: Double?
    let kind: LimitKind
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
                        .stroke(LimitSeverity(remaining: remaining).color(for: kind), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else {
                    Circle().inset(by: inset).stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
    }
}
