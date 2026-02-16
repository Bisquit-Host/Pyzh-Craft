import SwiftUI

/// Game setup service
/// Responsible for handling the complete process of game download, configuration and saving
@MainActor
class GameSetupUtil: ObservableObject {

    // MARK: - Properties
    @Published var downloadState = DownloadState()
    @Published var fabricDownloadState = DownloadState()
    @Published var forgeDownloadState = DownloadState()
    @Published var neoForgeDownloadState = DownloadState()

    private var downloadTask: Task<Void, Never>?

    // MARK: - Public Methods

    /// Internal game save method
    /// - Parameters:
    ///   - gameName: game name
    ///   - gameIcon: game icon
    ///   - selectedGameVersion: selected game version
    ///   - selectedModLoader: selected module loader
    ///   - specifiedLoaderVersion: specified loader version (optional)
    ///   - pendingIconData: icon data to be saved
    ///   - playerListViewModel: player list view model (optional, skip player verification when nil)
    ///   - gameRepository: game repository
    ///   - onSuccess: success callback
    ///   - onError: error callback
    func saveGame( // swiftlint:disable:this function_parameter_count
        gameName: String,
        gameIcon: String,
        selectedGameVersion: String,
        selectedModLoader: String,
        specifiedLoaderVersion: String,
        pendingIconData: Data?,
        playerListViewModel: PlayerListViewModel?,
        gameRepository: GameRepository,
        onSuccess: @escaping () -> Void,
        onError: @escaping (GlobalError, String) -> Void
    ) async {
        // Validate the current player (only if playerListViewModel is provided)
        if let playerListViewModel = playerListViewModel {
            guard playerListViewModel.currentPlayer != nil else {
                Logger.shared.error("无法保存游戏，因为没有选择当前玩家。")
                onError(
                    GlobalError.configuration(
                        i18nKey: "No Current Player",
                        level: .popup
                    ),
                    String(localized: "No Current Player Selected")
                )
                return
            }
        }

        // Set download status
        await MainActor.run {
            self.objectWillChange.send()
            downloadState.reset()
            downloadState.isDownloading = true
        }

        defer {
            Task { @MainActor in
                self.objectWillChange.send()
                downloadState.isDownloading = false
                downloadTask = nil
            }
        }

        // save game icon
        await saveGameIcon(
            gameName: gameName,
            pendingIconData: pendingIconData,
            onError: onError
        )

        // Create initial game information
        var gameInfo = GameVersionInfo(
            id: UUID(),
            gameName: gameName,
            gameIcon: gameIcon,
            gameVersion: selectedGameVersion,
            assetIndex: "",
            modLoader: selectedModLoader
        )

        do {
            // Download Mojang manifest
            let downloadedManifest = try await ModrinthService.fetchVersionInfo(from: selectedGameVersion)

            // Ensure and obtain the Java path to avoid repeated verification in the future
            let javaPath = await JavaManager.shared.ensureJavaExists(
                version: downloadedManifest.javaVersion.component
            )

            // Set up file manager
            let fileManager = try await setupFileManager(manifest: downloadedManifest, modLoader: gameInfo.modLoader)

            // Start download process
            try await startDownloadProcess(
                fileManager: fileManager,
                manifest: downloadedManifest,
                gameName: gameName
            )
            // Set up the mod loader
            let modLoaderResult = try await setupModLoaderIfNeeded(
                selectedModLoader: selectedModLoader,
                selectedGameVersion: selectedGameVersion,
                gameName: gameName,
                gameIcon: gameIcon,
                specifiedLoaderVersion: specifiedLoaderVersion
            )
            // Improve game information
            gameInfo = await finalizeGameInfo(
                gameInfo: gameInfo,
                manifest: downloadedManifest,
                selectedModLoader: selectedModLoader,
                selectedGameVersion: selectedGameVersion,
                specifiedLoaderVersion: specifiedLoaderVersion,
                fabricResult: selectedModLoader.lowercased() == "fabric" ? modLoaderResult : nil,
                forgeResult: selectedModLoader.lowercased() == "forge" ? modLoaderResult : nil,
                neoForgeResult: selectedModLoader.lowercased() == "neoforge" ? modLoaderResult : nil,
                quiltResult: selectedModLoader.lowercased() == "quilt" ? modLoaderResult : nil
            )
            // Use the result returned by ensureJavaExists to avoid triggering Java verification again
            gameInfo.javaPath = javaPath
            // Save game configuration

            gameRepository.addGameSilently(gameInfo)

            // Scan the game's mods directory (sync blocking)
            ModScanner.shared.scanGameModsDirectorySync(game: gameInfo)

            // Send notification
            NotificationManager.sendSilently(
                title: "Download Complete",
                body: String(format: String(localized: "\(gameInfo.gameName) (Version: \(gameInfo.gameVersion), Loader: \(gameInfo.modLoader)) has been successfully downloaded."))
            )
            onSuccess()
        } catch is CancellationError {
            Logger.shared.info("游戏下载任务已取消")
            // Clean created game folders
            await cleanupGameDirectories(gameName: gameName)
            await MainActor.run {
                self.objectWillChange.send()
                downloadState.reset()
            }
        } catch {
            // Clean created game folders
            await cleanupGameDirectories(gameName: gameName)
            GlobalErrorHandler.shared.handle(error)
        }
        return
    }

