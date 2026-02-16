import SwiftUI

/// Launcher import ViewModel
@MainActor
class LauncherImportViewModel: BaseGameFormViewModel {

    // MARK: - Published Properties

    @Published var selectedLauncherType: ImportLauncherType = .multiMC
    @Published var selectedInstancePath: URL?  // Directly selected instance path (all launchers use this method)
    @Published var isImporting = false {
        didSet {
            updateParentState()
        }
    }
    @Published var importProgress: (fileName: String, completed: Int, total: Int)?

    // MARK: - Private Properties

    private var gameRepository: GameRepository?
    private var playerListViewModel: PlayerListViewModel?
    private var copyTask: Task<Void, Error>?

    // MARK: - Initialization

    override init(configuration: GameFormConfiguration) {
        super.init(configuration: configuration)
    }

    // MARK: - Setup Methods

    func setup(gameRepository: GameRepository, playerListViewModel: PlayerListViewModel) {
        self.gameRepository = gameRepository
        self.playerListViewModel = playerListViewModel
        updateParentState()
    }

    // MARK: - Cleanup Methods

    /// Clean cache and state (called when sheet is closed)
    func cleanup() {
        // Cancel an ongoing task
        copyTask?.cancel()
        copyTask = nil
        downloadTask?.cancel()
        downloadTask = nil

        // reset state
        selectedInstancePath = nil
        importProgress = nil
        isImporting = false
        selectedLauncherType = .multiMC

        // Clean up the game name (optional, decide whether to keep it based on your needs)
        // gameNameValidator.gameName = ""

        // Reset download status
        gameSetupService.downloadState.reset()

        // Clean up references
        gameRepository = nil
        playerListViewModel = nil
    }

    // MARK: - Override Methods

    override func performConfirmAction() async {
        // All launchers use selectedInstancePath directly
        if let instancePath = selectedInstancePath {
            startDownloadTask {
                await self.importSelectedInstancePath(instancePath)
            }
        }
    }

    override func handleCancel() {
        if isDownloading || isImporting {
            // Cancel copy task
            copyTask?.cancel()
            copyTask = nil
            // Cancel download task
            downloadTask?.cancel()
            downloadTask = nil
            gameSetupService.downloadState.cancel()
            Task {
                await performCancelCleanup()
            }
        } else {
            configuration.actions.onCancel()
        }
    }

    override func performCancelCleanup() async {
        // Clean created game folders
        if let instancePath = selectedInstancePath {
            // Infer launcher base path from instance path
            let basePath = inferBasePath(from: instancePath)

            let parser = LauncherInstanceParserFactory.createParser(for: selectedLauncherType)
            if let info = try? parser.parseInstance(at: instancePath, basePath: basePath) {
                do {
                    let fileManager = MinecraftFileManager()
                    // Use the game name entered by the user if available, otherwise use the instance's game name
                    let gameName = gameNameValidator.gameName.isEmpty
                        ? info.gameName
                        : gameNameValidator.gameName
                    try fileManager.cleanupGameDirectories(gameName: gameName)
                } catch {
                    Logger.shared.error("清理游戏文件夹失败: \(error.localizedDescription)")
                }
            }
        }

        await MainActor.run {
            isImporting = false
            importProgress = nil
            gameSetupService.downloadState.reset()
            configuration.actions.onCancel()
        }
    }

    override func computeIsDownloading() -> Bool {
        gameSetupService.downloadState.isDownloading || isImporting
    }

    override func computeIsFormValid() -> Bool {
        // All launchers check selectedInstancePath
        guard selectedInstancePath != nil && gameNameValidator.isFormValid else {
            return false
        }

        // Check if Mod Loader supports
        return isModLoaderSupported
    }

    // MARK: - Instance Validation

    /// Automatically fill the game name into the input box (if the input box is empty)
    func autoFillGameNameIfNeeded() {
        guard let instancePath = selectedInstancePath else { return }

        // If the game name has been filled in, it will not be filled in automatically
        guard gameNameValidator.gameName.isEmpty else { return }

        // Infer launcher base path from instance path
        let basePath = inferBasePath(from: instancePath)
        let parser = LauncherInstanceParserFactory.createParser(for: selectedLauncherType)

        // Parse instance information and populate game name
        if let info = try? parser.parseInstance(at: instancePath, basePath: basePath) {
            gameNameValidator.gameName = info.gameName
        }
    }

