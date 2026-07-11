import Foundation

public struct UserScope: Sendable {
    public var chatGPTUserID: String
    public var accounts: [AccountRecord]
    public init(chatGPTUserID: String, accounts: [AccountRecord]) {
        self.chatGPTUserID = chatGPTUserID
        self.accounts = accounts
    }
}

public enum UsageFetchResult: Sendable {
    case success(RateLimitSnapshot)
    case status(Int)
    case missingAuth
    case transport(String)
}

public enum AccountNameFetchResult: Sendable {
    case success([String: String])
    case unavailable
}

public protocol UsageFetching: Sendable {
    func usage(for account: AccountRecord) async -> UsageFetchResult
    func accountNames(for scope: UserScope) async -> AccountNameFetchResult
}

public enum UsageParser {
    public static func parse(_ data: Data) -> RateLimitSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let limits = root["rate_limit"] as? [String: Any] ?? root
        let primary = window(limits["primary_window"] ?? limits["primary"])
        let secondary = window(limits["secondary_window"] ?? limits["secondary"])
        let creditObject = root["credits"] as? [String: Any]
        let credits = creditObject.map {
            CreditsSnapshot(
                hasCredits: $0["has_credits"] as? Bool ?? false,
                unlimited: $0["unlimited"] as? Bool ?? false,
                balance: ($0["balance"] as? String) ?? ($0["balance"] as? NSNumber)?.stringValue
            )
        }
        let resets = root["rate_limit_reset_credits"] as? [String: Any]
        let resetCredits = (resets?["available_count"] as? NSNumber)?.int64Value
            ?? (root["reset_credits"] as? NSNumber)?.int64Value
        let plan = (root["plan_type"] as? String).flatMap { PlanType(rawValue: $0.lowercased()) }
        guard primary != nil || secondary != nil || credits != nil else { return nil }
        return RateLimitSnapshot(primary: primary, secondary: secondary, credits: credits, resetCredits: resetCredits, planType: plan)
    }

    private static func window(_ value: Any?) -> RateLimitWindow? {
        guard let object = value as? [String: Any], let used = (object["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let minutes = (object["window_minutes"] as? NSNumber)?.int64Value
            ?? (object["limit_window_seconds"] as? NSNumber).map { $0.int64Value / 60 }
        let reset = (object["resets_at"] as? NSNumber)?.int64Value ?? (object["reset_at"] as? NSNumber)?.int64Value
        return RateLimitWindow(usedPercent: used, windowMinutes: minutes, resetsAt: reset)
    }
}
