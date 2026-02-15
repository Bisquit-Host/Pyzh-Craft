import Foundation
import Security

/// Keychain management tool class for secure storage of sensitive information
enum KeychainManager {
    // MARK: - Constants

    private static let service = Bundle.main.identifier

    // MARK: - Public Methods

    /// Save data to Keychain
    /// - Parameters:
    ///   - data: data to be saved
    ///   - account: account identifier (usually user ID)
    ///   - key: key name
    /// - Returns: Whether the save was successful
    static func save(data: Data, account: String, key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(account).\(key)",
            kSecValueData as String: data,
        ]

        // Delete existing items first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            Logger.shared.debug("Keychain 保存成功 - account: \(account), key: \(key)")
            return true
        } else {
            Logger.shared.error("Keychain 保存失败 - account: \(account), key: \(key), status: \(status)")
            return false
        }
    }

    /// Read data from Keychain
    /// - Parameters:
    ///   - account: account identifier (usually user ID)
    ///   - key: key name
    /// - Returns: The read data, if it does not exist or the read fails, nil is returned
    static func load(account: String, key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(account).\(key)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            Logger.shared.debug("Keychain 读取成功 - account: \(account), key: \(key)")
            return data
        } else if status == errSecItemNotFound {
            Logger.shared.debug("Keychain 项不存在 - account: \(account), key: \(key)")
            return nil
        } else {
            Logger.shared.error("Keychain 读取失败 - account: \(account), key: \(key), status: \(status)")
            return nil
        }
    }

    /// Delete data from Keychain
    /// - Parameters:
    ///   - account: account identifier (usually user ID)
    ///   - key: key name
    /// - Returns: Whether the deletion was successful
    static func delete(account: String, key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(account).\(key)",
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            Logger.shared.debug("Keychain 删除成功 - account: \(account), key: \(key)")
            return true
        } else {
            Logger.shared.error("Keychain 删除失败 - account: \(account), key: \(key), status: \(status)")
            return false
        }
    }

    /// Delete all Keychain data for the account
    /// Use kSecAttrAccount = "\(account).\(key)" when saving. Here you need to find out all the items with the account prefix and then delete them one by one
    /// - Parameter account: Account identifier (usually user ID)
    /// - Returns: Whether all deletions were successful
    static func deleteAll(account: String) -> Bool {
        let accountPrefix = "\(account)."
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status == errSecItemNotFound {
                Logger.shared.debug("Keychain 无数据可删 - account: \(account)")
                return true
            }
            Logger.shared.error("Keychain 查询所有数据失败 - account: \(account), status: \(status)")
            return false
        }

        var allSucceeded = true
        for item in items {
            guard let storedAccount = item[kSecAttrAccount as String] as? String,
                  storedAccount.hasPrefix(accountPrefix) else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: storedAccount,
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
                Logger.shared.error("Keychain 删除单项失败 - account: \(storedAccount), status: \(deleteStatus)")
                allSucceeded = false
            }
        }

        if allSucceeded {
            Logger.shared.debug("Keychain 删除所有数据成功 - account: \(account)")
        }
        return allSucceeded
    }
}
