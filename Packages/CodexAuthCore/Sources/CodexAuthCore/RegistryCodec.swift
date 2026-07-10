import Foundation

public enum RegistryError: Error, Equatable, Sendable {
    case invalidJSON
    case unsupportedSchema(Int)
}

public enum RegistryCodec {
    public static func decode(_ data: Data) throws -> RegistryV4 {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RegistryError.invalidJSON
        }
        let version = (object["schema_version"] as? Int) ?? (object["version"] as? Int) ?? 4
        guard version <= RegistryV4.currentSchemaVersion else {
            throw RegistryError.unsupportedSchema(version)
        }
        if version == 2 { return try migrateV2(object) }

        var normalized = object
        normalized["schema_version"] = RegistryV4.currentSchemaVersion
        normalized.removeValue(forKey: "version")
        if normalized["interval_seconds"] == nil,
           let live = normalized["live"] as? [String: Any],
           let interval = live["interval_seconds"] {
            normalized["interval_seconds"] = interval
        }
        normalized.removeValue(forKey: "live")
        normalized.removeValue(forKey: "api")
        normalized.removeValue(forKey: "auto_switch")
        let encoded = try JSONSerialization.data(withJSONObject: normalized)
        return try JSONDecoder().decode(RegistryV4.self, from: encoded)
    }

    public static func encode(_ registry: RegistryV4) throws -> Data {
        var current = registry
        current.schemaVersion = RegistryV4.currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(current) + Data("\n".utf8)
    }

    private static func migrateV2(_ object: [String: Any]) throws -> RegistryV4 {
        let activeEmail = (object["active_email"] as? String)?.lowercased()
        let legacyAccounts = object["accounts"] as? [[String: Any]] ?? []
        var records: [AccountRecord] = []
        for legacy in legacyAccounts {
            guard let email = (legacy["email"] as? String)?.lowercased() else { continue }
            let accountID = legacy["chatgpt_account_id"] as? String ?? email
            let userID = legacy["chatgpt_user_id"] as? String ?? email
            let key = AccountKey("\(userID)::\(accountID)")
            records.append(AccountRecord(
                accountKey: key,
                chatGPTAccountID: accountID,
                chatGPTUserID: userID,
                email: email,
                alias: legacy["alias"] as? String ?? "",
                accountName: legacy["account_name"] as? String,
                plan: (legacy["plan"] as? String).flatMap(PlanType.init(rawValue:)),
                authMode: .chatgpt,
                createdAt: legacy["created_at"] as? Int64 ?? Int64(Date().timeIntervalSince1970),
                lastUsedAt: legacy["last_used_at"] as? Int64
            ))
        }
        let active = records.first(where: { $0.email == activeEmail })?.accountKey
        return RegistryV4(activeAccountKey: active, accounts: records)
    }
}
