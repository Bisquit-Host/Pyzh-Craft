import SwiftUI

/// Game Operation Manager
/// Provides general game-related operations, such as displaying in Finder, deleting games, etc
@MainActor
class GameActionManager: ObservableObject {

    static let shared = GameActionManager()

    private init() {}

    // MARK: - Public Methods

    /// Show game directory in Finder
    /// - Parameter game: game version information
    func showInFinder(game: GameVersionInfo) {
        let gameDirectory = AppPaths.profileDirectory(gameName: game.gameName)

        // Check if directory exists
        guard FileManager.default.fileExists(atPath: gameDirectory.path) else {
            Logger.shared.warning("游戏目录不存在: \(gameDirectory.path)")
            return
        }

        // Show directory in Finder
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: gameDirectory.path)
        Logger.shared.info("在访达中显示游戏目录: \(game.gameName)")
    }

    /// Delete the game and its folder
    /// - Parameters:
    ///   - game: game version information to be deleted
    ///   - gameRepository: game repository
    ///   - selectedItem: currently selected sidebar item (for switching after deletion)
    ///   - gameType: game type binding (set to true when switching to the resource page)
    func deleteGame(
        game: GameVersionInfo,
        gameRepository: GameRepository,
        selectedItem: Binding<SidebarItem>? = nil,
        gameType: Binding<Bool>? = nil
    ) {
        Task {
            do {
                // Deletion is not allowed while the game is running
                if GameProcessManager.shared.isGameRunning(gameId: game.id) {
                    let error = GlobalError.validation(
                        chineseMessage: "游戏运行中，无法删除",
                        i18nKey: "Game is running, cannot delete",
                        level: .notification
                    )
                    GlobalErrorHandler.shared.handle(error)
                    return
                }

                // Switch to other games or resource pages first to avoid page reloading after deletion
                if let selectedItem = selectedItem {
                    await MainActor.run {
                        if let firstGame = gameRepository.games.first(where: {
                            $0.id != game.id
                        }) {
                            selectedItem.wrappedValue = .game(firstGame.id)
                        } else {
                            selectedItem.wrappedValue = .resource(.mod)
                            // When switching to the resource page, set gameType to true
                            gameType?.wrappedValue = true
                        }
                    }
                }

                // Clear the residual status of the game in the process/state manager (to avoid invalid keys after deletion)
                GameProcessManager.shared.removeGameState(gameId: game.id)
                GameStatusManager.shared.removeGameState(gameId: game.id)

                // Delete the game folder first (if it does not exist, skip but continue deleting records)
                let profileDir = AppPaths.profileDirectory(gameName: game.gameName)
                if FileManager.default.fileExists(atPath: profileDir.path) {
                    try FileManager.default.removeItem(at: profileDir)
                } else {
                    Logger.shared.warning("删除游戏时未找到游戏目录，跳过文件删除: \(profileDir.path)")
                }

                // Clear all memory cache related to this game (icons, paths, mod scan results)
                GameIconCache.shared.invalidateCache(for: game.gameName)
                AppPaths.invalidatePaths(forGameName: game.gameName)
                await ModScanner.shared.clearModCache(for: game.gameName)

                // Delete game history
                try await gameRepository.deleteGame(id: game.id)

                Logger.shared.info("成功删除游戏: \(game.gameName)")
            } catch {
                let globalError = GlobalError.fileSystem(
                    chineseMessage: "删除游戏失败: \(error.localizedDescription)",
                    i18nKey: "Game Deletion Failed",
                    level: .notification
                )
                Logger.shared.error("删除游戏失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
            }
        }
    }
}
