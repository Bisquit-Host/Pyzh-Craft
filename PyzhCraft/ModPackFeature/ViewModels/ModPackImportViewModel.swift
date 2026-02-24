import SwiftUI

// MARK: - ModPack Import View Model
@MainActor
class ModPackImportViewModel: BaseGameFormViewModel {
    private let modPackViewModel = ModPackDownloadSheetViewModel()
    
    @Published var selectedModPackFile: URL?
    @Published var extractedModPackPath: URL?
    @Published var modPackIndexInfo: ModrinthIndexInfo?
    @Published var isProcessingModPack = false
    
    private let onProcessingStateChanged: (Bool) -> Void
    private var gameRepository: GameRepository?
    
    // MARK: - Initialization
    init(
        configuration: GameFormConfiguration,
        preselectedFile: URL? = nil,
        shouldStartProcessing: Bool = false,
        onProcessingStateChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onProcessingStateChanged = onProcessingStateChanged
        super.init(configuration: configuration)
        
        self.selectedModPackFile = preselectedFile
        self.isProcessingModPack = shouldStartProcessing
    }
    
    // MARK: - Setup Methods
    
    func setup(gameRepository: GameRepository) {
        self.gameRepository = gameRepository
        modPackViewModel.setGameRepository(gameRepository)
        
        // If there are preselected files, start processing
        if selectedModPackFile != nil && isProcessingModPack {
            Task {
                await parseSelectedModPack()
            }
        }
        
        updateParentState()
    }
    
    // MARK: - Override Methods
    override func performConfirmAction() async {
        startDownloadTask {
            await self.importModPack()
        }
    }
    
    override func handleCancel() {
        if computeIsDownloading() {
            // Stop download task
            downloadTask?.cancel()
            downloadTask = nil
            
            // Cancel download status
            gameSetupService.downloadState.cancel()
            // ModPackInstallState does not have a dedicated cancel method and directly resets the state
            modPackViewModel.modPackInstallState.reset()
            
            // Stop processing status
            isProcessingModPack = false
            onProcessingStateChanged(false)
            
            // Perform post-cancellation cleanup
            Task {
                await performCancelCleanup()
            }
        } else {
            configuration.actions.onCancel()
        }
    }
    
    override func performCancelCleanup() async {
        let gameName = gameNameValidator.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        let extractedPath = extractedModPackPath
        
        // Perform file deletion in the background to avoid the main thread FileManager
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            if !gameName.isEmpty {
                let profileDir = AppPaths.profileDirectory(gameName: gameName)
                if fm.fileExists(atPath: profileDir.path) {
                    do {
                        try fm.removeItem(at: profileDir)
                        Logger.shared.info("Deleted uncreated ModPack game folder: \(profileDir.path)")
                    } catch {
                        Logger.shared.error("Failed to delete ModPack game folder: \(error.localizedDescription)")
                    }
                }
            }
            if let path = extractedPath, fm.fileExists(atPath: path.path) {
                do {
                    try fm.removeItem(at: path)
                    Logger.shared.info("Deleted ModPack temporary decompression file: \(path.path)")
                } catch {
                    Logger.shared.error("Failed to delete ModPack temporary files: \(error.localizedDescription)")
                }
            }
        }.value
        
