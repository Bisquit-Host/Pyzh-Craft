import Foundation

/// Authentication Credentials Storage Manager
/// Securely store authentication credentials using Keychain
class AuthCredentialStore {
    // MARK: - Public Methods

    /// Save authentication credentials
    /// - Parameter credential: the authentication credential to be saved
    /// - Returns: Whether the save was successful
    func saveCredential(_ credential: AuthCredential) -> Bool {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(credential)
            return KeychainManager.save(data: data, account: credential.userId, key: "authCredential")
        } catch {
            Logger.shared.error("编码认证凭据失败: \(error.localizedDescription)")
            return false
        }
    }

    /// Load authentication credentials
    /// - Parameter userId: user ID
    /// - Returns: Authentication credentials, returns nil if it does not exist or fails to load
    func loadCredential(userId: String) -> AuthCredential? {
        guard let data = KeychainManager.load(account: userId, key: "authCredential") else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AuthCredential.self, from: data)
        } catch {
            Logger.shared.error("解码认证凭据失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// Delete authentication credentials
    /// - Parameter userId: user ID
    /// - Returns: Whether the deletion was successful
    func deleteCredential(userId: String) -> Bool {
        KeychainManager.delete(account: userId, key: "authCredential")
    }

    /// Remove all authentication credentials for a user
    /// - Parameter userId: user ID
    /// - Returns: Whether the deletion was successful
    func deleteAllCredentials(userId: String) -> Bool {
        KeychainManager.deleteAll(account: userId)
    }

    /// Update authentication credentials
    /// - Parameter credential: updated authentication credentials
    /// - Returns: Whether the update is successful
    func updateCredential(_ credential: AuthCredential) -> Bool {
        saveCredential(credential)
    }
}