    /// Check if Mod Loader supports it and display notification if not
    func checkAndNotifyUnsupportedModLoader() {
        guard let info = currentInstanceInfo else { return }

        // Check if Mod Loader supports
        guard !AppConstants.modLoaders.contains(info.modLoader.lowercased()) else { return }

        // If not supported, show notification
        let supportedModLoadersList = AppConstants.modLoaders.joined(separator: "、")
        let instanceName = selectedInstancePath?.lastPathComponent ?? "Unknown"
        let chineseMessage = "实例 \(instanceName) 使用了不支持的 Mod Loader (\(info.modLoader))，仅支持 \(supportedModLoadersList)"

        GlobalErrorHandler.shared.handle(
            GlobalError.fileSystem(
                i18nKey: "Unsupported Mod Loader",
                level: .notification
            )
        )
    }

    /// Verify that the selected instance folder is valid
    /// All launchers require direct selection of the instance folder
    func validateInstance(at instancePath: URL) -> Bool {
        let parser = LauncherInstanceParserFactory.createParser(for: selectedLauncherType)
        let fileManager = FileManager.default

        // Check if the path exists and is a directory
        guard fileManager.fileExists(atPath: instancePath.path) else {
            return false
        }

        let resourceValues = try? instancePath.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues?.isDirectory == true else {
            return false
        }

        // Verify if it is a valid instance
        return parser.isValidInstance(at: instancePath)
    }

    // MARK: - Import Methods

    /// Import instance directly from path (all launchers use this method)
    private func importSelectedInstancePath(_ instancePath: URL) async {
        guard let gameRepository = gameRepository else { return }

        isImporting = true
        defer { isImporting = false }

        let instanceName = instancePath.lastPathComponent

        // Infer launcher base path from instance path
        let basePath = inferBasePath(from: instancePath)

        let parser = LauncherInstanceParserFactory.createParser(for: selectedLauncherType)

        // Parse instance information
        let instanceInfo: ImportInstanceInfo
        do {
            guard let parsedInfo = try parser.parseInstance(at: instancePath, basePath: basePath) else {
                Logger.shared.error("解析实例失败: \(instanceName) - 返回 nil")
                GlobalErrorHandler.shared.handle(
                    GlobalError.fileSystem(
                        i18nKey: "Parse Instance Failed",
                        level: .notification
                    )
                )
                return
            }
            instanceInfo = parsedInfo
        } catch {
            Logger.shared.error("解析实例失败: \(instanceName) - \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(
                GlobalError.fileSystem(
                    i18nKey: "Parse Instance Failed",
                    level: .notification
                )
            )
            return
        }

        // The verification instance must have a version
        guard !instanceInfo.gameVersion.isEmpty else {
            Logger.shared.error("实例 \(instanceName) 没有游戏版本")
            GlobalErrorHandler.shared.handle(
                GlobalError.fileSystem(
                    i18nKey: "Instance Has No Version",
                    level: .notification
                )
            )
            return
        }

        // Verified Mod Loader support, error shown, only logged here
        guard AppConstants.modLoaders.contains(instanceInfo.modLoader.lowercased()) else {
            Logger.shared.error("实例 \(instanceName) 使用了不支持的 Mod Loader: \(instanceInfo.modLoader)")
            return
        }

        // Generate game name (if not customized by user)
        let finalGameName = gameNameValidator.gameName.isEmpty
            ? instanceInfo.gameName
            : gameNameValidator.gameName

        // 1. Copy the game directory first (keep mods, config and other files)
        let targetDirectory = AppPaths.profileDirectory(gameName: finalGameName)

        do {
            // Create a replication task so it can be canceled
            copyTask = Task {
                try await InstanceFileCopier.copyGameDirectory(
                    from: instanceInfo.sourceGameDirectory,
                    to: targetDirectory,
                    launcherType: instanceInfo.launcherType
                ) { fileName, completed, total in
                    Task { @MainActor in
                        self.importProgress = (fileName, completed, total)
                    }
                }
            }

            try await copyTask?.value
            copyTask = nil

            Logger.shared.info("成功复制游戏目录: \(instanceName) -> \(finalGameName)")
        } catch is CancellationError {
            Logger.shared.info("复制游戏目录已取消: \(instanceName)")
            copyTask = nil
            // Clean copied files
            await performCancelCleanup()
            return
        } catch {
            Logger.shared.error("复制游戏目录失败: \(error.localizedDescription)")
            copyTask = nil
            GlobalErrorHandler.shared.handle(
                GlobalError.fileSystem(
                    i18nKey: "Copy Game Directory Failed",
                    level: .notification
                )
            )
            return
        }

        // 2. Download the game and Mod Loader (only download the missing ones, do not overwrite existing ones)
        let downloadSuccess = await withCheckedContinuation { continuation in
            Task {
                await gameSetupService.saveGame(
                    gameName: finalGameName,
                    gameIcon: AppConstants.defaultGameIcon,
                    selectedGameVersion: instanceInfo.gameVersion,
                    selectedModLoader: instanceInfo.modLoader,
                    specifiedLoaderVersion: instanceInfo.modLoaderVersion,
                    pendingIconData: nil,  // Icons are not imported when importing from launcher
                    playerListViewModel: playerListViewModel,
                    gameRepository: gameRepository,
                    onSuccess: {
                        continuation.resume(returning: true)
                    },
                    onError: { error, message in
                        Logger.shared.error("游戏下载失败: \(message)")
                        GlobalErrorHandler.shared.handle(error)
                        continuation.resume(returning: false)
                    }
                )
            }
        }

        if !downloadSuccess {
            Logger.shared.error("导入实例失败: \(instanceName)")
            return
        }

        Logger.shared.info("成功导入实例: \(instanceName) -> \(finalGameName)")

        // Import completed
        await MainActor.run {
            gameSetupService.downloadState.reset()
            configuration.actions.onCancel()
        }
    }

