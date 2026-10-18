import Foundation
import Security

@MainActor
struct SavedLogin {
    enum Profile { case primary, local }
    let profile:Profile
    private let defaults:UserDefaults
    init(profile:Profile = .primary, defaults:UserDefaults = UserDefaults(suiteName:"com.ultimaxb.UltimaMac")!) {
        self.profile = profile; self.defaults = defaults
    }
    private var service:String { "com.ultimaxb.UltimaMac.login" + (profile == .local ? ".local" : "") }
    private func key(_ name:String)->String { (profile == .local ? "localTestCenter." : "") + name }
    var host: String { defaults.string(forKey: key("server")) ?? (profile == .local ? "127.0.0.1" : "login.uo1998.com") }
    var port: String { defaults.string(forKey: key("port")) ?? (profile == .local ? "2593" : "5000") }
    var account: String { defaults.string(forKey: key("account")) ?? "" }
    var remembersPassword: Bool { defaults.bool(forKey: key("rememberPassword")) }
    private func query(host: String, port: String, account: String) -> [String: Any] {
        let key = String(data: try! JSONSerialization.data(withJSONObject: [host.lowercased(), port, account]), encoding: .utf8)!
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    func password() -> String? {
        guard remembersPassword else { return nil }
        var q = query(host: host, port: port, account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func save(host: String, port: String, account: String, password: String, remember: Bool) -> OSStatus {
        defaults.set(host, forKey: key("server"))
        defaults.set(port, forKey: key("port"))
        defaults.set(account, forKey: key("account"))
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
        defaults.set(remember && result == errSecSuccess, forKey: key("rememberPassword"))
        return result
    }
    func forget() -> OSStatus {
        let result = SecItemDelete(query(host: host, port: port, account: account) as CFDictionary)
        defaults.set(false, forKey: key("rememberPassword"))
        return result == errSecItemNotFound ? errSecSuccess : result
    }
}
