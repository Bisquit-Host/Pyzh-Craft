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
        Logger.shared.debug("玩家列表已加载，数量: \(players.count)")
        Logger.shared.debug("当前玩家 (加载后): \(currentPlayer?.name ?? "无")")
    }

    /// Safely load player lists
    private func loadPlayersSafely() {
        do {
            try loadPlayersThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("加载玩家列表失败: \(globalError.chineseMessage)")
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
            Logger.shared.error("添加玩家失败: \(globalError.chineseMessage)")
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
        Logger.shared.debug("玩家 \(name) 添加成功，列表已更新。")
        Logger.shared.debug("当前玩家 (添加后): \(currentPlayer?.name ?? "无")")
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
            Logger.shared.error("添加在线玩家失败: \(globalError.chineseMessage)")
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
        Logger.shared.debug("玩家 \(profile.name) 添加成功，列表已更新。")
        Logger.shared.debug("当前玩家 (添加后): \(currentPlayer?.name ?? "无")")
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
            Logger.shared.error("删除玩家失败: \(globalError.chineseMessage)")
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
        Logger.shared.debug("玩家 (ID: \(id)) 删除成功，列表已更新。")
        Logger.shared.debug("当前玩家 (删除后): \(currentPlayer?.name ?? "无")")
    }

    /// Set current player (silent version)
    /// - Parameter playerId: To be set as the ID of the current player
    func setCurrentPlayer(byID playerId: String) {
        do {
            try setCurrentPlayerThrowing(byID: playerId)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("设置当前玩家失败: \(globalError.chineseMessage)")
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
                chineseMessage: "玩家不存在: \(playerId)",
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
            "已设置玩家 (ID: \(playerId), 姓名: \(currentPlayer?.name ?? "未知")) 为当前玩家，数据已保存。"
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
            Logger.shared.error("更新玩家列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// Update the specified player information in the player list (throws exception version)
    /// - Parameter updatedPlayer: updated player object
    /// - Throws: GlobalError when the operation fails
    func updatePlayerInListThrowing(_ updatedPlayer: Player) throws {
        // Record current player information before update
        Logger.shared.info("[updatePlayerInListThrowing] 更新前当前玩家信息:")
        // Update local player list
        if let index = players.firstIndex(where: { $0.id == updatedPlayer.id }) {
            players[index] = updatedPlayer

            // If the current player is updated, currentPlayer must also be updated
            if let currentPlayer = currentPlayer, currentPlayer.id == updatedPlayer.id {
                self.currentPlayer = updatedPlayer
            }

            Logger.shared.debug("玩家列表中的玩家信息已更新: \(updatedPlayer.name)")
        }
    }
}
