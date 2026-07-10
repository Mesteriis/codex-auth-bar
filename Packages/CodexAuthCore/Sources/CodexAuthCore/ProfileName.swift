import Foundation

public struct ProfileName: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty,
              rawValue.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) ||
                  (byte >= 65 && byte <= 90) ||
                  (byte >= 97 && byte <= 122) ||
                  byte == 95 || byte == 45
              })
        else { return nil }
        self.rawValue = rawValue
    }

    public init?(_ rawValue: String) { self.init(rawValue: rawValue) }
    public var description: String { rawValue }
}
