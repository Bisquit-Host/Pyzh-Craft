import Foundation
import AVFoundation

/// Minecraft launch command generator (only responsible for process and authentication, exposed by GameLaunchUseCase)
struct MinecraftLaunchCommand {
    let player: Player?
    let game: GameVersionInfo

    /// Start the game (silent version)
    func launchGame() async {
        do {
            try await launchGameThrowing()
        } catch {
            await handleLaunchError(error)
        }
    }

    /// stop game
    func stopGame() async {
        // Stop the process, terminationHandler will automatically handle error monitoring stop and status update
        _ = GameProcessManager.shared.stopProcess(for: game.id)
    }

    /// Start the game (throws exception version)
    /// - Throws: GlobalError when startup fails
    func launchGameThrowing() async throws {
        // Verify and refresh token (if necessary) before launching the game
        let validatedPlayer = try await validatePlayerTokenBeforeLaunch()

        let command = game.launchCommand
        try await launchGameProcess(command: replaceAuthParameters(command: command, with: validatedPlayer))
    }

    /// Verify player token before launching the game
    /// - Returns: Verified player object
    /// - Throws: GlobalError when validation fails
    private func validatePlayerTokenBeforeLaunch() async throws -> Player? {
        guard let player = player else {
            Logger.shared.warning("没有选择玩家，使用默认认证参数")
            return nil
        }

        // If it is an offline account, return directly
        guard player.isOnlineAccount else {
            return player
        }

        Logger.shared.info("启动游戏前验证玩家 \(player.name) 的Token")

        // Load authentication credentials from Keychain for this player on demand before starting (only for the current player to avoid reading all accounts at once)
        var playerWithCredential = player
        if playerWithCredential.credential == nil {
            let dataManager = PlayerDataManager()
            if let credential = dataManager.loadCredential(userId: playerWithCredential.id) {
                playerWithCredential.credential = credential
            }
        }

        // Verify using the loaded/updated player object and try to refresh the token
        let authService = MinecraftAuthService.shared
        let validatedPlayer = try await authService.validateAndRefreshPlayerTokenThrowing(for: playerWithCredential)

        // If the Token is updated, it needs to be saved to PlayerDataManager
        if validatedPlayer.authAccessToken != player.authAccessToken {
            Logger.shared.info("玩家 \(player.name) 的Token已更新，保存到数据管理器")
            await updatePlayerInDataManager(validatedPlayer)
        }

        return validatedPlayer
    }

    /// Update player information in PlayerDataManager
    /// - Parameter updatedPlayer: updated player object
    private func updatePlayerInDataManager(_ updatedPlayer: Player) async {
        let dataManager = PlayerDataManager()
        let success = dataManager.updatePlayerSilently(updatedPlayer)
        if success {
            Logger.shared.debug("已更新玩家数据管理器中的Token信息")
            // Synchronously update the player list in memory (to avoid using old tokens at next startup)
            NotificationCenter.default.post(
                name: PlayerSkinService.playerUpdatedNotification,
                object: nil,
                userInfo: ["updatedPlayer": updatedPlayer]
            )
        }
    }

    private func replaceAuthParameters(command: [String], with validatedPlayer: Player?) -> [String] {
        guard let player = validatedPlayer else {
            Logger.shared.warning("没有验证的玩家，使用默认认证参数")
            return replaceGameParameters(command: command)
        }

        // Use NSMutableString to avoid chaining calls that create multiple temporary strings
        let authReplacedCommand = command.map { arg -> String in
            let mutableArg = NSMutableString(string: arg)
            mutableArg.replaceOccurrences(
                of: "${auth_player_name}",
                with: player.name,
                options: [],
                range: NSRange(location: 0, length: mutableArg.length)
            )
            mutableArg.replaceOccurrences(
                of: "${auth_uuid}",
                with: player.id,
                options: [],
                range: NSRange(location: 0, length: mutableArg.length)
            )
            mutableArg.replaceOccurrences(
                of: "${auth_access_token}",
                with: player.authAccessToken,
                options: [],
                range: NSRange(location: 0, length: mutableArg.length)
            )
            mutableArg.replaceOccurrences(
                of: "${auth_xuid}",
                with: player.authXuid,
                options: [],
                range: NSRange(location: 0, length: mutableArg.length)
            )
            return mutableArg as String
        }

        return replaceGameParameters(command: authReplacedCommand)
    }

