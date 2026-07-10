import Foundation

public enum AuthError: Error, Equatable, Sendable {
    case invalidJSON
    case authFileTooLarge
    case missingTokens
    case missingIDToken
    case missingAccessToken
    case missingEmail
    case missingAccountID
    case missingUserID
    case accountIDMismatch
    case invalidJWT
}

public enum AuthParser {
    public static let maximumBytes = 10 * 1024 * 1024

    public static func parse(_ data: Data) throws -> AuthInfo {
        guard data.count <= maximumBytes else { throw AuthError.authFileTooLarge }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidJSON
        }

        if let apiKey = nonEmpty(root["OPENAI_API_KEY"] as? String) {
            return AuthInfo(
                email: nil,
                chatGPTAccountID: nil,
                chatGPTUserID: nil,
                accountKey: nil,
                accessToken: nil,
                openAIAPIKey: apiKey,
                plan: nil,
                authMode: .apiKey
            )
        }

        guard let tokens = root["tokens"] as? [String: Any] else { throw AuthError.missingTokens }
        guard let idToken = nonEmpty(tokens["id_token"] as? String) else { throw AuthError.missingIDToken }
        guard let accessToken = nonEmpty(tokens["access_token"] as? String) else { throw AuthError.missingAccessToken }
        let payload = try decodePayload(idToken)
        let auth = payload["https://api.openai.com/auth"] as? [String: Any] ?? [:]

        guard let email = nonEmpty((payload["email"] as? String) ?? (auth["email"] as? String)) else {
            throw AuthError.missingEmail
        }
        guard let userID = nonEmpty((auth["chatgpt_user_id"] as? String) ?? (payload["chatgpt_user_id"] as? String) ?? (auth["user_id"] as? String) ?? (payload["user_id"] as? String)) else {
            throw AuthError.missingUserID
        }

        let tokenAccountID = nonEmpty(tokens["account_id"] as? String)
        let jwtAccountID = nonEmpty(auth["chatgpt_account_id"] as? String)
            ?? nonEmpty(payload["chatgpt_account_id"] as? String)
        if let tokenAccountID, let jwtAccountID, tokenAccountID != jwtAccountID {
            throw AuthError.accountIDMismatch
        }
        let organizationID = organizationID(from: auth["organizations"] ?? payload["organizations"])
        guard let accountID = tokenAccountID ?? jwtAccountID ?? organizationID else {
            throw AuthError.missingAccountID
        }
        let rawPlan = nonEmpty(auth["chatgpt_plan_type"] as? String)
            ?? nonEmpty(payload["chatgpt_plan_type"] as? String)
        let plan = rawPlan.flatMap { PlanType(rawValue: $0.lowercased()) } ?? (rawPlan == nil ? nil : .unknown)

        return AuthInfo(
            email: email.lowercased(),
            chatGPTAccountID: accountID,
            chatGPTUserID: userID,
            accountKey: AccountKey("\(userID)::\(accountID)"),
            accessToken: accessToken,
            openAIAPIKey: nil,
            plan: plan,
            authMode: .chatgpt
        )
    }

    private static func decodePayload(_ token: String) throws -> [String: Any] {
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count >= 3 else { throw AuthError.invalidJWT }
        var value = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AuthError.invalidJWT }
        return payload
    }

    private static func organizationID(from value: Any?) -> String? {
        guard let organizations = value as? [[String: Any]] else { return nil }
        let usable = organizations.compactMap { item -> (String, Bool)? in
            guard let id = nonEmpty(item["id"] as? String) else { return nil }
            return (id, item["is_default"] as? Bool ?? false)
        }
        return usable.first(where: { $0.1 })?.0 ?? usable.first?.0
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
