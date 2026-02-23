import SwiftUI

/// A view model that manages the list of players and interacts with PlayerDataManager.
class PlayerListViewModel: ObservableObject {
    @Published var players: [Player] = []
    @Published var currentPlayer: Player?

    private let dataManager = PlayerDataManager()
    private var notificationObserver: NSObjectProtocol?

    init() {
        loadPlayersSafely()
        setupNotifications()
    }
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    private func setupNotifications() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: PlayerSkinService.playerUpdatedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let updatedPlayer = notification.userInfo?["updatedPlayer"] as? Player {
                self?.updatePlayerInList(updatedPlayer)
            }
        }
    }

    // MARK: - Public Methods

    /// Load player list (silent version)
    func loadPlayers() {
        loadPlayersSafely()
    }

    /// Loading player list (throws exception version)
    /// - Throws: GlobalError when the operation fails
    func loadPlayersThrowing() throws {
        players = try dataManager.loadPlayersThrowing()
        currentPlayer = players.first { $0.isCurrent }
        Logger.shared.debug("Player list loaded, quantity: \(players.count)")
        Logger.shared.debug("Current player (after loading): \(currentPlayer?.name ?? "none")")
    }

    /// Safely load player lists
    private func loadPlayersSafely() {
        do {
            try loadPlayersThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to load player list: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            // keep current status
        }
    }

    /// Add new players (silent version)
    /// - Parameter name: The name of the player to be added
    /// - Returns: Whether added successfully
    func addPlayer(name: String) -> Bool {
        do {
            try addPlayerThrowing(name: name)
            return true
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to add player: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }

    /// Add new player (throws exception version)
    /// - Parameter name: The name of the player to be added
    /// - Throws: GlobalError when the operation fails
    func addPlayerThrowing(name: String) throws {
        try dataManager.addPlayer(name: name, isOnline: false, avatarName: "")
        try loadPlayersThrowing()
        Logger.shared.debug("Player \(name) was added successfully and the list has been updated")
        Logger.shared.debug("Current player (after addition): \(currentPlayer?.name ?? "none")")
    }

    /// Add online players (silent version)
    /// - Parameter profile: Minecraft configuration file
    /// - Returns: Whether added successfully
    func addOnlinePlayer(profile: MinecraftProfileResponse) -> Bool {
        do {
            try addOnlinePlayerThrowing(profile: profile)
            return true
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to add online player: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }

    /// Add online player (throws exception version)
    /// - Parameter profile: Minecraft configuration file
    /// - Throws: GlobalError when the operation fails
    func addOnlinePlayerThrowing(profile: MinecraftProfileResponse) throws {
        let avatarUrl =
            profile.skins.isEmpty ? "" : profile.skins[0].url.httpToHttps()
        try dataManager.addPlayer(
            name: profile.name,
            uuid: profile.id,
            isOnline: true,
            avatarName: avatarUrl,
            accToken: profile.accessToken,
            refreshToken: profile.refreshToken,
            xuid: profile.authXuid
        )
        try loadPlayersThrowing()
        Logger.shared.debug("Player \(profile.name) was added successfully and the list has been updated")
        Logger.shared.debug("Current player (after addition): \(currentPlayer?.name ?? "none")")
    }

    /// Remove player (silent version)
    /// - Parameter id: Player ID to be deleted
    /// - Returns: Whether the deletion was successful
    func deletePlayer(byID id: String) -> Bool {
        do {
            try deletePlayerThrowing(byID: id)
            return true
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to delete player: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }

    /// Remove player (throws exception version)
    /// - Parameter id: Player ID to be deleted
    /// - Throws: GlobalError when the operation fails
    func deletePlayerThrowing(byID id: String) throws {
        try dataManager.deletePlayer(byID: id)
        try loadPlayersThrowing()
        Logger.shared.debug("Player (ID: \(id)) was deleted successfully and the list has been updated")
        Logger.shared.debug("Current player (after deletion): \(currentPlayer?.name ?? "none")")
    }

    /// Set current player (silent version)
    /// - Parameter playerId: To be set as the ID of the current player
    func setCurrentPlayer(byID playerId: String) {
        do {
            try setCurrentPlayerThrowing(byID: playerId)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to set current player: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// Set current player (throws exception version)
    /// - Parameter playerId: To be set as the ID of the current player
    /// - Throws: GlobalError when the operation fails
    func setCurrentPlayerThrowing(byID playerId: String) throws {
        guard let index = players.firstIndex(where: { $0.id == playerId })
        else {
            throw GlobalError.player(
                i18nKey: "Not Found",
                level: .notification
            )
        }

        for i in 0..<players.count {
            players[i].isCurrent = (i == index)
        }
        currentPlayer = players[index]

        try dataManager.savePlayersThrowing(players)
        Logger.shared.debug(
            "Current player set (ID: \(playerId), Name: \(currentPlayer?.name ?? "unknown")), data saved"
        )
    }

    /// Check if player exists
    /// - Parameter name: The name to check
    /// - Returns: Returns true if there is a player with the same name, otherwise returns false
    func playerExists(name: String) -> Bool {
        dataManager.playerExists(name: name)
    }

    /// Update the specified player information in the player list
    /// - Parameter updatedPlayer: updated player object
    func updatePlayerInList(_ updatedPlayer: Player) {
        do {
            try updatePlayerInListThrowing(updatedPlayer)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to update player list: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// Update the specified player information in the player list (throws exception version)
    /// - Parameter updatedPlayer: updated player object
    /// - Throws: GlobalError when the operation fails
    func updatePlayerInListThrowing(_ updatedPlayer: Player) throws {
        // Record current player information before update
        Logger.shared.info("[updatePlayerInListThrowing] Current player information before update:")
        // Update local player list
        if let index = players.firstIndex(where: { $0.id == updatedPlayer.id }) {
            players[index] = updatedPlayer

            // If the current player is updated, currentPlayer must also be updated
            if let currentPlayer = currentPlayer, currentPlayer.id == updatedPlayer.id {
                self.currentPlayer = updatedPlayer
            }

            Logger.shared.debug("Player information in the player list has been updated: \(updatedPlayer.name)")
        }
    }
}