    private func replaceGameParameters(command: [String]) -> [String] {
        let settings = GameSettingsManager.shared

        // Memory settings: Prioritize the game configuration. If the game has no configuration, use the global configuration
        let xms = game.xms > 0 ? game.xms : settings.globalXms
        let xmx = game.xmx > 0 ? game.xmx : settings.globalXmx

        // Use NSMutableString to avoid chaining calls that create multiple temporary strings
        var replacedCommand = command.map { arg -> String in
            let mutableArg = NSMutableString(string: arg)
            let xmsString = "\(xms)"
            let xmxString = "\(xmx)"
            mutableArg.replaceOccurrences(
                of: "${xms}",
                with: xmsString,
                options: [],
                range: NSRange(location: 0, length: mutableArg.length)
            )
            mutableArg.replaceOccurrences(
                of: "${xmx}",
                with: xmxString,
                options: [],
                range: NSRange(location: 0, length: mutableArg.length)
            )
            return mutableArg as String
        }

        // Splice JVM parameters for advanced settings at runtime
        // Logic: If there are custom JVM parameters, use them directly, otherwise use garbage collector + performance optimization parameters
        if !game.jvmArguments.isEmpty {
            // Insert custom JVM parameters into the beginning of the command array (after the java command) and remove duplication to maintain order
            let advancedArgs = game.jvmArguments
                .components(separatedBy: " ")
                .filter { !$0.isEmpty }
            var seen = Set<String>()
            let uniqueAdvancedArgs = advancedArgs.filter { arg in
                if seen.contains(arg) { return false }
                seen.insert(arg)
                return true
            }
            replacedCommand.insert(contentsOf: uniqueAdvancedArgs, at: 0)
        }

        return replacedCommand
    }

    /// Start game process
    /// - Parameter command: startup command array
    /// - Throws: GlobalError when startup fails
    private func launchGameProcess(command: [String]) async throws {
        if game.modLoader != "vanilla" {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        // Directly use the Java path specified by the game
        let javaExecutable = game.javaPath
        guard !javaExecutable.isEmpty else {
            throw GlobalError.configuration(
                chineseMessage: "Java 路径未设置",
                i18nKey: "Java Path Not Set",
                level: .popup
            )
        }

        // Get the game working directory
        let gameWorkingDirectory = AppPaths.profileDirectory(gameName: game.gameName)

        Logger.shared.info("启动游戏进程: \(javaExecutable) \(command.joined(separator: " "))")
        Logger.shared.info("游戏工作目录: \(gameWorkingDirectory.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaExecutable)
        process.arguments = command
        process.currentDirectoryURL = gameWorkingDirectory

        // Set environment variables (advanced settings)
        if !game.environmentVariables.isEmpty {
            var env = ProcessInfo.processInfo.environment
            let envLines = game.environmentVariables.components(separatedBy: "\n")
            for line in envLines {
                if let equalIndex = line.firstIndex(of: "=") {
                    let key = String(line[..<equalIndex])
                    let value = String(line[line.index(after: equalIndex)...])
                    env[key] = value
                }
            }
            process.environment = env
        }

        // Store the process in the manager (will automatically set the termination handler)
        GameProcessManager.shared.storeProcess(gameId: game.id, process: process)

        do {
            try process.run()

            // Set the status to running immediately after the process starts
            _ = await MainActor.run {
                GameStatusManager.shared.setGameRunning(gameId: game.id, isRunning: true)
            }
        } catch {
            Logger.shared.error("启动进程失败: \(error.localizedDescription)")

            // Clean up process and reset state when startup fails
            _ = GameProcessManager.shared.stopProcess(for: game.id)
            _ = await MainActor.run {
                GameStatusManager.shared.setGameRunning(gameId: game.id, isRunning: false)
            }

            throw GlobalError.gameLaunch(
                chineseMessage: "启动游戏进程失败: \(error.localizedDescription)",
                i18nKey: "Process Failed",
                level: .popup
            )
        }
    }

    /// Handle startup errors
    /// - Parameter error: startup error
    private func handleLaunchError(_ error: Error) async {
        Logger.shared.error("启动游戏失败：\(error.localizedDescription)")

        // Handling errors using a global error handler
        let globalError = GlobalError.from(error)
        GlobalErrorHandler.shared.handle(globalError)
    }
}
