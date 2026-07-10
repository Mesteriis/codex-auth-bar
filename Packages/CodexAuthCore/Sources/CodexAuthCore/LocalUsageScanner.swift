import Foundation

public struct LocalUsageEvent: Sendable {
    public var snapshot: RateLimitSnapshot
    public var signature: RolloutSignature
}

public enum LocalUsageScanner {
    public static func newest(home: CodexHome, activatedAtMilliseconds: Int64?) throws -> LocalUsageEvent? {
        let sessions = home.root.appending(path: "sessions", directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
        let newest = try files.max {
            let left = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let right = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return left < right
        }
        guard let newest, let text = String(data: try Data(contentsOf: newest), encoding: .utf8) else { return nil }
        var result: LocalUsageEvent?
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["type"] as? String == "event_msg",
                  let payload = root["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let limits = payload["rate_limits"],
                  let limitsData = try? JSONSerialization.data(withJSONObject: limits),
                  let snapshot = UsageParser.parse(limitsData)
            else { continue }
            let timestamp = timestampMilliseconds(root["timestamp"] ?? payload["timestamp"])
            guard activatedAtMilliseconds == nil || timestamp >= activatedAtMilliseconds! else { continue }
            result = LocalUsageEvent(snapshot: snapshot, signature: RolloutSignature(path: newest.path, eventTimestampMilliseconds: timestamp))
        }
        return result
    }

    private static func timestampMilliseconds(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value > 10_000_000_000 ? number.int64Value : number.int64Value * 1_000 }
        if let string = value as? String, let date = ISO8601DateFormatter().date(from: string) { return Int64(date.timeIntervalSince1970 * 1_000) }
        return Int64(Date().timeIntervalSince1970 * 1_000)
    }
}
