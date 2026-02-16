import SwiftUI

/// Game log collector
/// Collect crash logs and send to AI window
@MainActor
class GameLogCollector {
    static let shared = GameLogCollector()

    private init() {}

    /// Collect game logs and open the AI ​​window
    /// - Parameters:
    ///   - gameName: game name
    ///   - playerListViewModel: player list view model
    ///   - gameRepository: game repository
    func collectAndOpenAIWindow(
        gameName: String,
        playerListViewModel: PlayerListViewModel,
        gameRepository: GameRepository
    ) async {
        // Collect log files
        let logFiles = await collectLogFiles(gameName: gameName)

        if logFiles.isEmpty {
            // Log file not found
            let error = GlobalError.fileSystem(i18nKey: "Game Log Files Not Found",
                level: .notification
            )
            GlobalErrorHandler.shared.handle(error)
            return
        }

        // Open AI window and send logs
        await openAIWindowWithLogs(
            logFiles: logFiles,
            gameName: gameName,
            playerListViewModel: playerListViewModel,
            gameRepository: gameRepository
        )
    }

    /// Collect log files
    /// - Parameter gameName: game name
    /// - Returns: Log file URL array
    private func collectLogFiles(gameName: String) async -> [URL] {
        let gameDirectory = AppPaths.profileDirectory(gameName: gameName)
        let fileManager = FileManager.default

        // 1. Prioritize collecting all files in the crash report folder
        let crashReportsDir = gameDirectory.appendingPathComponent(AppConstants.DirectoryNames.crashReports, isDirectory: true)

        if fileManager.fileExists(atPath: crashReportsDir.path) {
            do {
                let crashFiles = try fileManager
                    .contentsOfDirectory(
                        at: crashReportsDir,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    )
                    .filter { url in
                        guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
                            return false
                        }
                        return resourceValues.isRegularFile ?? false
                    }

                if !crashFiles.isEmpty {
                    Logger.shared.info("找到 \(crashFiles.count) 个崩溃报告文件")
                    return crashFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
                }
            } catch {
                Logger.shared.warning("读取崩溃报告文件夹失败: \(error.localizedDescription)")
            }
        }

        // 2. If there is no crash report, collect logs/latest.log
        let logsDir = gameDirectory.appendingPathComponent("logs", isDirectory: true)
        let latestLog = logsDir.appendingPathComponent("latest.log")

        if fileManager.fileExists(atPath: latestLog.path) {
            Logger.shared.info("找到 latest.log 文件")
            return [latestLog]
        }

        Logger.shared.warning("未找到崩溃报告和 latest.log 文件")
        return []
    }

    /// Open AI window and send logs
    /// - Parameters:
    ///   - logFiles: array of log file URLs
    ///   - gameName: game name
    ///   - playerListViewModel: player list view model
    ///   - gameRepository: game repository
    private func openAIWindowWithLogs(
        logFiles: [URL],
        gameName: String,
        playerListViewModel: PlayerListViewModel,
        gameRepository: GameRepository
    ) async {
        // Create ChatState
        let chatState = ChatState()

        // Prepare attachments
        var attachments: [MessageAttachmentType] = []
        for logFile in logFiles {
            attachments.append(.file(logFile, logFile.lastPathComponent))
        }

        // Store to WindowDataStore
        WindowDataStore.shared.aiChatState = chatState
        // open window
        WindowManager.shared.openWindow(id: .aiChat)

        // Wait for the window to open before sending the message
        try? await Task.sleep(nanoseconds: 100_000_000) // Wait 0.1 seconds

        // Send messages and attachments
        await AIChatManager.shared.sendMessage("", attachments: attachments, chatState: chatState)
    }
}
