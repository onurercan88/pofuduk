import Foundation
import Security

/// Stores provider secrets in the Keychain (this device only). Keys are never hard-coded in the binary.
struct KeychainSecretStore: Sendable {
    static let weatherAPIKey = "weatherapi.key"
    private let service = "com.pofuduk.secrets"

    func value(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    /// DEBUG only: a developer can supply the key via the scheme's environment variable `WEATHERAPI_KEY`
    /// (never committed). It is copied into the Keychain once.
    func seedFromEnvironmentInDebug() {
        #if DEBUG
        if let key = ProcessInfo.processInfo.environment["WEATHERAPI_KEY"], !key.isEmpty,
           value(for: Self.weatherAPIKey) != key {
            set(key, for: Self.weatherAPIKey)
        }
        #endif
    }
}
