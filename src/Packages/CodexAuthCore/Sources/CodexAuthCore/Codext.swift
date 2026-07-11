import CryptoKit
import Foundation

public enum CodextArchitecture: String, Codable, Sendable { case arm64, x64 }

public struct CodextArtifact: Codable, Equatable, Sendable {
    public var architecture: CodextArchitecture
    public var url: URL
    public var sha256: String
    public var size: Int64
    public init(architecture: CodextArchitecture, url: URL, sha256: String, size: Int64) {
        self.architecture = architecture
        self.url = url
        self.sha256 = sha256
        self.size = size
    }
}

public struct CodextManifest: Codable, Equatable, Sendable {
    public var version: String
    public var artifacts: [CodextArtifact]
}

public enum CodextError: Error, Equatable, Sendable { case untrustedOrigin, sizeMismatch, hashMismatch, unsafeArchive }

public enum CodextVerifier {
    public static func verify(file: URL, artifact: CodextArtifact) throws {
        guard artifact.url.scheme == "https", artifact.url.host?.lowercased() == "github.com" else { throw CodextError.untrustedOrigin }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard size == artifact.size else { throw CodextError.sizeMismatch }
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash.caseInsensitiveCompare(artifact.sha256) == .orderedSame else { throw CodextError.hashMismatch }
    }
}

public enum CodextArchiveValidator {
    public static func validate(entries: [String]) throws {
        let normalized = entries.map { entry in
            entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
        }
        guard normalized.allSatisfy({ entry in
            !entry.isEmpty && !entry.hasPrefix("/") &&
                !entry.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        }), Set(normalized) == Set(["codext", "codex-code-mode-host"]), normalized.count == 2
        else { throw CodextError.unsafeArchive }
    }

    public static func validateVerboseListing(_ lines: [String]) throws {
        let nonempty = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard nonempty.count == 2,
              nonempty.allSatisfy({ $0.first == "-" }),
              Set(nonempty.compactMap { $0.split(whereSeparator: \.isWhitespace).last.map(String.init) })
                == Set(["codext", "codex-code-mode-host"])
        else { throw CodextError.unsafeArchive }
    }
}