    // MARK: - Private Methods

    /// Clean game folder
    /// - Parameter gameName: game name
    private func cleanupGameDirectories(gameName: String) async {
        do {
            let fileManager = MinecraftFileManager()
            try fileManager.cleanupGameDirectories(gameName: gameName)
        } catch {
            Logger.shared.error("清理游戏文件夹失败: \(error.localizedDescription)")
            // No error is thrown because this is a cleanup operation and should not affect the main process
        }
    }

    private func saveGameIcon(
        gameName: String,
        pendingIconData: Data?,
        onError: @escaping (GlobalError, String) -> Void
    ) async {
        guard let data = pendingIconData, !gameName.isEmpty else {
            return
        }
        let profileDir = AppPaths.profileDirectory(gameName: gameName)
        let iconURL = profileDir.appendingPathComponent(AppConstants.defaultGameIcon)

        do {
            try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
            try data.write(to: iconURL)
        } catch {
            onError(
                GlobalError.fileSystem(
                    i18nKey: "Image Save Failed",
                    level: .notification
                ),
                String(localized: "Failed to Save Image")
            )
        }
    }

    private func setupFileManager(manifest: MinecraftVersionManifest, modLoader: String) async throws -> MinecraftFileManager {
        let nativesDir = AppPaths.nativesDirectory
        try FileManager.default.createDirectory(at: nativesDir, withIntermediateDirectories: true)
        return MinecraftFileManager()
    }

    private func startDownloadProcess(
        fileManager: MinecraftFileManager,
        manifest: MinecraftVersionManifest,
        gameName: String
    ) async throws {
        // First download the resource index to get the total number of resource files
        let assetIndex = try await downloadAssetIndex(manifest: manifest)
        let resourceTotalFiles = assetIndex.objects.count

        downloadState.startDownload(
            coreTotalFiles: 1 + manifest.libraries.count + 1,
            resourcesTotalFiles: resourceTotalFiles
        )

        fileManager.onProgressUpdate = { fileName, completed, total, type in
            Task { @MainActor in
                self.objectWillChange.send()
                self.downloadState.updateProgress(fileName: fileName, completed: completed, total: total, type: type)
            }
        }

        // Use a silent version of the API to avoid throwing exceptions
        let success = await fileManager.downloadVersionFiles(manifest: manifest, gameName: gameName)
        if !success {
            throw GlobalError.download(
                i18nKey: "Minecraft Version Failed",
                level: .notification
            )
        }
    }

