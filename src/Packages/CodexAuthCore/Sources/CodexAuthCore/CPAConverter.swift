import Foundation

public enum CPAError: Error, Equatable, Sendable {
    case invalidFormat
    case missingIDToken
    case missingAccessToken
    case unsupportedAPIKey
}

public enum CPAConverter {
    public static func toStandard(_ data: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CPAError.invalidFormat }
        guard let idToken = object["id_token"] as? String, !idToken.isEmpty else { throw CPAError.missingIDToken }
        guard let accessToken = object["access_token"] as? String, !accessToken.isEmpty else { throw CPAError.missingAccessToken }
        var tokens: [String: Any] = ["id_token": idToken, "access_token": accessToken]
        if let refresh = object["refresh_token"] as? String, !refresh.isEmpty { tokens["refresh_token"] = refresh }
        if let account = object["account_id"] as? String, !account.isEmpty { tokens["account_id"] = account }
        var standard: [String: Any] = ["auth_mode": "chatgpt", "OPENAI_API_KEY": NSNull(), "tokens": tokens]
        if let lastRefresh = object["last_refresh"] as? String { standard["last_refresh"] = lastRefresh }
        return try JSONSerialization.data(withJSONObject: standard, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
    }

    public static func fromStandard(_ data: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CPAError.invalidFormat }
        if let key = object["OPENAI_API_KEY"] as? String, !key.isEmpty { throw CPAError.unsupportedAPIKey }
        guard let tokens = object["tokens"] as? [String: Any] else { throw CPAError.invalidFormat }
        guard let idToken = tokens["id_token"] as? String, !idToken.isEmpty else { throw CPAError.missingIDToken }
        guard let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty else { throw CPAError.missingAccessToken }
        var cpa: [String: Any] = ["id_token": idToken, "access_token": accessToken]
        for key in ["refresh_token", "account_id"] {
            if let value = tokens[key] as? String, !value.isEmpty { cpa[key] = value }
        }
        if let value = object["last_refresh"] as? String, !value.isEmpty { cpa["last_refresh"] = value }
        return try JSONSerialization.data(withJSONObject: cpa, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
    }
}
