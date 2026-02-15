import Foundation

/// User basic information storage manager
/// Use UserDefaults (plist) to store basic user information
class UserProfileStore {
    private let profilesKey = "userProfiles"

    // MARK: - Public Methods

    /// Load all user basic information
    /// - Returns: array of user basic information
    func loadProfiles() -> [UserProfile] {
        guard let profilesData = UserDefaults.standard.data(forKey: profilesKey) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([UserProfile].self, from: profilesData)
        } catch {
            Logger.shared.error("加载用户基本信息失败: \(error.localizedDescription)")
            return []
        }
    }

    /// Load all user basic information (throws exception version)
    /// - Returns: array of user basic information
    /// - Throws: GlobalError when the operation fails
    func loadProfilesThrowing() throws -> [UserProfile] {
        guard let profilesData = UserDefaults.standard.data(forKey: profilesKey) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([UserProfile].self, from: profilesData)
        } catch {
            throw GlobalError.validation(
                chineseMessage: "加载用户基本信息失败: \(error.localizedDescription)",
                i18nKey: "error.validation.user_profile_load_failed",
                level: .notification
            )
        }
    }

    /// Save array of user basic information
    /// - Parameter profiles: Array of basic user information to be saved
    func saveProfiles(_ profiles: [UserProfile]) {
        do {
            try saveProfilesThrowing(profiles)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("保存用户基本信息失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// Save the user's basic information array (throws an exception version)
    /// - Parameter profiles: Array of basic user information to be saved
    /// - Throws: GlobalError when the operation fails
    func saveProfilesThrowing(_ profiles: [UserProfile]) throws {
        do {
            let encoder = JSONEncoder()
            let encodedData = try encoder.encode(profiles)
            UserDefaults.standard.set(encodedData, forKey: profilesKey)
            Logger.shared.debug("用户基本信息已保存")
        } catch {
            throw GlobalError.validation(
                chineseMessage: "保存用户基本信息失败: \(error.localizedDescription)",
                i18nKey: "error.validation.user_profile_save_failed",
                level: .notification
            )
        }
    }

    /// Add basic user information
    /// - Parameter profile: Basic information of the user to be added
    /// - Throws: GlobalError when the operation fails
    func addProfile(_ profile: UserProfile) throws {
        var profiles = try loadProfilesThrowing()

        if profiles.contains(where: { $0.id == profile.id }) {
            throw GlobalError.player(
                chineseMessage: "用户已存在: \(profile.name)",
                i18nKey: "error.player.already_exists",
                level: .notification
            )
        }

        // If it is the first user, set it to the current user
        if profiles.isEmpty {
            var newProfile = profile
            newProfile.isCurrent = true
            profiles.append(newProfile)
        } else {
            profiles.append(profile)
        }

        try saveProfilesThrowing(profiles)
        Logger.shared.debug("已添加新用户: \(profile.name)")
    }

    /// Update basic user information
    /// - Parameter profile: updated user basic information
    /// - Throws: GlobalError when the operation fails
    func updateProfile(_ profile: UserProfile) throws {
        var profiles = try loadProfilesThrowing()

        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw GlobalError.player(
                chineseMessage: "要更新的用户不存在: \(profile.name)",
                i18nKey: "error.player.not_found_for_update",
                level: .notification
            )
        }

        profiles[index] = profile
        try saveProfilesThrowing(profiles)
        Logger.shared.debug("已更新用户信息: \(profile.name)")
    }

    /// Delete basic user information
    /// - Parameter id: User ID to be deleted
    /// - Throws: GlobalError when the operation fails
    func deleteProfile(byID id: String) throws {
        var profiles = try loadProfilesThrowing()
        let initialCount = profiles.count

        // Check if the user to be deleted is the current user
        let isDeletingCurrentUser = profiles.contains { $0.id == id && $0.isCurrent }

        profiles.removeAll { $0.id == id }

        if profiles.count < initialCount {
            // If the current user is deleted, a new current user needs to be set up
            if isDeletingCurrentUser && !profiles.isEmpty {
                profiles[0].isCurrent = true
                Logger.shared.debug("当前用户被删除，已设置第一个用户为当前用户: \(profiles[0].name)")
            }

            try saveProfilesThrowing(profiles)
            Logger.shared.debug("已删除用户 (ID: \(id))")
        } else {
            throw GlobalError.player(
                chineseMessage: "用户不存在: \(id)",
                i18nKey: "error.player.not_found",
                level: .notification
            )
        }
    }

    /// Check if user exists
    /// - Parameter id: User ID to check
    /// - Returns: true if exists, false otherwise
    func profileExists(id: String) -> Bool {
        do {
            let profiles = try loadProfilesThrowing()
            return profiles.contains { $0.id == id }
        } catch {
            Logger.shared.error("检查用户存在性失败: \(error.localizedDescription)")
            return false
        }
    }
}
