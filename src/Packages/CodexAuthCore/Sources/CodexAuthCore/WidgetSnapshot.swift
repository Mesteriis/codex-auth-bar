import CryptoKit
import Foundation

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var generatedAtMilliseconds: Int64
    public var accounts: [WidgetAccountSnapshot]

    public init(
        generatedAtMilliseconds: Int64,
        accounts: [WidgetAccountSnapshot],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAtMilliseconds = generatedAtMilliseconds
        self.accounts = accounts
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMilliseconds = "generated_at_ms"
        case accounts
    }
}

public struct WidgetAccountSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var plan: PlanType?
    public var isActive: Bool
    public var fiveHour: WidgetLimitSnapshot?
    public var weekly: WidgetLimitSnapshot?

    public init(
        id: String,
        displayName: String,
        plan: PlanType?,
        isActive: Bool,
        fiveHour: WidgetLimitSnapshot?,
        weekly: WidgetLimitSnapshot?
    ) {
        self.id = id
        self.displayName = displayName
        self.plan = plan
        self.isActive = isActive
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case plan
        case isActive = "is_active"
        case fiveHour = "five_hour"
        case weekly
    }
}

public struct WidgetLimitSnapshot: Codable, Equatable, Sendable {
    public var remainingPercent: Double
    public var resetsAtSeconds: Int64?

    public init(remainingPercent: Double, resetsAtSeconds: Int64?) {
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetsAtSeconds = resetsAtSeconds
    }

    public func effectiveRemainingPercent(at date: Date) -> Double {
        guard let resetsAtSeconds,
              resetsAtSeconds <= Int64(date.timeIntervalSince1970)
        else { return remainingPercent }
        return 100
    }

    enum CodingKeys: String, CodingKey {
        case remainingPercent = "remaining_percent"
        case resetsAtSeconds = "resets_at"
    }
}

public enum WidgetSnapshotProjector {
    public static func project(
        _ registry: RegistryV4,
        generatedAt: Date = .now,
        fallbackName: (Int) -> String = { "Account \($0)" }
    ) -> WidgetSnapshot {
        let ordered = registry.accounts.sorted {
            let leftActive = $0.accountKey == registry.activeAccountKey
            let rightActive = $1.accountKey == registry.activeAccountKey
            if leftActive != rightActive { return leftActive }

            let left = attentionScore($0, at: generatedAt)
            let right = attentionScore($1, at: generatedAt)
            if left != right { return left < right }

            return safeCandidate($0) < safeCandidate($1)
        }
        let accounts = ordered.enumerated().map { index, account in
            WidgetAccountSnapshot(
                id: stableID(account.accountKey),
                displayName: safeName(account, fallback: fallbackName(index + 1)),
                plan: account.resolvedPlan,
                isActive: account.accountKey == registry.activeAccountKey,
                fiveHour: limit(account.lastUsage?.primary, at: generatedAt),
                weekly: limit(account.lastUsage?.secondary, at: generatedAt)
            )
        }
        return WidgetSnapshot(
            generatedAtMilliseconds: Int64(generatedAt.timeIntervalSince1970 * 1_000),
            accounts: accounts
        )
    }

    private static func stableID(_ key: AccountKey) -> String {
        SHA256.hash(data: Data(key.rawValue.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func safeCandidate(_ account: AccountRecord) -> String {
        [account.alias, account.accountName ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: isSafeName) ?? ""
    }

    private static func safeName(_ account: AccountRecord, fallback: String) -> String {
        let candidate = safeCandidate(account)
        let value = candidate.isEmpty ? fallback : candidate
        return value.count > 30 ? String(value.prefix(29)) + "…" : value
    }

    private static func isSafeName(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("@") && SecretRedactor.redact(value) == value
    }

    private static func limit(_ window: RateLimitWindow?, at date: Date) -> WidgetLimitSnapshot? {
        guard let window else { return nil }
        return WidgetLimitSnapshot(
            remainingPercent: window.remainingPercent(at: date),
            resetsAtSeconds: window.resetsAt
        )
    }

    private static func attentionScore(_ account: AccountRecord, at date: Date) -> Double {
        let values = [account.lastUsage?.primary, account.lastUsage?.secondary]
            .compactMap { $0?.remainingPercent(at: date) }
        return values.min() ?? 100
    }
}

public enum CodexWidgetContract {
    public static let kind = "com.mesteriis.CodexAuthBar.accounts"
    public static let appGroup = "group.com.mesteriis.CodexAuthBar"
}
