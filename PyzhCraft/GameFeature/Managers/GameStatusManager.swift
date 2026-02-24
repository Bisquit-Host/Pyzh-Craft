import Foundation

/// game state manager
/// Manage the game running status based on the actual process status, using gameId as the key
class GameStatusManager: ObservableObject {
    static let shared = GameStatusManager()
    /// Game running status dictionary, key is gameId, value is whether it is running
    @Published private var gameRunningStates: [String: Bool] = [:]
    /// Game startup status dictionary, key is gameId, value is whether it is starting (not yet in running state)
    @Published private var gameLaunchingStates: [String: Bool] = [:]
    
    private init() {}
    
    /// Check if the specified game is running
    /// - Parameter gameId: game ID
    /// - Returns: Is it running?
    func isGameRunning(gameId: String) -> Bool {
        let actuallyRunning = GameProcessManager.shared.isGameRunning(gameId: gameId)
        
        DispatchQueue.main.async {
            self.updateGameStatusIfNeeded(gameId: gameId, actuallyRunning: actuallyRunning)
        }
        
        return actuallyRunning
    }
    /// Update game status (if needed)
    /// - Parameters:
    ///   - gameId: game ID
    ///   - actuallyRunning: actual running status
    private func updateGameStatusIfNeeded(gameId: String, actuallyRunning: Bool) {
        if let cachedState = gameRunningStates[gameId], cachedState != actuallyRunning {
            gameRunningStates[gameId] = actuallyRunning
            Logger.shared.debug("Synchronous update of game status: \(gameId) -> \(actuallyRunning ? "running" : "stopped")")
        } else if gameRunningStates[gameId] == nil {
            gameRunningStates[gameId] = actuallyRunning
        }
    }
    
    /// Force refresh the status of the specified game
    /// - Parameter gameId: game ID
    func refreshGameStatus(gameId: String) {
        let actuallyRunning = GameProcessManager.shared.isGameRunning(gameId: gameId)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.gameRunningStates[gameId] = actuallyRunning
            Logger.shared.debug("Force refresh of game state: \(gameId) -> \(actuallyRunning ? "running" : "stopped")")
        }
    }
    
    /// - Parameters:
    ///   - gameId: game ID
    ///   - isRunning: whether it is running
    func setGameRunning(gameId: String, isRunning: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let currentState = self.gameRunningStates[gameId]
            if currentState != isRunning {
                self.gameRunningStates[gameId] = isRunning
                Logger.shared.debug("Game status update: \(gameId) -> \(isRunning ? "running" : "stopped")")
            }
        }
    }
    
    /// Clean up stopped game state
    func cleanupStoppedGames() {
        let processManager = GameProcessManager.shared
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.gameRunningStates = self.gameRunningStates.filter { gameId, _ in
                processManager.isGameRunning(gameId: gameId)
            }
        }
    }
    
    /// Get all running game IDs
    var runningGameIds: [String] {
        return gameRunningStates.compactMap { gameId, isRunning in
            isRunning ? gameId : nil
        }
    }
    
    /// Get all game status
    var allGameStates: [String: Bool] {
        gameRunningStates
    }
    
    // MARK: - Startup status management
    
    /// - Parameters:
    ///   - gameId: game ID
    ///   - isLaunching: whether it is launching
    func setGameLaunching(gameId: String, isLaunching: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let currentState = self.gameLaunchingStates[gameId] ?? false
            if currentState != isLaunching {
                self.gameLaunchingStates[gameId] = isLaunching
                Logger.shared.debug("Game startup status update: \(gameId) -> \(isLaunching ? "launching" : "not launching")")
            }
        }
    }
    
    /// - Parameter gameId: game ID
    /// - Returns: Whether it is starting
    func isGameLaunching(gameId: String) -> Bool {
        gameLaunchingStates[gameId] ?? false
    }
    
    /// - Parameter gameId: game ID
    func removeGameState(gameId: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.gameRunningStates.removeValue(forKey: gameId)
            self.gameLaunchingStates.removeValue(forKey: gameId)
        }
    }
}
