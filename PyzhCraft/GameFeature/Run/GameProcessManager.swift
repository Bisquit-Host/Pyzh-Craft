import Foundation

/// game process manager
final class GameProcessManager: ObservableObject, @unchecked Sendable {
    static let shared = GameProcessManager()
    
    private var gameProcesses: [String: Process] = [:]
    
    // Mark actively stopped games to distinguish between user-initiated shutdowns and real crashes
    private var manuallyStoppedGames: Set<String> = []
    private let queue = DispatchQueue(label: "com.pyzhcraft.gameprocessmanager")
    
    private init() {}
    
    func storeProcess(gameId: String, process: Process) {
        // Set process termination handler (set before startup)
        // Not executed on the main thread: database and file scanning are placed in the background, and only the UI status is updated back to the main thread
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleProcessTermination(gameId: gameId, userId: userId, process: process)
            }
        }
        
        queue.async { [weak self] in
            self?.gameProcesses[key] = process
        }
        
        Logger.shared.debug("Store game process: \(gameId)")
    }
    
    // Unified processing of all cleaning logic
    private func handleProcessTermination(gameId: String, process: Process) async {
        let wasManuallyStopped = queue.sync { manuallyStoppedGames.contains(gameId) }
        
        handleProcessExit(gameId: gameId, wasManuallyStopped: wasManuallyStopped)
        
        if !wasManuallyStopped {
            let isCrash = await checkIfCrash(gameId: gameId, process: process)
            
            if isCrash {
                let gameSettings = GameSettingsManager.shared
                if gameSettings.enableAICrashAnalysis {
                    Logger.shared.info("Game crash detected, AI analysis enabled: \(gameId)")
                    await collectLogsForGameImmediately(gameId: gameId)
                }
            } else {
                Logger.shared.debug("The game exits normally without triggering AI analysis: \(gameId)")
            }
        }
        
        await MainActor.run {
            GameStatusManager.shared.setGameRunning(gameId: gameId, userId: userId, isRunning: false)
        }
        queue.async { [weak self] in
            self?.gameProcesses.removeValue(forKey: key)
            self?.manuallyStoppedGames.remove(key)
        }
    }
    
    private func checkIfCrash(gameId: String, process: Process) async -> Bool {
        // 1. Check the exit code: normal exit is usually 0, crash is usually non-0
        // The exit code of a process stopped by terminate() may be 15, which has been excluded by wasManuallyStopped
        let exitCode = process.terminationStatus
        if exitCode == 0 {
            // The exit code is 0, which may be a normal exit, but you also need to check whether there is a crash report
            Logger.shared.debug("The game exit code is 0: \(gameId)")
        } else {
            // If the exit code is non-0, it is likely a crash
            Logger.shared.info("The game exit code is non-0 (\(exitCode)), it may crash: \(gameId)")
            return true
        }
        
        // 2. Check whether a crash report file is generated (more accurate judgment)
        // Query game information from database to get game name
        let dbPath = AppPaths.gameVersionDatabase.path
        let database = GameVersionDatabase(dbPath: dbPath)
        
        do {
            try? database.initialize()
            guard let game = try database.getGame(by: gameId) else {
                Logger.shared.warning("Unable to find game from database, unable to check crash report: \(gameId)")
                // If game information cannot be queried and the exit code is non-0, it is considered a crash
                return exitCode != 0
            }
            
            // Check the crash report folder
            let gameDirectory = AppPaths.profileDirectory(gameName: game.gameName)
            let crashReportsDir = gameDirectory.appendingPathComponent(AppConstants.DirectoryNames.crashReports, isDirectory: true)
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: crashReportsDir.path) {
                do {
                    let crashFiles = try fileManager
                        .contentsOfDirectory(
                            at: crashReportsDir,
                            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey],
                            options: [.skipsHiddenFiles]
                        )
                        .filter { url in
                            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
                                return false
                            }
                            return resourceValues.isRegularFile ?? false
                        }
                    
                    // Check if there are any recently generated crash reports (within the last 5 minutes)
                    let now = Date()
                    let fiveMinutesAgo = now.addingTimeInterval(-300)
                    
                    for crashFile in crashFiles {
                        if let creationDate = try? crashFile.resourceValues(forKeys: [.creationDateKey]).creationDate,
                           creationDate >= fiveMinutesAgo {
                            Logger.shared.info("Find the most recently generated crash report: \(crashFile.lastPathComponent)")
                            return true
                        }
                    }
                    
                    // If the exit code is 0 but there is no recent crash report, it is considered a normal exit
                    // (The case of non-0 exit code has been dealt with above)
                } catch {
                    Logger.shared.warning("Failed to read crash report folder: \(error.localizedDescription)")
                }
            }
            
            // If the exit code is 0 and no crash is reported, it is considered a normal exit
            return false
        } catch {
            Logger.shared.error("Querying game from database failed: \(error.localizedDescription)")
            // If it cannot be queried and the exit code is non-0, it is considered a crash
            return exitCode != 0
        }
    }
    
    /// Collect logs for the game (can be used for process-based crash detection)
    /// - Parameter gameId: Game ID
    func collectLogsForGameImmediately(gameId: String) async {
        // Query game information from SQL database
        let dbPath = AppPaths.gameVersionDatabase.path
        let database = GameVersionDatabase(dbPath: dbPath)
        
        do {
            // Initialize the database (if it has not been initialized, it may fail, you can continue to try to query)
            try? database.initialize()
            
            // Query games from database
            guard let game = try database.getGame(by: gameId) else {
                Logger.shared.warning("Unable to find game from database: \(gameId)")
                return
            }
            
            // Create temporary view models and warehouse instances for AI windows
            let playerListViewModel = PlayerListViewModel()
            let gameRepository = GameRepository()
            
            await GameLogCollector.shared.collectAndOpenAIWindow(
                gameName: game.gameName,
                playerListViewModel: playerListViewModel,
                gameRepository: gameRepository
            )
        } catch {
            Logger.shared.error("Querying game from database failed: \(error.localizedDescription)")
        }
    }
    
    /// Handling process exit situations
    private func handleProcessExit(gameId: String, wasManuallyStopped: Bool) {
        if wasManuallyStopped {
            Logger.shared.debug("The game was actively stopped by the user: \(gameId)")
        } else {
            Logger.shared.info("Game process has exited: \(gameId)")
        }
    }
    
    /// Get game progress
    /// - Parameter gameId: Game ID
    /// - Returns: process object, returns nil if it does not exist
    func getProcess(for gameId: String) -> Process? {
        queue.sync { gameProcesses[gameId] }
    }
    
    /// Stop the game process (not waiting for the process to exit on the main thread to avoid stuck UI)
    /// - Parameter gameId: Game ID
    /// - Returns: Whether the stop was initiated successfully
    func stopProcess(for gameId: String) -> Bool {
        let process: Process? = queue.sync {
            guard let proc = gameProcesses[key] else { return nil }
            manuallyStoppedGames.insert(key)
            return proc
        }
        guard let process = process else { return false }
        
        if process.isRunning {
            process.terminate()
            // Wait for exit in the background to avoid the main thread calling waitUntilExit() and blocking the UI
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
            }
        }
        
        Logger.shared.debug("Stop game process: \(gameId)")
        return true
    }
    
    /// Check if the game is running
    /// - Parameter gameId: Game ID
    /// - Returns: Is it running?
    func isGameRunning(gameId: String) -> Bool {
        queue.sync { gameProcesses[gameId]?.isRunning ?? false }
    }
    
    // Clean up processes that did not trigger terminationHandler correctly
    func cleanupTerminatedProcesses() {
        let terminatedKeys: [String] = queue.sync {
            let keys = gameProcesses.compactMap { key, process in
                !process.isRunning ? key : nil
            }
            guard !keys.isEmpty else { return [] }
            for key in keys {
                gameProcesses.removeValue(forKey: key)
                manuallyStoppedGames.remove(key)
            }
            return keys
        }
        
        guard !terminatedGameIds.isEmpty else { return }
        
        for gameId in terminatedGameIds {
            Logger.shared.debug("Clean up terminated processes: \(gameId)")
        }
        
        Task { @MainActor in
            for key in terminatedKeys {
                // key 格式为 "gameId_userId"
                if let idx = key.firstIndex(of: "_") {
                    let gameId = String(key[..<idx])
                    let userId = String(key[key.index(after: idx)...])
                    GameStatusManager.shared.setGameRunning(gameId: gameId, userId: userId, isRunning: false)
                }
            }
        }
    }
    
    /// Check whether the game was actively stopped
    /// - Parameter gameId: Game ID
    /// - Returns: Whether it was stopped actively
    func isManuallyStopped(gameId: String) -> Bool {
        queue.sync { manuallyStoppedGames.contains(gameId) }
    }
    
    /// Remove the process and status of the specified game (called when deleting the game)
    /// If the game is running, the process will be terminated first, wait in the background for exit, and then be removed from the memory without blocking the calling thread
    /// - Parameter gameId: Game ID
    func removeGameState(gameId: String) {
        let prefix = "\(gameId)_"
        let toRemove: [(String, Process)] = queue.sync {
            let pairs = gameProcesses.filter { key, _ in key.hasPrefix(prefix) }
            for (key, proc) in pairs {
                gameProcesses.removeValue(forKey: key)
                if proc.isRunning {
                    manuallyStoppedGames.insert(key)
                }
            }
            return pairs.map { ($0.key, $0.value) }
        }
        
        if let process = process, process.isRunning {
            process.terminate()
            
            DispatchQueue.global(qos: .utility).async { [weak self] in
                process.waitUntilExit()
                self?.queue.async {
                    self?.gameProcesses.removeValue(forKey: key)
                    self?.manuallyStoppedGames.remove(key)
                }
            }
        }

        Task { @MainActor in
            for (key, process) in toRemove where !process.isRunning {
                if let idx = key.firstIndex(of: "_") {
                    let gameId = String(key[..<idx])
                    let userId = String(key[key.index(after: idx)...])
                    GameStatusManager.shared.setGameRunning(gameId: gameId, userId: userId, isRunning: false)
                }
            }
        }
    }
}
