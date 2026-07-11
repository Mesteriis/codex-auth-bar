import Foundation

public enum RegistryError: Error, Equatable, Sendable {
    case invalidJSON
    case unsupportedSchema(Int)
    case legacySnapshotContextRequired
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
        if version == 2 { throw RegistryError.legacySnapshotContextRequired }

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

}
