import Foundation

/// Player Data Manager
/// Separate storage using UserProfileStore (plist) and AuthCredentialStore (Keychain)
class PlayerDataManager {
    private let profileStore = UserProfileStore()
    private let credentialStore = AuthCredentialStore()

    // MARK: - Public Methods

    /// Add new player
    /// - Parameters:
    ///   - name: player name
    ///   - uuid: player UUID, if nil, generate offline UUID
    ///   - isOnline: whether it is an online account
    ///   - avatarName: avatar name
    ///   - accToken: access token, default is empty string
    ///   - refreshToken: refresh token, default is empty string
    ///   - xuid: Xbox user ID, default is empty string
    ///   - expiresAt: token expiration time, optional
    /// - Throws: GlobalError when the operation fails
    func addPlayer(
        name: String,
        uuid: String? = nil,
        isOnline: Bool,
        avatarName: String,
        accToken: String = "",
        refreshToken: String = "",
        xuid: String = "",
        expiresAt: Date? = nil
    ) throws {
        let players = try loadPlayersThrowing()

        if playerExists(name: name) {
            throw GlobalError.player(
                i18nKey: "Already Exists",
                level: .notification
            )
        }

        do {
            // Create Player object
            let credential: AuthCredential?
            if isOnline && !accToken.isEmpty {
                // You need to create a Player first to obtain the ID. Here, create a profile first
                let tempId: String
                if let providedUUID = uuid {
                    tempId = providedUUID
                } else {
                    tempId = try PlayerUtils.generateOfflineUUID(for: name)
                }
                credential = AuthCredential(
                    userId: tempId,
                    accessToken: accToken,
                    refreshToken: refreshToken,
                    expiresAt: expiresAt,
                    xuid: xuid
                )
            } else {
                credential = nil
            }

            let newPlayer = try Player(
                name: name,
                uuid: uuid,
                avatar: avatarName.isEmpty ? nil : avatarName,
                credential: credential,
                isCurrent: players.isEmpty
            )

            // save profile
            try profileStore.addProfile(newPlayer.profile)

            // If there is a credential, save it to Keychain
            if let credential = newPlayer.credential {
                if !credentialStore.saveCredential(credential) {
                    // If saving the credential fails, roll back the profile
                    try? profileStore.deleteProfile(byID: newPlayer.id)
                    throw GlobalError.validation(
                        i18nKey: "Failed to save authentication credentials: \(credential.userId)",
                        level: .notification
                    )
                }
            }

            Logger.shared.debug("New player added: \(name)")
        } catch {
            throw GlobalError.player(
                i18nKey: "Creation Failed",
                level: .notification
            )
        }
    }

