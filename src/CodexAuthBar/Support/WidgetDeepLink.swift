import Foundation

enum WidgetDeepLink: Equatable {
    case accounts

    init?(_ url: URL) {
        guard url.scheme == "codexauthbar",
              url.host == "accounts",
              url.path.isEmpty,
              url.query == nil,
              url.fragment == nil,
              url.user == nil,
              url.password == nil,
              url.port == nil
        else { return nil }
        self = .accounts
    }
}
