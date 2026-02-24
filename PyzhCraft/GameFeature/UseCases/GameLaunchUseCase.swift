import Foundation

/// Game start/stop use case
/// Decouple UI and Run module: View only depends on this UseCase and does not directly depend on MinecraftLaunchCommand
final class GameLaunchUseCase: ObservableObject {
    
    /// Start the game
    /// - Parameters:
    ///   - player: current player (can be nil, use default authentication parameters)
    ///   - game: the game to start
    func launchGame(player: Player?, game: GameVersionInfo) async {
        let command = MinecraftLaunchCommand(player: player, game: game)
        await command.launchGame()
    }
    
    /// stop game
    /// - Parameter game: The game to stop
    func stopGame(game: GameVersionInfo) async {
        let command = MinecraftLaunchCommand(player: nil, game: game)
        await command.stopGame()
    }
}