    private func downloadAssetIndex(manifest: MinecraftVersionManifest) async throws -> DownloadedAssetIndex {

        let destinationURL = AppPaths.metaDirectory.appendingPathComponent("assets/indexes").appendingPathComponent("\(manifest.assetIndex.id).json")

        do {
            _ = try await DownloadManager.downloadFile(urlString: manifest.assetIndex.url.absoluteString, destinationURL: destinationURL, expectedSha1: manifest.assetIndex.sha1)
            let assetIndexData = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: destinationURL)
                return try JSONDecoder().decode(AssetIndexData.self, from: data)
            }.value
            var totalSize = 0
            for object in assetIndexData.objects.values {
                totalSize += object.size
            }
            return DownloadedAssetIndex(
                id: manifest.assetIndex.id,
                url: manifest.assetIndex.url,
                sha1: manifest.assetIndex.sha1,
                totalSize: totalSize,
                objects: assetIndexData.objects
            )
        } catch {
            let globalError = GlobalError.from(error)
            throw GlobalError.download(
                i18nKey: "Asset Index Failed",
                level: .notification
            )
        }
    }

    private func setupModLoaderIfNeeded(
        selectedModLoader: String,
        selectedGameVersion: String,
        gameName: String,
        gameIcon: String,
        specifiedLoaderVersion: String
    ) async throws -> (loaderVersion: String, classpath: String, mainClass: String)? {
        let loaderType = selectedModLoader.lowercased()
        let handler: (any ModLoaderHandler.Type)?

        switch loaderType {
        case "fabric":
            handler = FabricLoaderService.self
        case "forge":
            handler = ForgeLoaderService.self
        case "neoforge":
            handler = NeoForgeLoaderService.self
        case "quilt":
            handler = QuiltLoaderService.self
        default:
            handler = nil
        }

        guard let handler else { return nil }

        // Create GameVersionInfo directly without relying on mojangVersions
        let gameInfo = GameVersionInfo(
            gameName: gameName,
            gameIcon: gameIcon,
            gameVersion: selectedGameVersion,
            assetIndex: "",
            modLoader: selectedModLoader
        )

        // Choose a different method depending on whether a loader version is specified or not
        let progressCallback: (String, Int, Int) -> Void = { [weak self] fileName, completed, total in
            Task { @MainActor in
                guard let self = self else { return }
                self.objectWillChange.send()
                switch loaderType {
                case "fabric":
                    self.fabricDownloadState.updateProgress(fileName: fileName, completed: completed, total: total, type: .core)
                case "forge":
                    self.forgeDownloadState.updateProgress(fileName: fileName, completed: completed, total: total, type: .core)
                case "neoforge":
                    self.neoForgeDownloadState.updateProgress(fileName: fileName, completed: completed, total: total, type: .core)
                case "quilt":
                    self.fabricDownloadState.updateProgress(fileName: fileName, completed: completed, total: total, type: .core)
                default:
                    break
                }
            }
        }

        return await handler.setupWithSpecificVersion(
            for: selectedGameVersion,
            loaderVersion: specifiedLoaderVersion,
            gameInfo: gameInfo,
            onProgressUpdate: progressCallback
        )
    }

    private func finalizeGameInfo(
        gameInfo: GameVersionInfo,
        manifest: MinecraftVersionManifest,
        selectedModLoader: String,
        selectedGameVersion: String,
        specifiedLoaderVersion: String,
        fabricResult: (loaderVersion: String, classpath: String, mainClass: String)? = nil,
        forgeResult: (loaderVersion: String, classpath: String, mainClass: String)? = nil,
        neoForgeResult: (loaderVersion: String, classpath: String, mainClass: String)? = nil,
        quiltResult: (loaderVersion: String, classpath: String, mainClass: String)? = nil
    ) async -> GameVersionInfo {
        var updatedGameInfo = gameInfo
        updatedGameInfo.assetIndex = manifest.assetIndex.id
        updatedGameInfo.javaVersion = manifest.javaVersion.majorVersion

        switch selectedModLoader.lowercased() {
        case "fabric", "quilt":
            if let result = selectedModLoader.lowercased() == "fabric" ? fabricResult : quiltResult {
                updatedGameInfo.modVersion = result.loaderVersion
                updatedGameInfo.modClassPath = result.classpath
                updatedGameInfo.mainClass = result.mainClass

                if selectedModLoader.lowercased() == "fabric" {
                    if let fabricLoader = try? await FabricLoaderService.fetchSpecificLoaderVersion(for: selectedGameVersion, loaderVersion: specifiedLoaderVersion) {
                        let jvmArgs = fabricLoader.arguments.jvm ?? []
                        updatedGameInfo.modJvm = jvmArgs
                        let gameArgs = fabricLoader.arguments.game ?? []
                        updatedGameInfo.gameArguments = gameArgs
                    }
                } else {
                    if let quiltLoader = try? await QuiltLoaderService.fetchSpecificLoaderVersion(for: selectedGameVersion, loaderVersion: specifiedLoaderVersion) {
                        let jvmArgs = quiltLoader.arguments.jvm ?? []
                        updatedGameInfo.modJvm = jvmArgs
                        let gameArgs = quiltLoader.arguments.game ?? []
                        updatedGameInfo.gameArguments = gameArgs
                    }
                }
            }

        case "forge":
            if let result = forgeResult {
                updatedGameInfo.modVersion = result.loaderVersion
                updatedGameInfo.modClassPath = result.classpath
                updatedGameInfo.mainClass = result.mainClass

                if let forgeLoader = try? await ForgeLoaderService.fetchSpecificForgeProfile(for: selectedGameVersion, loaderVersion: specifiedLoaderVersion) {
                    let gameArgs = forgeLoader.arguments.game ?? []
                    updatedGameInfo.gameArguments = gameArgs
                    let jvmArgs = forgeLoader.arguments.jvm ?? []
                    updatedGameInfo.modJvm = jvmArgs.map { arg in
                        arg.replacingOccurrences(of: "${version_name}", with: selectedGameVersion)
                            .replacingOccurrences(of: "${classpath_separator}", with: ":")
                            .replacingOccurrences(of: "${library_directory}", with: AppPaths.librariesDirectory.path)
                    }
                }
            }

        case "neoforge":
            if let result = neoForgeResult {
                updatedGameInfo.modVersion = result.loaderVersion
                updatedGameInfo.modClassPath = result.classpath
                updatedGameInfo.mainClass = result.mainClass

                if let neoForgeLoader = try? await NeoForgeLoaderService.fetchSpecificNeoForgeProfile(for: selectedGameVersion, loaderVersion: specifiedLoaderVersion) {
                    let gameArgs = neoForgeLoader.arguments.game ?? []
                    updatedGameInfo.gameArguments = gameArgs

                    let jvmArgs = neoForgeLoader.arguments.jvm ?? []
                    // Use NSMutableString to avoid chaining calls that create multiple temporary strings
                    updatedGameInfo.modJvm = jvmArgs.map { arg -> String in
                        let mutableArg = NSMutableString(string: arg)
                        mutableArg.replaceOccurrences(
                            of: "${version_name}",
                            with: selectedGameVersion,
                            options: [],
                            range: NSRange(location: 0, length: mutableArg.length)
                        )
                        mutableArg.replaceOccurrences(
                            of: "${classpath_separator}",
                            with: ":",
                            options: [],
                            range: NSRange(location: 0, length: mutableArg.length)
                        )
                        mutableArg.replaceOccurrences(
                            of: "${library_directory}",
                            with: AppPaths.librariesDirectory.path,
                            options: [],
                            range: NSRange(location: 0, length: mutableArg.length)
                        )
                        return mutableArg as String
                    }
                }
            }

        default:
            updatedGameInfo.mainClass = manifest.mainClass
        }

        // Build startup command
        let launcherBrand = Bundle.main.appName
        let launcherVersion = Bundle.main.fullVersion

        updatedGameInfo.launchCommand = MinecraftLaunchCommandBuilder.build(
            manifest: manifest,
            gameInfo: updatedGameInfo,
            launcherBrand: launcherBrand,
            launcherVersion: launcherVersion
        )

        return updatedGameInfo
    }

    /// Check if game name is duplicate
    /// - Parameter name: game name
    /// - Returns: Whether it is repeated
    func checkGameNameDuplicate(_ name: String) async -> Bool {
        guard !name.isEmpty else { return false }

        let fileManager = FileManager.default
        let gameDir = AppPaths.profileRootDirectory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: gameDir.path)
    }
}
