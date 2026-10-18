import Foundation
import Security

@MainActor
enum SavedLogin {
    private static let defaults = UserDefaults(suiteName: "com.ultimaxb.UltimaMac")!
    private static let service = "com.ultimaxb.UltimaMac.login"
    static var host: String { defaults.string(forKey: "server") ?? "login.uo1998.com" }
    static var port: String { defaults.string(forKey: "port") ?? "5000" }
    static var account: String { defaults.string(forKey: "account") ?? "" }
    static var remembersPassword: Bool { defaults.bool(forKey: "rememberPassword") }
    private static func query(host: String, port: String, account: String) -> [String: Any] {
        let key = String(data: try! JSONSerialization.data(withJSONObject: [host.lowercased(), port, account]), encoding: .utf8)!
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    static func password() -> String? {
        guard remembersPassword else { return nil }
        var q = query(host: host, port: port, account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(host: String, port: String, account: String, password: String, remember: Bool) -> OSStatus {
        defaults.set(host, forKey: "server")
        defaults.set(port, forKey: "port")
        defaults.set(account, forKey: "account")
        var result: OSStatus = errSecSuccess
        let q = query(host: host, port: port, account: account)
        if remember {
            let values = [kSecValueData as String: Data(password.utf8)]
            result = SecItemUpdate(q as CFDictionary, values as CFDictionary)
            if result == errSecItemNotFound {
                var item = q
                item[kSecValueData as String] = Data(password.utf8)
                item[kSecAttrLabel as String] = "UltimaMac shard login"
                result = SecItemAdd(item as CFDictionary, nil)
            }
        } else {
            result = SecItemDelete(q as CFDictionary)
            if result == errSecItemNotFound { result = errSecSuccess }
        }
        defaults.set(remember && result == errSecSuccess, forKey: "rememberPassword")
        return result
    }
    static func forget() -> OSStatus {
        let result = SecItemDelete(query(host: host, port: port, account: account) as CFDictionary)
        defaults.set(false, forKey: "rememberPassword")
        return result == errSecItemNotFound ? errSecSuccess : result
    }
}
