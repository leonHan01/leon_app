import Foundation
import Security

// Only the throwaway keychain path supplied by test-macos-signing.sh is used.
// These checks never query the login keychain or read an application token.
SecKeychainSetUserInteractionAllowed(false)
#if UPDATE_BUILD
print("Keychain upgrade fixture: updated binary")
#else
print("Keychain upgrade fixture: original binary")
#endif

func require(_ status: OSStatus, _ operation: String) {
    guard status == errSecSuccess else {
        fputs("FAIL: \(operation) returned \(status); interaction is disabled.\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count == 3 else { exit(2) }
let mode = CommandLine.arguments[1]
let path = CommandLine.arguments[2]
guard ["create", "read"].contains(mode),
      URL(fileURLWithPath: path).lastPathComponent.hasPrefix("leon-signing-check-") else { exit(2) }
let fixture = Data("Leon signing upgrade test; this is not a real credential.".utf8)
let password = "isolated-test-keychain"
var keychain: SecKeychain?
if mode == "create" {
    require(SecKeychainCreate(path, UInt32(password.utf8.count), password, false, nil, &keychain), "create test keychain")
} else {
    require(SecKeychainOpen(path, &keychain), "open test keychain")
}
guard let keychain else { exit(2) }
require(SecKeychainUnlock(keychain, UInt32(password.utf8.count), password, true), "unlock test keychain")
var query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.leon.tests.keychain-signing",
    kSecAttrAccount as String: "upgrade-fixture"
]
if mode == "create" {
    query[kSecUseKeychain as String] = keychain
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    query[kSecValueData as String] = fixture
    require(SecItemAdd(query as CFDictionary, nil), "write test credential")
    print("PASS: wrote isolated test credential")
} else {
    query[kSecMatchSearchList as String] = [keychain]
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    require(SecItemCopyMatching(query as CFDictionary, &result), "read test credential after upgrade")
    guard let data = result as? Data, data == fixture else { exit(3) }
    print("PASS: read the existing test credential with interaction disabled")
}
