import Foundation
import Testing
@testable import CodexAuthCore

struct AuthParserTests {
    @Test func parsesChatGPTIdentityAndNormalizesEmail() throws {
        let token = jwt([
            "email": "USER@Example.COM",
            "chatgpt_user_id": "user-1",
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "account-1",
                "chatgpt_plan_type": "pro",
            ],
        ])
        let data = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "chatgpt",
            "tokens": [
                "id_token": token,
                "access_token": "access-secret",
                "account_id": "account-1",
            ],
        ])

        let info = try AuthParser.parse(data)

        #expect(info.email == "user@example.com")
        #expect(info.accountKey == AccountKey("user-1::account-1"))
        #expect(info.plan == .pro)
        #expect(info.authMode == .chatgpt)
    }

    @Test func usesDefaultOrganizationForPhoneLogin() throws {
        let token = jwt([
            "email": "phone@example.com",
            "user_id": "user-phone",
            "https://api.openai.com/auth": [
                "organizations": [
                    ["id": "org-first", "is_default": false],
                    ["id": "org-default", "is_default": true],
                ],
            ],
        ])
        let data = try JSONSerialization.data(withJSONObject: [
            "tokens": ["id_token": token, "access_token": "access-secret"],
        ])

        let info = try AuthParser.parse(data)

        #expect(info.chatGPTAccountID == "org-default")
        #expect(info.accountKey?.rawValue == "user-phone::org-default")
    }

    @Test func rejectsMismatchedAccountIDs() throws {
        let token = jwt([
            "email": "user@example.com",
            "chatgpt_user_id": "user-1",
            "https://api.openai.com/auth": ["chatgpt_account_id": "jwt-account"],
        ])
        let data = try JSONSerialization.data(withJSONObject: [
            "tokens": [
                "id_token": token,
                "access_token": "access-secret",
                "account_id": "token-account",
            ],
        ])

        #expect(throws: AuthError.accountIDMismatch) {
            try AuthParser.parse(data)
        }
    }

    @Test func recognizesAPIKeyWithoutExposingItInIdentity() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "apikey",
            "OPENAI_API_KEY": "sk-test-secret",
        ])

        let info = try AuthParser.parse(data)

        #expect(info.authMode == .apiKey)
        #expect(info.openAIAPIKey == "sk-test-secret")
        #expect(info.accountKey == nil)
    }
}

private func jwt(_ payload: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return "header.\(data.base64URLEncodedString()).signature"
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
