import SwiftUI

/// Game right-click menu component to optimize memory usage
/// Use independent view components and cached state to reduce memory usage
struct GameContextMenu: View {
    let game: GameVersionInfo
    let onDelete: () -> Void
    let onOpenServerSettings: () -> Void
    let onExport: () -> Void

    @ObservedObject private var gameStatusManager = GameStatusManager.shared
    @ObservedObject private var gameActionManager = GameActionManager.shared
    @ObservedObject private var selectedGameManager = SelectedGameManager.shared
    @EnvironmentObject private var playerListViewModel: PlayerListViewModel
    @EnvironmentObject private var gameRepository: GameRepository
    @EnvironmentObject private var gameLaunchUseCase: GameLaunchUseCase

    private var isRunning: Bool {
        gameStatusManager.allGameStates[game.id] ?? false
    }

    var body: some View {
        Button(
            isRunning ? "Stop" : "Start",
            systemImage: isRunning ? "stop.fill" : "play.fill",
            action: toggleGameState
        )

        Button("Show in Finder", systemImage: "folder") {
            gameActionManager.showInFinder(game: game)
        }

        Button("Server Settings", systemImage: "server.rack") {
            selectedGameManager.setSelectedGame(game.id)
            onOpenServerSettings()
        }

        Divider()

        Button("Export", systemImage: "square.and.arrow.up", action: onExport)
        Button("Delete Game", systemImage: "trash", role: .destructive, action: onDelete)
    }

    private func toggleGameState() {
        Task {
            let currentlyRunning = gameStatusManager.allGameStates[game.id] ?? false

            if currentlyRunning {
                await gameLaunchUseCase.stopGame(game: game)
            } else {
                gameStatusManager.setGameLaunching(gameId: game.id, isLaunching: true)
                defer { gameStatusManager.setGameLaunching(gameId: game.id, isLaunching: false) }
                await gameLaunchUseCase.launchGame(
                    player: playerListViewModel.currentPlayer,
                    game: game
                )
            }
        }
    }
}