    // MARK: - Helper Methods

    /// Infer launcher base path from instance path
    /// Looks up for the directory containing the icons folder, using the parent directory of the instance path's parent directory if not found
    private func inferBasePath(from instancePath: URL) -> URL {
        let fileManager = FileManager.default
        var currentPath = instancePath

        // Search upward, up to 5 levels
        for _ in 0..<5 {
            let iconsPath = currentPath.appendingPathComponent("icons")
            
            if fileManager.fileExists(atPath: iconsPath.path) {
                return currentPath
            }
            
            let parentPath = currentPath.deletingLastPathComponent()
            
            if parentPath.path == currentPath.path {
                // Root directory has been reached
                break
            }
            
            currentPath = parentPath
        }

        // If the icons folder is not found, use the parent directory of the instance path as a fallback
        return instancePath.deletingLastPathComponent().deletingLastPathComponent()
    }

    /// download icon
    private func downloadIcon(from urlString: String, instanceName: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            // cache icon
            let cacheDir = AppPaths.appCache.appendingPathComponent("imported_icons")
            try FileManager.default.createDirectory(
                at: cacheDir,
                withIntermediateDirectories: true
            )
            let cachedPath = cacheDir.appendingPathComponent("\(instanceName).png")
            try data.write(to: cachedPath)

            return data
        } catch {
            Logger.shared.warning("下载图标失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Computed Properties

    var shouldShowProgress: Bool {
        gameSetupService.downloadState.isDownloading || isImporting
    }

    var hasSelectedInstance: Bool {
        selectedInstancePath != nil
    }

    /// Get information about the currently selected instance
    var currentInstanceInfo: ImportInstanceInfo? {
        guard let instancePath = selectedInstancePath else { return nil }

        // Infer launcher base path from instance path
        let basePath = inferBasePath(from: instancePath)

        let parser = LauncherInstanceParserFactory.createParser(for: selectedLauncherType)
        do {
            if let info = try parser.parseInstance(at: instancePath, basePath: basePath) {
                // Verification must have a version (only records logs, does not display errors, errors will be displayed during import)
                guard !info.gameVersion.isEmpty else {
                    Logger.shared.warning("选中的实例没有游戏版本")
                    return nil
                }

                return info
            } else {
                Logger.shared.warning("解析实例返回 nil")
                return nil
            }
        } catch {
            Logger.shared.error("解析实例失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// Checks whether the currently selected instance uses a supported Mod Loader
    var isModLoaderSupported: Bool {
        guard let info = currentInstanceInfo else { return false }
        return AppConstants.modLoaders.contains(info.modLoader.lowercased())
    }
}
