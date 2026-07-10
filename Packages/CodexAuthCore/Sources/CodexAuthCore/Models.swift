import Foundation

public struct AccountKey: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public enum PlanType: String, Codable, CaseIterable, Sendable {
    case free, plus, prolite, pro, team, business, enterprise, edu, unknown

    public var label: String {
        switch self {
        case .free: "Free"
        case .plus: "Plus"
        case .prolite: "Pro Lite"
        case .pro: "Pro"
        case .team, .business: "Business"
        case .enterprise: "Enterprise"
        case .edu: "Edu"
        case .unknown: "Unknown"
        }
    }
}

public enum AuthMode: String, Codable, Sendable {
    case chatgpt
    case apiKey = "apikey"
}

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var windowMinutes: Int64?
    public var resetsAt: Int64?

    public init(usedPercent: Double, windowMinutes: Int64? = nil, resetsAt: Int64? = nil) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    public func remainingPercent(at date: Date = .now) -> Double {
        if let resetsAt, resetsAt <= Int64(date.timeIntervalSince1970) { return 100 }
        return max(0, min(100, 100 - usedPercent))
    }
}

public struct CreditsSnapshot: Codable, Equatable, Sendable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String? = nil) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited, balance
    }
}

public struct RateLimitSnapshot: Codable, Equatable, Sendable {
    public var primary: RateLimitWindow?
    public var secondary: RateLimitWindow?
    public var credits: CreditsSnapshot?
    public var resetCredits: Int64?
    public var planType: PlanType?

    public init(
        primary: RateLimitWindow? = nil,
        secondary: RateLimitWindow? = nil,
        credits: CreditsSnapshot? = nil,
        resetCredits: Int64? = nil,
        planType: PlanType? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.resetCredits = resetCredits
        self.planType = planType
    }

    enum CodingKeys: String, CodingKey {
        case primary, secondary, credits
        case resetCredits = "reset_credits"
        case planType = "plan_type"
    }
}

public struct RolloutSignature: Codable, Equatable, Sendable {
    public var path: String
    public var eventTimestampMilliseconds: Int64

    public init(path: String, eventTimestampMilliseconds: Int64) {
        self.path = path
        self.eventTimestampMilliseconds = eventTimestampMilliseconds
    }

    enum CodingKeys: String, CodingKey {
        case path
        case eventTimestampMilliseconds = "event_timestamp_ms"
    }
}

public struct AccountRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: AccountKey { accountKey }
    public var accountKey: AccountKey
    public var chatGPTAccountID: String
    public var chatGPTUserID: String
    public var email: String
    public var alias: String
    public var accountName: String?
    public var plan: PlanType?
    public var authMode: AuthMode?
    public var createdAt: Int64
    public var lastUsedAt: Int64?
    public var lastUsage: RateLimitSnapshot?
    public var lastUsageAt: Int64?
    public var lastLocalRollout: RolloutSignature?

    public init(
        accountKey: AccountKey,
        chatGPTAccountID: String,
        chatGPTUserID: String,
        email: String,
        alias: String = "",
        accountName: String? = nil,
        plan: PlanType? = nil,
        authMode: AuthMode? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970),
        lastUsedAt: Int64? = nil,
        lastUsage: RateLimitSnapshot? = nil,
        lastUsageAt: Int64? = nil,
        lastLocalRollout: RolloutSignature? = nil
    ) {
        self.accountKey = accountKey
        self.chatGPTAccountID = chatGPTAccountID
        self.chatGPTUserID = chatGPTUserID
        self.email = email.lowercased()
        self.alias = alias
        self.accountName = accountName
        self.plan = plan
        self.authMode = authMode
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.lastUsage = lastUsage
        self.lastUsageAt = lastUsageAt
        self.lastLocalRollout = lastLocalRollout
    }

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case chatGPTAccountID = "chatgpt_account_id"
        case chatGPTUserID = "chatgpt_user_id"
        case email, alias
        case accountName = "account_name"
        case plan
        case authMode = "auth_mode"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
        case lastLocalRollout = "last_local_rollout"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accountKey = try values.decode(AccountKey.self, forKey: .accountKey)
        chatGPTAccountID = try values.decode(String.self, forKey: .chatGPTAccountID)
        chatGPTUserID = try values.decode(String.self, forKey: .chatGPTUserID)
        email = try values.decode(String.self, forKey: .email).lowercased()
        alias = try values.decodeIfPresent(String.self, forKey: .alias) ?? ""
        accountName = try values.decodeIfPresent(String.self, forKey: .accountName)
        plan = try values.decodeIfPresent(PlanType.self, forKey: .plan)
        authMode = try values.decodeIfPresent(AuthMode.self, forKey: .authMode)
        createdAt = try values.decodeIfPresent(Int64.self, forKey: .createdAt) ?? Int64(Date().timeIntervalSince1970)
        lastUsedAt = try values.decodeIfPresent(Int64.self, forKey: .lastUsedAt)
        lastUsage = try values.decodeIfPresent(RateLimitSnapshot.self, forKey: .lastUsage)
        lastUsageAt = try values.decodeIfPresent(Int64.self, forKey: .lastUsageAt)
        lastLocalRollout = try values.decodeIfPresent(RolloutSignature.self, forKey: .lastLocalRollout)
    }

    public var displayName: String {
        if !alias.isEmpty { return alias }
        if let accountName, !accountName.isEmpty { return accountName }
        return email
    }

    public var resolvedPlan: PlanType? { lastUsage?.planType ?? plan }
}

public struct RegistryV4: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var activeAccountKey: AccountKey?
    public var previousActiveAccountKey: AccountKey?
    public var activeAccountActivatedAtMilliseconds: Int64?
    public var intervalSeconds: UInt16
    public var accounts: [AccountRecord]

    public init(
        activeAccountKey: AccountKey? = nil,
        previousActiveAccountKey: AccountKey? = nil,
        activeAccountActivatedAtMilliseconds: Int64? = nil,
        intervalSeconds: UInt16 = 60,
        accounts: [AccountRecord] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.activeAccountKey = activeAccountKey
        self.previousActiveAccountKey = previousActiveAccountKey
        self.activeAccountActivatedAtMilliseconds = activeAccountActivatedAtMilliseconds
        self.intervalSeconds = intervalSeconds
        self.accounts = accounts
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case activeAccountKey = "active_account_key"
        case previousActiveAccountKey = "previous_active_account_key"
        case activeAccountActivatedAtMilliseconds = "active_account_activated_at_ms"
        case intervalSeconds = "interval_seconds"
        case accounts
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        activeAccountKey = try values.decodeIfPresent(AccountKey.self, forKey: .activeAccountKey)
        previousActiveAccountKey = try values.decodeIfPresent(AccountKey.self, forKey: .previousActiveAccountKey)
        activeAccountActivatedAtMilliseconds = try values.decodeIfPresent(Int64.self, forKey: .activeAccountActivatedAtMilliseconds)
        intervalSeconds = try values.decodeIfPresent(UInt16.self, forKey: .intervalSeconds) ?? 60
        accounts = try values.decodeIfPresent([AccountRecord].self, forKey: .accounts) ?? []
    }
}

public struct AuthInfo: Equatable, Sendable {
    public var email: String?
    public var chatGPTAccountID: String?
    public var chatGPTUserID: String?
    public var accountKey: AccountKey?
    public var accessToken: String?
    public var openAIAPIKey: String?
    public var plan: PlanType?
    public var authMode: AuthMode
}
