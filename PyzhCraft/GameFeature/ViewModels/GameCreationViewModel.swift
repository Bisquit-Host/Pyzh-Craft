import SwiftUI
import UniformTypeIdentifiers

// MARK: - Game Creation View Model
@MainActor
class GameCreationViewModel: BaseGameFormViewModel {
    // MARK: - Published Properties
    @Published var gameIcon = AppConstants.defaultGameIcon
    @Published var iconImage: Image?
    @Published var selectedGameVersion = ""
    @Published var versionTime = ""
    @Published var selectedModLoader = "vanilla"
    @Published var selectedLoaderVersion = ""
    @Published var availableLoaderVersions: [String] = []
    @Published var availableVersions: [String] = []

    // MARK: - Private Properties
    private var pendingIconData: Data?
    private var pendingIconURL: URL?
    private var didInit = false

    // MARK: - Environment Objects (to be set from view)
    private var gameRepository: GameRepository?
    private var playerListViewModel: PlayerListViewModel?

    // MARK: - Initialization
    override init(configuration: GameFormConfiguration) {
        super.init(configuration: configuration)
    }

    // MARK: - Setup Methods
    func setup(gameRepository: GameRepository, playerListViewModel: PlayerListViewModel) {
        self.gameRepository = gameRepository
        self.playerListViewModel = playerListViewModel

        if !didInit {
            didInit = true
            Task {
                await initializeVersionPicker()
            }
        }
        updateParentState()
    }

    // MARK: - Override Methods
    override func performConfirmAction() async {
        startDownloadTask {
            await self.saveGame()
        }
    }

    override func handleCancel() {
        if isDownloading {
            // Stop download task
            downloadTask?.cancel()
            downloadTask = nil

            // Cancel download status
            gameSetupService.downloadState.cancel()

            // Perform post-cancellation cleanup
            Task {
                await performCancelCleanup()
            }
        } else {
            configuration.actions.onCancel()
        }
    }

    override func performCancelCleanup() async {
        // If you cancel while downloading, you need to delete the created game folder
        let gameName = gameNameValidator.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !gameName.isEmpty {
            // Check if the game has been saved to the warehouse
            // If it has been saved, it means the game was created successfully and the folder should not be deleted
            let isGameSaved = await MainActor.run {
                guard let gameRepository = gameRepository else { return false }
                return gameRepository.games.contains { $0.gameName == gameName }
            }

            if !isGameSaved {
                // The game is not saved, indicating that the operation is cancelled. You can safely delete the folder
                do {
                    let profileDir = AppPaths.profileDirectory(gameName: gameName)

                    // Check if directory exists
                    if FileManager.default.fileExists(atPath: profileDir.path) {
                        try FileManager.default.removeItem(at: profileDir)
                        Logger.shared.info("已删除取消创建的游戏文件夹: \(profileDir.path)")
                    }
                } catch {
                    Logger.shared.error("删除游戏文件夹失败: \(error.localizedDescription)")
                    // This should not prevent the window from closing even if the deletion fails
                }
            } else {
                // The game is saved and the folder should not be deleted
                Logger.shared.info("游戏已成功保存，跳过删除文件夹: \(gameName)")
            }
        }

        // Reset download status and close window
        await MainActor.run {
            gameSetupService.downloadState.reset()
            configuration.actions.onCancel()
        }
    }

    override func computeIsDownloading() -> Bool {
        gameSetupService.downloadState.isDownloading
    }

    override func computeIsFormValid() -> Bool {
        let isLoaderVersionValid = selectedModLoader == "vanilla" || !selectedLoaderVersion.isEmpty
        return gameNameValidator.isFormValid && isLoaderVersionValid
    }

    // MARK: - Version Management
    /// Initial version selector
    func initializeVersionPicker() async {
        let includeSnapshots = GameSettingsManager.shared.includeSnapshotsForGameVersions
        let compatibleVersions = await CommonService.compatibleVersions(
            for: selectedModLoader,
            includeSnapshots: includeSnapshots
        )
        await updateAvailableVersions(compatibleVersions)
    }

    /// Update available versions and set default selections
    func updateAvailableVersions(_ versions: [String]) async {
        self.availableVersions = versions
        // If the currently selected version is not in the compatible version list, select the first compatible version
        if !versions.contains(self.selectedGameVersion) && !versions.isEmpty {
            self.selectedGameVersion = versions.first ?? ""
        }

        // Get the time information of the currently selected version
        if !versions.isEmpty {
            let targetVersion = versions.contains(self.selectedGameVersion) ? self.selectedGameVersion : (versions.first ?? "")
            let timeString = await ModrinthService.queryVersionTime(from: targetVersion)
            self.versionTime = timeString
        }
    }

    /// Handling mod loader changes
    func handleModLoaderChange(_ newLoader: String) {
        Task {
            let includeSnapshots = GameSettingsManager.shared.includeSnapshotsForGameVersions
            let compatibleVersions = await CommonService.compatibleVersions(
                for: newLoader,
                includeSnapshots: includeSnapshots
            )
            await updateAvailableVersions(compatibleVersions)

            // Update loader version list
            if newLoader != "vanilla" && !selectedGameVersion.isEmpty {
                await updateLoaderVersions(for: newLoader, gameVersion: selectedGameVersion)
            } else {
                await MainActor.run {
                    availableLoaderVersions = []
                    selectedLoaderVersion = ""
                }
            }
        }
    }

