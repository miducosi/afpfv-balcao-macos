import Foundation
import Security

/// Guarda a sessão do Supabase no Keychain (nunca em UserDefaults).
/// Usa o keychain de proteção de dados (sem pedidos de palavra-passe do porta-chaves). As compilações de
/// desenvolvimento assinadas ad hoc não têm acesso a esse keychain; aí a sessão fica num ficheiro do contentor
/// da app (só em DEBUG).
nonisolated enum Keychain {
    private static let service = "pt.afpfv.balcao.macos"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func read(_ account: String) -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        #if DEBUG
        if status == errSecMissingEntitlement { return try? Data(contentsOf: fallbackURL(account)) }
        #endif
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    static func write(_ data: Data, for account: String) {
        let query = query(account)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        #if DEBUG
        if status == errSecMissingEntitlement {
            let url = fallbackURL(account)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
        #endif
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
        #if DEBUG
        try? FileManager.default.removeItem(at: fallbackURL(account))
        #endif
    }

    #if DEBUG
    private static func fallbackURL(_ account: String) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("debug-\(account).json")
    }
    #endif
}
