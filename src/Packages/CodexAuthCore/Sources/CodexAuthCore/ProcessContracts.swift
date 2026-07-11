import Foundation

public enum LoginMethod: Sendable {
    case browser
    case deviceCode
    case apiKey(String)
}

public struct LoginArtifact: Sendable {
    public var authURL: URL
    public init(authURL: URL) { self.authURL = authURL }
}

public enum CredentialStoreMode: String, Codable, Sendable {
    case file
    case keyring
    case auto
    case ephemeral
    case unknown

    public var permitsFileSwitching: Bool { self == .file }
}

public enum DoctorReportParser {
    public static func credentialStore(from data: Data) throws -> CredentialStoreMode {
        let object = try JSONSerialization.jsonObject(with: data)
        return findCredentialStore(in: object) ?? .unknown
    }

    private static func findCredentialStore(in value: Any) -> CredentialStoreMode? {
        if let dictionary = value as? [String: Any] {
            let expectedKeys = ["auth storage mode", "credential_store", "credentials_store", "cli_auth_credentials_store"]
            for key in expectedKeys {
                if let raw = dictionary[key] as? String, let mode = mode(raw) { return mode }
            }
            for nested in dictionary.values {
                if let found = findCredentialStore(in: nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = findCredentialStore(in: nested) { return found }
            }
        }
        return nil
    }

    private static func mode(_ raw: String) -> CredentialStoreMode? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "file": .file
        case "keyring": .keyring
        case "auto": .auto
        case "ephemeral": .ephemeral
        default: nil
        }
    }
}

public enum CredentialStoreConfigParser {
    public static func mode(in contents: String) -> CredentialStoreMode {
        var isTopLevel = true
        for rawLine in contents.split(whereSeparator: \Character.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                isTopLevel = false
                continue
            }
            guard isTopLevel, let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key == "cli_auth_credentials_store" else { continue }
            let rawValue = line[line.index(after: separator)...]
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .lowercased()
            switch rawValue {
            case "file": return .file
            case "keyring": return .keyring
            case "auto": return .auto
            case "ephemeral": return .ephemeral
            default: return .unknown
            }
        }
        return .unknown
    }
}

public struct CodexCapabilities: Sendable {
    public var executable: URL
    public var version: String
    public var supportsProfiles: Bool
    public var supportsDoctorJSON: Bool
    public var credentialStore: CredentialStoreMode
    public init(
        executable: URL,
        version: String,
        supportsProfiles: Bool,
        supportsDoctorJSON: Bool,
        credentialStore: CredentialStoreMode = .unknown
    ) {
        self.executable = executable
        self.version = version
        self.supportsProfiles = supportsProfiles
        self.supportsDoctorJSON = supportsDoctorJSON
        self.credentialStore = credentialStore
    }
}

public struct CodexLaunchRequest: Sendable {
    public var codexHome: URL
    public var cliPath: URL?
    public var bundleIdentifier: String
    public var diagnostics: Bool
    public init(codexHome: URL, cliPath: URL? = nil, bundleIdentifier: String = "com.openai.codex", diagnostics: Bool = false) {
        self.codexHome = codexHome
        self.cliPath = cliPath
        self.bundleIdentifier = bundleIdentifier
        self.diagnostics = diagnostics
    }
}

public protocol CodexProcessControlling: Sendable {
    func capabilities() async throws -> CodexCapabilities
    func performLogin(_ method: LoginMethod) async throws -> LoginArtifact
    func terminateDesktopApp(timeout: Duration) async throws
    func launchDesktopApp(_ request: CodexLaunchRequest) async throws
}