        gameSetupService.downloadState.reset()
        modPackViewModel.modPackInstallState.reset()
        configuration.actions.onCancel()
    }
    
    override func computeIsDownloading() -> Bool {
        return gameSetupService.downloadState.isDownloading
        || modPackViewModel.modPackInstallState.isInstalling
        || isProcessingModPack
    }
    
    override func computeIsFormValid() -> Bool {
        let hasFile = selectedModPackFile != nil
        let hasInfo = modPackIndexInfo != nil
        let nameValid = gameNameValidator.isFormValid
        return hasFile && hasInfo && nameValid
    }
    
    // MARK: - ModPack Processing
    func parseSelectedModPack() async {
        guard let selectedFile = selectedModPackFile else { return }
        
        isProcessingModPack = true
        onProcessingStateChanged(true)
        
        // Unzip the integration package
        guard let extracted = await modPackViewModel.extractModPack(modPackPath: selectedFile) else {
            isProcessingModPack = false
            onProcessingStateChanged(false)
            return
        }
        
        extractedModPackPath = extracted
        
        // Parse index information
        if let parsed = await modPackViewModel.parseModrinthIndex(extractedPath: extracted) {
            modPackIndexInfo = parsed
            let defaultName = GameNameGenerator.generateImportName(
                modPackName: parsed.modPackName,
                modPackVersion: parsed.modPackVersion,
                includeTimestamp: true
            )
            gameNameValidator.setDefaultName(defaultName)
            isProcessingModPack = false
            onProcessingStateChanged(false)
        } else {
            isProcessingModPack = false
            onProcessingStateChanged(false)
        }
    }
    
    // MARK: - ModPack Import
    private func importModPack() async {
        guard selectedModPackFile != nil,
              let extractedPath = extractedModPackPath,
              let indexInfo = modPackIndexInfo,
              let gameRepository = gameRepository else { return }
        
        isProcessingModPack = true
        
        // 1. Create profile folder
        let profileCreated = await createProfileDirectories(for: gameNameValidator.gameName)
        
        if !profileCreated {
            handleModPackInstallationResult(success: false, gameName: gameNameValidator.gameName)
            return
        }
        
        // 2. Copy the overrides file (before installing dependencies)
        let resourceDir = AppPaths.profileDirectory(gameName: gameNameValidator.gameName)
        // First calculate the total number of overrides files
        let overridesTotal = await calculateOverridesTotal(extractedPath: extractedPath)
        
        // Only when there is an overrides file, isInstalling and overridesTotal are set in advance
        // Make sure the progress bar is displayed before copying starts (updateOverridesProgress will update other status in the callback)
        if overridesTotal > 0 {
            await MainActor.run {
                modPackViewModel.modPackInstallState.isInstalling = true
                modPackViewModel.modPackInstallState.overridesTotal = overridesTotal
                modPackViewModel.objectWillChange.send()
            }
        }
        
        // Wait a short period of time to ensure the UI is updated
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let overridesSuccess = await ModPackDependencyInstaller.installOverrides(
            extractedPath: extractedPath,
            resourceDir: resourceDir
        ) { [self] fileName, completed, total, type in
            Task { @MainActor in
                updateModPackInstallProgress(
                    fileName: fileName,
                    completed: completed,
                    total: total,
                    type: type
                )
                modPackViewModel.objectWillChange.send()
            }
        }
        
        if !overridesSuccess {
            handleModPackInstallationResult(success: false, gameName: gameNameValidator.gameName)
            return
        }
        
        // 3. Prepare for installation
        let tempGameInfo = GameVersionInfo(
            id: UUID(),
            gameName: gameNameValidator.gameName,
            gameIcon: AppConstants.defaultGameIcon,
            gameVersion: indexInfo.gameVersion,
            assetIndex: "",
            modLoader: indexInfo.loaderType
        )
        
        let (filesToDownload, requiredDependencies) = calculateInstallationCounts(from: indexInfo)
        
        modPackViewModel.modPackInstallState.startInstallation(
            filesTotal: filesToDownload.count,
            dependenciesTotal: requiredDependencies.count
        )
        
        isProcessingModPack = false
        
        // 4. Download the integration package file (mod file)
        let filesSuccess = await ModPackDependencyInstaller.installModPackFiles(
            files: indexInfo.files,
            resourceDir: resourceDir,
            gameInfo: tempGameInfo
        ) { [self] fileName, completed, total, type in
            Task { @MainActor in
                modPackViewModel.objectWillChange.send()
                updateModPackInstallProgress(
                    fileName: fileName,
                    completed: completed,
                    total: total,
                    type: type
                )
            }
        }
        
        if !filesSuccess {
            handleModPackInstallationResult(success: false, gameName: gameNameValidator.gameName)
            return
        }
        
        // 5. Install dependencies
        let dependencySuccess = await ModPackDependencyInstaller.installModPackDependencies(
            dependencies: indexInfo.dependencies,
            gameInfo: tempGameInfo,
            resourceDir: resourceDir
        ) { [self] fileName, completed, total, type in
            Task { @MainActor in
                modPackViewModel.objectWillChange.send()
                updateModPackInstallProgress(
                    fileName: fileName,
                    completed: completed,
                    total: total,
                    type: type
                )
            }
        }
        
        if !dependencySuccess {
            handleModPackInstallationResult(success: false, gameName: gameNameValidator.gameName)
            return
        }
        
        // 6. Install the game itself
        let gameSuccess = await withCheckedContinuation { continuation in
            Task {
                await gameSetupService.saveGame(
                    gameName: gameNameValidator.gameName,
                    gameIcon: AppConstants.defaultGameIcon,
                    selectedGameVersion: indexInfo.gameVersion,
                    selectedModLoader: indexInfo.loaderType,
                    specifiedLoaderVersion: indexInfo.loaderVersion,
                    pendingIconData: nil,
                    playerListViewModel: nil, // Will be set from environment
                    gameRepository: gameRepository,
                    onSuccess: {
                        continuation.resume(returning: true)
                    },
                    onError: { error, message in
                        Task { @MainActor in
                            Logger.shared.error("Game setup failed: \(message)")
                            GlobalErrorHandler.shared.handle(error)
                        }
                        continuation.resume(returning: false)
                    }
                )
            }
        }
        
        handleModPackInstallationResult(success: gameSuccess, gameName: gameNameValidator.gameName)
    }
    
    // MARK: - Helper Methods
    private func calculateOverridesTotal(extractedPath: URL) async -> Int {
        // Check Modrinth format overrides first
        var overridesPath = extractedPath.appendingPathComponent("overrides")
        
        // If not present, check the CurseForge format overrides folder
        if !FileManager.default.fileExists(atPath: overridesPath.path) {
            let possiblePaths = ["overrides", "Override", "override"]
            for pathName in possiblePaths {
                let testPath = extractedPath.appendingPathComponent(pathName)
                if FileManager.default.fileExists(atPath: testPath.path) {
                    overridesPath = testPath
                    break
                }
            }
        }
        
        // If the overrides folder does not exist, returns 0
        guard FileManager.default.fileExists(atPath: overridesPath.path) else {
            return 0
        }
        
        // Count total number of files
        do {
            let allFiles = try InstanceFileCopier.getAllFiles(in: overridesPath)
            return allFiles.count
        } catch {
            Logger.shared.error("Failed to calculate total number of overrides files: \(error.localizedDescription)")
            return 0
        }
    }
    
    private func createProfileDirectories(for gameName: String) async -> Bool {
        let profileDirectory = AppPaths.profileDirectory(gameName: gameName)
        
        let subdirs = AppPaths.profileSubdirectories.map {
            profileDirectory.appendingPathComponent($0)
        }
        
        for dir in [profileDirectory] + subdirs {
            do {
                try FileManager.default.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true
                )
            } catch {
                Logger.shared.error("Failed to create directory: \(dir.path), error: \(error.localizedDescription)")
                GlobalErrorHandler.shared.handle(
                    GlobalError.fileSystem(
                        i18nKey: "Directory Creation Failed",
                        level: .notification
                    )
                )
                return false
            }
        }
        
        return true
    }
    
    private func calculateInstallationCounts(
        from indexInfo: ModrinthIndexInfo
    ) -> ([ModrinthIndexFile], [ModrinthIndexProjectDependency]) {
        let filesToDownload = indexInfo.files.filter { file in
            if let env = file.env, let client = env.client,
               client.lowercased() == "unsupported" {
                return false
            }
            return true
        }
        let requiredDependencies = indexInfo.dependencies.filter {
            $0.dependencyType == "required"
        }
        
        return (filesToDownload, requiredDependencies)
    }
    
    private func updateModPackInstallProgress(
        fileName: String,
        completed: Int,
        total: Int,
        type: ModPackDependencyInstaller.DownloadType
    ) {
        switch type {
        case .files:
            modPackViewModel.modPackInstallState.updateFilesProgress(
                fileName: fileName,
                completed: completed,
                total: total
            )
        case .dependencies:
            modPackViewModel.modPackInstallState.updateDependenciesProgress(
                dependencyName: fileName,
                completed: completed,
                total: total
            )
        case .overrides:
            modPackViewModel.modPackInstallState.updateOverridesProgress(
                overrideName: fileName,
                completed: completed,
                total: total
            )
        }
    }
    
    private func handleModPackInstallationResult(success: Bool, gameName: String) {
        if success {
            Logger.shared.info("Local integration package import completed: \(gameName)")
            // Clean up index data no longer needed to free up memory
            modPackViewModel.clearParsedIndexInfo()
            configuration.actions.onCancel() // Use cancel to dismiss
        } else {
            Logger.shared.error("Local integration package import failed: \(gameName)")
            // Clean created game folders
            Task {
                await cleanupGameDirectories(gameName: gameName)
            }
            let globalError = GlobalError.resource(
                i18nKey: "Local modpack import failed",
                level: .notification
            )
            GlobalErrorHandler.shared.handle(globalError)
            modPackViewModel.modPackInstallState.reset()
            gameSetupService.downloadState.reset()
            // Clean up index data no longer needed to free up memory
            modPackViewModel.clearParsedIndexInfo()
        }
        isProcessingModPack = false
    }
    
    private func cleanupGameDirectories(gameName: String) async {
        do {
            let fileManager = MinecraftFileManager()
            try fileManager.cleanupGameDirectories(gameName: gameName)
        } catch {
            Logger.shared.error("Failed to clean game folder: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Computed Properties for UI Updates
    var shouldShowProgress: Bool {
        gameSetupService.downloadState.isDownloading
        || modPackViewModel.modPackInstallState.isInstalling
    }
    
    var hasSelectedModPack: Bool {
        selectedModPackFile != nil
    }
    
    var modPackName: String {
        modPackIndexInfo?.modPackName ?? ""
    }
    
    var gameVersion: String {
        modPackIndexInfo?.gameVersion ?? ""
    }
    
    var modPackVersion: String {
        modPackIndexInfo?.modPackVersion ?? ""
    }
    
    var loaderInfo: String {
        guard let indexInfo = modPackIndexInfo else { return "" }
        return indexInfo.loaderVersion.isEmpty
        ? indexInfo.loaderType
        : "\(indexInfo.loaderType)-\(indexInfo.loaderVersion)"
    }
    
    // MARK: - Expose Internal Objects
    var modPackViewModelForProgress: ModPackDownloadSheetViewModel {
        modPackViewModel
    }
}
