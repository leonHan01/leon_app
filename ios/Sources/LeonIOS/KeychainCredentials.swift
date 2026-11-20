import Foundation
import Security

actor KeychainCredentials: CredentialStorage {
    private var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.leon.ios.session", kSecAttrAccount as String:"current-user"] }
    func read() throws -> Credentials? {
        var input = query; input[kSecReturnData as String] = true; input[kSecMatchLimit as String] = kSecMatchLimitOne
        var output: CFTypeRef?; let status = SecItemCopyMatching(input as CFDictionary,&output)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = output as? Data else { throw NativeError(message:"无法读取钥匙串（\(status)）。") }
        return try JSONDecoder().decode(Credentials.self,from:data)
    }
    func save(_ credentials: Credentials?) throws {
        guard let credentials else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw NativeError(message:"无法移除钥匙串登录（\(status)）。") }; return
        }
        let data = try JSONEncoder().encode(credentials)
        var status = SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var input = query; input[kSecValueData as String] = data
            input[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(input as CFDictionary,nil)
        }
        guard status == errSecSuccess else { throw NativeError(message:"无法保存钥匙串登录（\(status)）。") }
    }
}
