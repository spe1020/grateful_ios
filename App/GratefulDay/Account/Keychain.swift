import Foundation
import Security

/// The result of a Keychain read. A failed read is never "not found"
/// (design §7): only `errSecItemNotFound` maps to `.notFound`.
enum KeychainRead: Equatable {
    case found(Data)
    case notFound
    /// `errSecInteractionNotAllowed`: the device is locked.
    case locked
    case failed(OSStatus)

    init(status: OSStatus, data: Data?) {
        switch status {
        case errSecSuccess:
            if let data { self = .found(data) } else { self = .failed(errSecDecode) }
        case errSecItemNotFound: self = .notFound
        case errSecInteractionNotAllowed: self = .locked
        default: self = .failed(status)
        }
    }
}

/// The Keychain operations the app needs. Injected so tests can drive every
/// result, including failures.
protocol KeychainStoring: AnyObject {
    func read(service: String, account: String, synchronizable: Bool) -> KeychainRead
    /// Adds the item; fails with `errSecDuplicateItem` if it exists.
    func add(_ data: Data, service: String, account: String, synchronizable: Bool, accessibility: CFString) -> OSStatus
    func delete(service: String, account: String, synchronizable: Bool) -> OSStatus
    /// Accounts (item names) under a service.
    func accounts(service: String, synchronizable: Bool) -> Result<[String], OSStatusError>
}

struct OSStatusError: Error, Equatable { let status: OSStatus }

/// The system Keychain (generic-password items).
final class SystemKeychain: KeychainStoring {
    private func base(service: String, account: String?, synchronizable: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!,
        ]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    func read(service: String, account: String, synchronizable: Bool) -> KeychainRead {
        var q = base(service: service, account: account, synchronizable: synchronizable)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        return KeychainRead(status: status, data: out as? Data)
    }

    func add(_ data: Data, service: String, account: String, synchronizable: Bool, accessibility: CFString) -> OSStatus {
        var q = base(service: service, account: account, synchronizable: synchronizable)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = accessibility
        return SecItemAdd(q as CFDictionary, nil)
    }

    func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
        SecItemDelete(base(service: service, account: account, synchronizable: synchronizable) as CFDictionary)
    }

    func accounts(service: String, synchronizable: Bool) -> Result<[String], OSStatusError> {
        var q = base(service: service, account: nil, synchronizable: synchronizable)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            let items = (out as? [[String: Any]]) ?? []
            return .success(items.compactMap { $0[kSecAttrAccount as String] as? String })
        case errSecItemNotFound:
            return .success([])
        default:
            return .failure(OSStatusError(status: status))
        }
    }
}
