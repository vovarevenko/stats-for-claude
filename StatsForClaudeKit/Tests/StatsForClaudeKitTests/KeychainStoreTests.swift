import Foundation
import Security
import Testing
@testable import StatsForClaudeKit

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {
    /// Helper that adds and tears down a generic-password keychain item under
    /// a unique service name so tests cannot collide with the real app entry.
    private final class KeychainItem {
        let service: String
        init(service: String, payload: Data) {
            self.service = service
            // Best-effort cleanup before insert.
            let delQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            SecItemDelete(delQuery as CFDictionary)

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecValueData as String: payload,
            ]
            _ = SecItemAdd(addQuery as CFDictionary, nil)
        }

        deinit {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    private func uniqueService() -> String {
        "test.stats-for-claude.\(UUID().uuidString)"
    }

    @Test("missing keychain entry throws tokenNotFound")
    func missingThrowsTokenNotFound() {
        let store = KeychainStore(service: uniqueService())
        #expect(throws: APIError.self) {
            _ = try store.readClaudeToken()
        }
    }

    @Test("malformed payload throws tokenNotFound")
    func malformedThrowsTokenNotFound() throws {
        let service = uniqueService()
        let item = try KeychainItem(service: service, payload: #require("not json".data(using: .utf8)))
        defer { _ = item }
        let store = KeychainStore(service: service)
        #expect(throws: APIError.self) {
            _ = try store.readClaudeToken()
        }
    }

    @Test("payload missing accessToken throws tokenNotFound")
    func missingAccessTokenThrows() throws {
        let service = uniqueService()
        let payload = try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": ["other": "field"],
        ])
        let item = KeychainItem(service: service, payload: payload)
        defer { _ = item }
        let store = KeychainStore(service: service)
        #expect(throws: APIError.self) {
            _ = try store.readClaudeToken()
        }
    }

    @Test("valid payload returns the access token")
    func validPayloadReturnsToken() throws {
        let service = uniqueService()
        let payload = try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": ["accessToken": "secret-abc"],
        ])
        let item = KeychainItem(service: service, payload: payload)
        defer { _ = item }
        let store = KeychainStore(service: service)
        #expect(try store.readClaudeToken() == "secret-abc")
    }

    @Test("readClaudeCredentials extracts refreshToken and millisecond expiresAt")
    func readsFullCredentials() throws {
        let service = uniqueService()
        let expiresMs: Double = 1_900_000_000_000 // 2030-03-17T18:26:40Z
        let payload = try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": [
                "accessToken": "access-1",
                "refreshToken": "refresh-1",
                "expiresAt": expiresMs,
            ],
        ])
        let item = KeychainItem(service: service, payload: payload)
        defer { _ = item }
        let store = KeychainStore(service: service)
        let creds = try store.readClaudeCredentials()
        #expect(creds.accessToken == "access-1")
        #expect(creds.refreshToken == "refresh-1")
        #expect(creds.expiresAt == Date(timeIntervalSince1970: expiresMs / 1000))
    }
}