    /// Handle game version changes
    func handleGameVersionChange(_ newGameVersion: String) {
        Task {
            await updateLoaderVersions(for: selectedModLoader, gameVersion: newGameVersion)
        }
    }

    /// Update loader version list
    private func updateLoaderVersions(for loader: String, gameVersion: String) async {
        guard loader != "vanilla" && !gameVersion.isEmpty else {
            availableLoaderVersions = []
            selectedLoaderVersion = ""
            return
        }

        var versions: [String] = []

        switch loader.lowercased() {
        case "fabric":
            let fabricVersions = await FabricLoaderService.fetchAllLoaderVersions(for: gameVersion)
            versions = fabricVersions.map { $0.loader.version }
        case "forge":
            do {
                let forgeVersions = try await ForgeLoaderService.fetchAllForgeVersions(for: gameVersion)
                versions = forgeVersions.loaders.map { $0.id }
            } catch {
                Logger.shared.error("获取 Forge 版本失败: \(error.localizedDescription)")
                versions = []
            }
        case "neoforge":
            do {
                let neoforgeVersions = try await NeoForgeLoaderService.fetchAllNeoForgeVersions(for: gameVersion)
                versions = neoforgeVersions.loaders.map { $0.id }
            } catch {
                Logger.shared.error("获取 NeoForge 版本失败: \(error.localizedDescription)")
                versions = []
            }
        case "quilt":
            let quiltVersions = await QuiltLoaderService.fetchAllQuiltLoaders(for: gameVersion)
            versions = quiltVersions.map { $0.loader.version }
        default:
            versions = []
        }

        availableLoaderVersions = versions
        // If the currently selected version is not in the list, select the first version
        if !versions.contains(selectedLoaderVersion) && !versions.isEmpty {
            selectedLoaderVersion = versions.first ?? ""
        } else if versions.isEmpty {
            selectedLoaderVersion = ""
        }
    }

    // MARK: - Image Handling
    func handleImagePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                handleNonCriticalError(
                    GlobalError.validation(
                        chineseMessage: "未选择文件",
                        i18nKey: "No File Selected",
                        level: .notification
                    ),
                    message: "Image Selection Failed"
                )
                return
            }
            guard url.startAccessingSecurityScopedResource() else {
                handleFileAccessError(URLError(.cannotOpenFile), context: "图片文件")
                return
            }
            Task {
                let result: Result<(Data, URL), Error> = await Task.detached(priority: .userInitiated) {
                    do {
                        let data = try Data(contentsOf: url)
                        let tempDir = FileManager.default.temporaryDirectory
                        let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString).png")
                        try data.write(to: tempURL)
                        return .success((data, tempURL))
                    } catch {
                        return .failure(error)
                    }
                }.value
                url.stopAccessingSecurityScopedResource()
                switch result {
                case .success(let (dataToWrite, tempURL)):
                    pendingIconURL = tempURL
                    pendingIconData = dataToWrite
                    iconImage = nil
                case .failure(let error):
                    handleFileReadError(error, context: "图片文件")
                }
            }

        case .failure(let error):
            let globalError = GlobalError.from(error)
            handleNonCriticalError(
                globalError,
                message: "Image Selection Failed"
            )
        }
    }

    func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            Logger.shared.error("图片拖放失败：没有提供者")
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { data, error in
                if let error = error {
                    DispatchQueue.main.async {
                        let globalError = GlobalError.from(error)
                        self.handleNonCriticalError(
                            globalError,
                            message: "Failed to Load Dragged Image"
                        )
                    }
                    return
                }

                if let data = data {
                    Task { @MainActor in
                        let result: URL? = await Task.detached(priority: .userInitiated) {
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("\(UUID().uuidString).png")
                            do {
                                try data.write(to: tempURL)
                                return tempURL
                            } catch {
                                return nil
                            }
                        }.value
                        if let tempURL = result {
                            self.pendingIconURL = tempURL
                            self.pendingIconData = data
                            self.iconImage = nil
                        } else {
                            self.handleFileReadError(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil), context: "图片保存")
                        }
                    }
                }
            }
            return true
        }
        Logger.shared.warning("图片拖放失败：不支持的类型")
        return false
    }

    // MARK: - Game Save Methods
    private func saveGame() async {
        guard let gameRepository = gameRepository,
              let playerListViewModel = playerListViewModel else {
            Logger.shared.error("GameRepository 或 PlayerListViewModel 未设置")
            return
        }

        // For non-vanilla loaders, saving is not allowed if no version is selected
        let loaderVersion = selectedModLoader == "vanilla" ? selectedModLoader : selectedLoaderVersion

        await gameSetupService.saveGame(
            gameName: gameNameValidator.gameName,
            gameIcon: gameIcon,
            selectedGameVersion: selectedGameVersion,
            selectedModLoader: selectedModLoader,
            specifiedLoaderVersion: loaderVersion,
            pendingIconData: pendingIconData,
            playerListViewModel: playerListViewModel,
            gameRepository: gameRepository,
            onSuccess: {
                Task { @MainActor in
                    self.configuration.actions.onCancel() // Use cancel to dismiss
                }
            },
            onError: { error, message in
                Task { @MainActor in
                    self.handleNonCriticalError(error, message: message)
                }
            }
        )
    }

    // MARK: - Computed Properties for UI Updates
    var shouldShowProgress: Bool {
        gameSetupService.downloadState.isDownloading
    }

    var pendingIconURLForDisplay: URL? {
        pendingIconURL
    }
}
