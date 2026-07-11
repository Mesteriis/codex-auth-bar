import Foundation

public enum SecretRedactor {
    public static func redact(_ text: String) -> String {
        let rules: [(pattern: String, replacement: String)] = [
            (#"(?i)\"(access_token|refresh_token|id_token|OPENAI_API_KEY)\"\s*[:=]\s*\"[^\"]*\""#, #"\"$1\":\"<redacted>\""#),
            (#"(?i)\bBearer\s+[^\s\"']+"#, "Bearer <redacted>"),
            (#"\beyJ[A-Za-z0-9._-]+"#, "<redacted-token>"),
            (#"\bsk-[A-Za-z0-9_-]+"#, "<redacted-key>"),
        ]
        return rules.reduce(text) { value, rule in
            value.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: .regularExpression
            )
        }
    }
}
