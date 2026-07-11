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
    static func value(
        title: String,
        remaining: Double?,
        reset: Date?,
        now: Date,
        freshness: WidgetFreshness?,
        locale: Locale = .current
    ) -> String {
        guard let remaining else {
            return String(localized: "\(title) limit unavailable", locale: locale)
        }
        let format = String(localized: "%@ limit, %d percent remaining", locale: locale)
        var result = String(format: format, locale: locale, title, Int(remaining))
        if let reset {
            let relative = RelativeDateTimeFormatter()
            relative.locale = locale
            let resetFormat = String(localized: "resets %@", locale: locale)
            result += ", " + String(
                format: resetFormat,
                locale: locale,
                relative.localizedString(for: reset, relativeTo: now)
            )
        }
        if freshness == .aging || freshness == .stale {
            result += ", " + String(localized: "data out of date", locale: locale)
        }
        return result
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
                Text(remaining.map { "\(Int($0))%" } ?? "—")
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
                Text(fiveHourRemaining.map { "\(Int($0))%" } ?? "—")
                    .font(.title3.monospacedDigit().weight(.bold))
                Text("5h · Weekly").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Limits"))
        .accessibilityValue(Text("5h \(fiveHourRemaining.map { "\(Int($0))%" } ?? "unavailable"), Weekly \(weeklyRemaining.map { "\(Int($0))%" } ?? "unavailable")"))
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
