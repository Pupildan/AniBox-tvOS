import Foundation
import SwiftUI

@MainActor
final class Session: ObservableObject {
    static let shared = Session()
    private let d = UserDefaults.standard

    @Published var server: String
    @Published var token: String
    @Published var username: String
    @Published var userInfo: JSON = .null
    @Published var expiredNotice = false

    var isLoggedIn: Bool { !token.isEmpty && !server.isEmpty }

    private init() {
        server = d.string(forKey: "server") ?? ""
        token = Keychain.get("token") ?? ""
        username = d.string(forKey: "username") ?? ""
    }

    func updateServer(_ s: String) { server = s; d.set(s, forKey: "server") }

    func login(server raw: String, username: String, password: String, remember: Bool) async throws {
        let s = FnClient.normalize(raw)
        let t = try await FnClient.shared.login(server: s, username: username, password: password)
        updateServer(s)
        self.username = username
        d.set(username, forKey: "username")
        Keychain.set(t, for: "token")
        if remember { Keychain.set(password, for: "password") } else { Keychain.remove("password") }
        token = t
        userInfo = (try? await FnClient.shared.userInfo()) ?? .null
    }

    /// 会话失效：有记住的密码就静默重登
    func handleAuthExpired() {
        guard let pw = Keychain.get("password"), !username.isEmpty else { logout(); expiredNotice = true; return }
        Task {
            do { try await login(server: server, username: username, password: pw, remember: true) }
            catch { logout(); expiredNotice = true }
        }
    }

    func logout() {
        Task { _ = try? await FnClient.shared.call("/v/api/v1/logout", method: "POST") }
        token = ""
        Keychain.remove("token")
    }
}

enum Keychain {
    static func set(_ v: String, for k: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "anibox.\(k)"]
        SecItemDelete(q as CFDictionary)
        var a = q; a[kSecValueData as String] = Data(v.utf8)
        SecItemAdd(a as CFDictionary, nil)
    }
    static func get(_ k: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "anibox.\(k)",
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func remove(_ k: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "anibox.\(k)"] as CFDictionary)
    }
}
