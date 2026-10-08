import Foundation
import Security

// MARK: - Keychain Service

/// Manages secure storage of Xtream credentials in the macOS Keychain.
///
/// Credentials for a source are kept in a *single* generic-password item so that
/// reading them costs one Keychain round-trip instead of two, and the result is
/// memoized for the lifetime of the process. Both matter because every Keychain
/// read on an app whose code signature is not recognised by the item's ACL makes
/// macOS prompt the user for their login password — and the VOD screens ask for
/// credentials on nearly every interaction.
final class KeychainService {
    static let shared = KeychainService()

    struct Credentials {
        let username: String
        let password: String
    }

    private let legacyService = "com.iptvplayer.xtream"
    private let service = "com.iptvplayer.xtream.credentials"

    private let lock = NSLock()
    /// Memoized credentials, keyed by source ID. A cached `nil` means "looked up
    /// and genuinely absent", so a missing source is not retried on every call.
    private var cache: [UUID: Credentials?] = [:]

    private init() {}

    // MARK: - Public API

    /// Stores Xtream credentials for a given source ID.
    func storeCredentials(sourceID: UUID, username: String, password: String) throws {
        let credentials = Credentials(username: username, password: password)
        try write(credentials, for: sourceID)

        lock.lock()
        cache[sourceID] = credentials
        lock.unlock()

        // Drop any pre-existing split-item representation.
        deleteLegacyItems(sourceID: sourceID)
    }

    /// Retrieves Xtream credentials for a given source ID.
    func getCredentials(sourceID: UUID) -> (username: String, password: String)? {
        lock.lock()
        if let cached = cache[sourceID] {
            lock.unlock()
            return cached.map { ($0.username, $0.password) }
        }
        lock.unlock()

        let credentials = read(sourceID: sourceID) ?? migrateLegacyItems(sourceID: sourceID)

        lock.lock()
        cache[sourceID] = credentials
        lock.unlock()

        guard let credentials else { return nil }
        return (credentials.username, credentials.password)
    }

    /// Deletes Xtream credentials for a given source ID.
    func deleteCredentials(sourceID: UUID) {
        lock.lock()
        cache[sourceID] = nil as Credentials?
        lock.unlock()

        delete(service: service, account: sourceID.uuidString)
        deleteLegacyItems(sourceID: sourceID)
    }

    /// Forgets memoized credentials without touching the Keychain. Used when
    /// switching profiles so a long-running process does not hold credentials
    /// for sources it is no longer showing.
    func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // MARK: - Combined Item

    private func write(_ credentials: Credentials, for sourceID: UUID) throws {
        let payload = [
            "username": credentials.username,
            "password": credentials.password
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw IPTVError.keychainError("Failed to encode credentials")
        }

        // Delete existing item first so SecItemAdd cannot fail with errSecDuplicateItem.
        delete(service: service, account: sourceID.uuidString)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw IPTVError.keychainError("Failed to store credentials: \(status)")
        }
    }

    private func read(sourceID: UUID) -> Credentials? {
        guard let data = readData(service: service, account: sourceID.uuidString),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let username = payload["username"],
              let password = payload["password"] else {
            return nil
        }
        return Credentials(username: username, password: password)
    }

    // MARK: - Legacy Migration

    /// Earlier builds stored the username and password as two separate items.
    /// Read them once, fold them into the combined item, and discard the originals.
    private func migrateLegacyItems(sourceID: UUID) -> Credentials? {
        guard let usernameData = readData(service: legacyService, account: legacyKey(sourceID, "username")),
              let passwordData = readData(service: legacyService, account: legacyKey(sourceID, "password")),
              let username = String(data: usernameData, encoding: .utf8),
              let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }

        let credentials = Credentials(username: username, password: password)
        guard (try? write(credentials, for: sourceID)) != nil else {
            // Keep the legacy items if the rewrite failed; they are still readable.
            return credentials
        }
        deleteLegacyItems(sourceID: sourceID)
        return credentials
    }

    private func deleteLegacyItems(sourceID: UUID) {
        delete(service: legacyService, account: legacyKey(sourceID, "username"))
        delete(service: legacyService, account: legacyKey(sourceID, "password"))
    }

    private func legacyKey(_ sourceID: UUID, _ field: String) -> String {
        "\(legacyService).\(sourceID.uuidString).\(field)"
    }

    // MARK: - Primitives

    private func readData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    private func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
