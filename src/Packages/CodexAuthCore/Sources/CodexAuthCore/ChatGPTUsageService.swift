import Foundation

public actor ChatGPTUsageService: UsageFetching {
    private let home: CodexHome
    private let session: URLSession
    private let userAgent: String

    public init(home: CodexHome, version: String = "0.1.0", session: URLSession? = nil) {
        self.home = home
        self.userAgent = "codex-auth-bar/\(version)"
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 7
            configuration.httpMaximumConnectionsPerHost = 5
            self.session = URLSession(
                configuration: configuration,
                delegate: RedirectGuard(allowedHosts: ["chatgpt.com"]),
                delegateQueue: nil
            )
        }
    }

    public func usage(for account: AccountRecord) async -> UsageFetchResult {
        guard let context = authContext(account) else { return .missingAuth }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(context.token)", forHTTPHeaderField: "Authorization")
        request.setValue(context.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .transport("InvalidResponse") }
            guard http.url?.scheme == "https", http.url?.host == "chatgpt.com" else { return .transport("UnexpectedRedirect") }
            guard http.statusCode == 200 else { return .status(http.statusCode) }
            guard let snapshot = UsageParser.parse(data) else { return .transport("InvalidJSON") }
            return .success(snapshot)
        } catch is CancellationError {
            return .transport("Cancelled")
        } catch {
            return .transport(error is URLError && (error as? URLError)?.code == .timedOut ? "TimedOut" : "RequestFailed")
        }
    }

    public func accountNames(for scope: UserScope) async -> AccountNameFetchResult {
        guard let account = scope.accounts.first(where: { authContext($0) != nil }),
              let context = authContext(account)
        else { return .unavailable }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/accounts")!)
        request.setValue("Bearer \(context.token)", forHTTPHeaderField: "Authorization")
        request.setValue(context.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.url?.scheme == "https", http.url?.host == "chatgpt.com",
              http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]]
        else { return .unavailable }
        var names: [String: String] = [:]
        for item in items {
            if let id = item["id"] as? String, let name = item["name"] as? String, !name.isEmpty { names[id] = name }
        }
        return names.isEmpty ? .unavailable : .success(names)
    }

    private func authContext(_ account: AccountRecord) -> (token: String, accountID: String)? {
        guard let data = try? SecureFiles.readRegularFile(home.snapshot(for: account.accountKey)),
              let info = try? AuthParser.parse(data),
              let token = info.accessToken,
              let accountID = info.chatGPTAccountID
        else { return nil }
        return (token, accountID)
    }
}

public struct APIKeyIdentity: Equatable, Sendable {
    public var id: String
    public var email: String
    public init(id: String, email: String) { self.id = id; self.email = email.lowercased() }
}

public protocol APIKeyIdentityResolving: Sendable {
    func identity(apiKey: String) async throws -> APIKeyIdentity
}

public enum APIKeyIdentityError: Error, Sendable { case invalidResponse, status(Int) }

public actor APIKeyIdentityService: APIKeyIdentityResolving {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 7
            self.session = URLSession(
                configuration: configuration,
                delegate: RedirectGuard(allowedHosts: ["api.openai.com"]),
                delegateQueue: nil
            )
        }
    }

    public func identity(apiKey: String) async throws -> APIKeyIdentity {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/me")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIKeyIdentityError.invalidResponse }
        guard http.url?.scheme == "https", http.url?.host == "api.openai.com" else { throw APIKeyIdentityError.invalidResponse }
        guard http.statusCode == 200 else { throw APIKeyIdentityError.status(http.statusCode) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (object["id"] as? String) ?? (object["user_id"] as? String),
              !id.isEmpty,
              let email = object["email"] as? String,
              !email.isEmpty
        else { throw APIKeyIdentityError.invalidResponse }
        return APIKeyIdentity(id: id, email: email)
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHosts: Set<String>
    init(allowedHosts: Set<String>) { self.allowedHosts = allowedHosts }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme == "https",
              request.url?.host.map({ allowedHosts.contains($0.lowercased()) }) == true
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
