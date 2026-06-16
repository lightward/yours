import Foundation
import Security

// Minimal keychain wrapper for the one secret this app holds: the bearer
// token that carries the google_id (and with it, the ability to decrypt this
// resonance's data server-side). It lives here and nowhere else.
enum Keychain {
    private static let service = "fyi.yours.app"
    private static let account = "native-token"

    static var token: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data
            else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(base as CFDictionary)

            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var attributes = base
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }
}
