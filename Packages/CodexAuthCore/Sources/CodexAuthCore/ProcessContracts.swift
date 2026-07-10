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

public struct CodexCapabilities: Sendable {
    public var executable: URL
    public var version: String
    public var supportsProfiles: Bool
    public var supportsDoctorJSON: Bool
    public init(executable: URL, version: String, supportsProfiles: Bool, supportsDoctorJSON: Bool) {
        self.executable = executable
        self.version = version
        self.supportsProfiles = supportsProfiles
        self.supportsDoctorJSON = supportsDoctorJSON
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