    /// Add new players (silent version)
    /// - Parameters:
    ///   - name: player name
    ///   - uuid: player UUID, if nil, generate offline UUID
    ///   - isOnline: whether it is an online account
    ///   - avatarName: avatar name
    ///   - accToken: access token, default is empty string
    ///   - refreshToken: refresh token, default is empty string
    ///   - xuid: Xbox user ID, default is empty string
    ///   - expiresAt: token expiration time, optional
    /// - Returns: Whether added successfully
    func addPlayerSilently(
        name: String,
        uuid: String? = nil,
        isOnline: Bool,
        avatarName: String,
        accToken: String = "",
        refreshToken: String = "",
        xuid: String = "",
        expiresAt: Date? = nil
    ) -> Bool {
        do {
            try addPlayer(
                name: name,
                uuid: uuid,
                isOnline: isOnline,
                avatarName: avatarName,
                accToken: accToken,
                refreshToken: refreshToken,
                xuid: xuid,
                expiresAt: expiresAt
            )
            return true
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to add player: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }

    /// Load all saved players (silent version)
    /// - Returns: Player array
    func loadPlayers() -> [Player] {
        do {
            return try loadPlayersThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to load player data: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    /// Load all saved players (throws exception version)
    /// - Returns: Player array
    /// - Throws: GlobalError when the operation fails
    func loadPlayersThrowing() throws -> [Player] {
        // Load all profiles from UserProfileStore
        let profiles = try profileStore.loadProfilesThrowing()

        // Only basic information is loaded, Keychain is not accessed here,
        // Avoid reading the credentials of all players at once on startup (which will trigger multiple keychain password pop-ups)
        let players = profiles.map { profile in
            Player(profile: profile, credential: nil)
        }

        return players
    }

    /// Load authentication credentials on demand for specified players
    /// - Parameter userId: player ID
    /// - Returns: Authentication credentials, if not present, returns nil
    func loadCredential(userId: String) -> AuthCredential? {
        credentialStore.loadCredential(userId: userId)
    }

    /// Check if player exists (case insensitive)
    /// - Parameter name: The name to check
    /// - Returns: Returns true if there is a player with the same name, otherwise returns false
    func playerExists(name: String) -> Bool {
        do {
            let players = try loadPlayersThrowing()
            return players.contains { $0.name.lowercased() == name.lowercased() }
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to check player existence: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }

    /// Delete the player with the specified ID
    /// - Parameter id: Player ID to be deleted
    /// - Throws: GlobalError when the operation fails
    func deletePlayer(byID id: String) throws {
        let players = try loadPlayersThrowing()
        let initialCount = players.count

        // Check if the player to be deleted is the current player
        let isDeletingCurrentPlayer = players.contains { $0.id == id && $0.isCurrent }

        // delete profile
        try profileStore.deleteProfile(byID: id)

        // Remove the credential if it exists
        _ = credentialStore.deleteCredential(userId: id)

        if initialCount > 0 {
            // If the current player is deleted, a new current player needs to be set
            if isDeletingCurrentPlayer {
                let remainingPlayers = try loadPlayersThrowing()
                if !remainingPlayers.isEmpty {
                    var firstPlayer = remainingPlayers[0]
                    firstPlayer.isCurrent = true
                    try updatePlayer(firstPlayer)
                    Logger.shared.debug("The current player has been deleted and the first player has been set as the current player: \(firstPlayer.name)")
                }
            }
            Logger.shared.debug("Player deleted (ID: \(id))")
        }
    }

    /// Delete the player with the specified ID (silent version)
    /// - Parameter id: Player ID to be deleted
    /// - Returns: Whether the deletion was successful
    func deletePlayerSilently(byID id: String) -> Bool {
        do {
            try deletePlayer(byID: id)
            return true
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to delete player: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }

    /// Save player array (silent version)
    /// - Parameter players: Array of players to save
    func savePlayers(_ players: [Player]) {
        do {
            try savePlayersThrowing(players)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to save player data: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// Save player array (throws exception version)
    /// - Parameter players: Array of players to save
    /// - Throws: GlobalError when the operation fails
    func savePlayersThrowing(_ players: [Player]) throws {
        // Separate profiles and credentials
        var profiles: [UserProfile] = []
        var credentials: [AuthCredential] = []

        for player in players {
            profiles.append(player.profile)
            if let credential = player.credential {
                credentials.append(credential)
            }
        }

        // Save profiles
        try profileStore.saveProfilesThrowing(profiles)

        // save credentials
        for credential in credentials where !credentialStore.saveCredential(credential) {
            throw GlobalError.validation(
                i18nKey: "Failed to save authentication credentials: \(credential.userId)",
                level: .notification
            )
        }

        // Clean up deleted player credentials
        let existingProfileIds = Set(profiles.map { $0.id })
        let allCredentials = try loadPlayersThrowing().compactMap { $0.credential }
        for credential in allCredentials where !existingProfileIds.contains(credential.userId) {
            _ = credentialStore.deleteCredential(userId: credential.userId)
        }

        Logger.shared.debug("Player data saved")
    }

    /// Update the specified player's information
    /// - Parameter updatedPlayer: updated player object
    /// - Throws: GlobalError when the operation fails
    func updatePlayer(_ updatedPlayer: Player) throws {
        // Update profile
        try profileStore.updateProfile(updatedPlayer.profile)

        // Update or delete credentials
        if let credential = updatedPlayer.credential {
            if !credentialStore.saveCredential(credential) {
                throw GlobalError.validation(
                    i18nKey: "Failed to update authentication credentials",
                    level: .notification
                )
            }
        } else {
            Logger.shared.debug("No new authentication credentials provided, existing Keychain state retained - userId: \(updatedPlayer.id)")
        }

        Logger.shared.debug("Updated player information: \(updatedPlayer.name)")
    }

    /// Update the specified player's information (silent version)
    /// - Parameter updatedPlayer: updated player object
    /// - Returns: Whether the update is successful
    func updatePlayerSilently(_ updatedPlayer: Player) -> Bool {
        do {
            try updatePlayer(updatedPlayer)
            return true
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to update player information: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }
}
