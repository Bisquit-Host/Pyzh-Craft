import SwiftUI

struct ModPackDownloadSheet: View {
    let projectId: String
    let gameInfo: GameVersionInfo?
    let query: String
    let preloadedDetail: ModrinthProjectDetail?
    @EnvironmentObject private var gameRepository: GameRepository
    @Environment(\.dismiss)
    private var dismiss

    @StateObject private var viewModel = ModPackDownloadSheetViewModel()
    @State private var selectedGameVersion: String = ""
    @State private var selectedModPackVersion: ModrinthProjectDetailVersion?
    @State private var downloadTask: Task<Void, Error>?
    @State private var isProcessing = false
    @StateObject private var gameSetupService = GameSetupUtil()
    @StateObject private var gameNameValidator: GameNameValidator

    // MARK: - Initializer
    init(
        projectId: String,
        gameInfo: GameVersionInfo?,
        query: String,
        preloadedDetail: ModrinthProjectDetail? = nil
    ) {
        self.projectId = projectId
        self.gameInfo = gameInfo
        self.query = query
        self.preloadedDetail = preloadedDetail
        self._gameNameValidator = StateObject(wrappedValue: GameNameValidator(gameSetupService: GameSetupUtil()))
    }

    var body: some View {
        CommonSheetView(
            header: { headerView },
            body: { bodyView },
            footer: { footerView }
        )
        .onAppear {
            viewModel.setGameRepository(gameRepository)
            if let preloadedDetail {
                viewModel.applyPreloadedDetail(preloadedDetail)
            } else {
                Task {
                    await viewModel.loadProjectDetails(projectId: projectId)
                }
            }
        }
        .onDisappear {
            // Clear all data after closing the page
            clearAllData()
        }
    }

    // MARK: - clear data
    /// Clear all data on the page
    private func clearAllData() {
        // If downloading is in progress, cancel the download task
        if isDownloading {
            downloadTask?.cancel()
            downloadTask = nil
            isProcessing = false
            viewModel.modPackInstallState.reset()
            gameSetupService.downloadState.reset()
        }

        // Clean selected versions
        selectedGameVersion = ""
        selectedModPackVersion = nil
        // Clean all ViewModel data and temporary files
        viewModel.cleanupAllData()
    }

    // MARK: - View Components

    private var headerView: some View {
        HStack {
            Text("Download Modpack")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bodyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isProcessing {
                ProcessingView(
                    downloadedBytes: viewModel.modPackDownloadProgress,
                    totalBytes: viewModel.modPackTotalSize
                )
            } else if viewModel.isLoadingProjectDetails {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else if let projectDetail = viewModel.projectDetail {
                ModrinthProjectTitleView(projectDetail: projectDetail)
                    .padding(.bottom, 18)

                VersionSelectionView(
                    selectedGameVersion: $selectedGameVersion,
                    selectedModPackVersion: $selectedModPackVersion,
                    availableGameVersions: viewModel.availableGameVersions,
                    filteredModPackVersions: viewModel.filteredModPackVersions,
                    isLoadingModPackVersions: viewModel.isLoadingModPackVersions,
                    isProcessing: isProcessing,
                    onGameVersionChange: handleGameVersionChange,
                    onModPackVersionAppear: selectFirstModPackVersion
                )

                if !selectedGameVersion.isEmpty && selectedModPackVersion != nil {
                    gameNameInputSection
                }

                if shouldShowProgress {
                    DownloadProgressView(
                        gameSetupService: gameSetupService,
                        modPackInstallState: viewModel.modPackInstallState,
                        lastParsedIndexInfo: viewModel.lastParsedIndexInfo
                    )
                    .padding(.top, 18)
                }
            }
        }
    }

    private var footerView: some View {
        HStack {
            cancelButton
            Spacer()
            confirmButton
        }
    }

    // MARK: - Computed Properties

    private var shouldShowProgress: Bool {
        gameSetupService.downloadState.isDownloading
            || viewModel.modPackInstallState.isInstalling
    }

    private var canDownload: Bool {
        !selectedGameVersion.isEmpty && selectedModPackVersion != nil && gameNameValidator.isFormValid
    }

    private var isDownloading: Bool {
        isProcessing || gameSetupService.downloadState.isDownloading
            || viewModel.modPackInstallState.isInstalling
    }

    // MARK: - UI Components

    private var gameNameInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !selectedGameVersion.isEmpty && selectedModPackVersion != nil {
                GameNameInputView(
                    gameName: $gameNameValidator.gameName,
                    isGameNameDuplicate: $gameNameValidator.isGameNameDuplicate,
                    isDisabled: isProcessing,
                    gameSetupService: gameSetupService
                )
            }
        }
    }

    private var cancelButton: some View {
        Button(isDownloading ? "Stop".localized() : "Cancel".localized()) {
            handleCancel()
        }
        .keyboardShortcut(.cancelAction)
    }

    private var confirmButton: some View {
        Button {
            Task {
                await downloadModPack()
            }
        } label: {
            HStack {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Download")
                }
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canDownload || isDownloading)
    }

    // MARK: - Helper Methods

    private func handleGameVersionChange(_ newValue: String) {
        if !newValue.isEmpty {
            Task {
                await viewModel.loadModPackVersions(for: newValue)
            }
            // Set default game name
            setDefaultGameName()
        } else {
            viewModel.filteredModPackVersions = []
        }
    }

    private func selectFirstModPackVersion() {
        if !viewModel.filteredModPackVersions.isEmpty
            && selectedModPackVersion == nil {
            selectedModPackVersion = viewModel.filteredModPackVersions[0]
            // Set default game name
            setDefaultGameName()
        }
    }

    private func setDefaultGameName() {
        let defaultName = GameNameGenerator.generateModPackName(
            projectTitle: viewModel.projectDetail?.title,
            gameVersion: selectedGameVersion,
            includeTimestamp: true
        )
        gameNameValidator.setDefaultName(defaultName)
    }

    private func handleCancel() {
        if isDownloading {
            downloadTask?.cancel()
            downloadTask = nil
            isProcessing = false
            viewModel.modPackInstallState.reset()

            // Clean created game folders
            Task {
                await cleanupGameDirectories(gameName: gameNameValidator.gameName)
            }
            // Close the sheet directly after stopping
            dismiss()
        } else {
            dismiss()
        }
    }

    // MARK: - Download Action

    @MainActor
    private func downloadModPack() async {
        guard let selectedVersion = selectedModPackVersion,
            let projectDetail = viewModel.projectDetail
        else { return }

        downloadTask = Task {
            await performModPackDownload(
                selectedVersion: selectedVersion,
                projectDetail: projectDetail
            )
        }
    }

    @MainActor
    private func performModPackDownload(
        selectedVersion: ModrinthProjectDetailVersion,
        projectDetail: ModrinthProjectDetail
    ) async {
        isProcessing = true

        // 1. Download the integration package
        guard
            let downloadedPath = await downloadModPackFile(
                selectedVersion: selectedVersion,
                projectDetail: projectDetail
            )
        else {
            isProcessing = false
            return
        }

        // 2. Unzip the integration package
        guard
            let extractedPath = await viewModel.extractModPack(
                modPackPath: downloadedPath
            )
        else {
            isProcessing = false
            return
        }

        // 3. Parse modrinth.index.json
        guard
            let indexInfo = await viewModel.parseModrinthIndex(
                extractedPath: extractedPath
            )
        else {
            isProcessing = false
            return
        }

        // 4. Download the game icon
        let iconPath = await viewModel.downloadGameIcon(
            projectDetail: projectDetail,
            gameName: gameNameValidator.gameName
        )

        // 5. Create profile folder
        let profileCreated = await withCheckedContinuation { continuation in
            Task {
                let result = await createProfileDirectories(for: gameNameValidator.gameName)
                continuation.resume(returning: result)
            }
        }

        if !profileCreated {
            handleInstallationResult(success: false, gameName: gameNameValidator.gameName)
            return
        }

        // Entering the installation phase (copying overrides/downloading files/installing dependencies) is no longer considered "parsing"
        // Keep the UI structure unchanged and only make the progress bar area visible through state switching
        isProcessing = false

        // 6. Copy the overrides file (before installing dependencies)
        let resourceDir = AppPaths.profileDirectory(gameName: gameNameValidator.gameName)
        // First calculate the total number of overrides files
        let overridesTotal = await calculateOverridesTotal(extractedPath: extractedPath)

        // Only when there is an overrides file, isInstalling and overridesTotal are set in advance
        // Make sure the progress bar is displayed before copying starts (updateOverridesProgress will update other status in the callback)
        if overridesTotal > 0 {
            await MainActor.run {
                viewModel.modPackInstallState.isInstalling = true
                viewModel.modPackInstallState.overridesTotal = overridesTotal
                viewModel.objectWillChange.send()
            }
        }

        // Wait a short period of time to ensure the UI is updated
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let overridesSuccess = await ModPackDependencyInstaller.installOverrides(
            extractedPath: extractedPath,
            resourceDir: resourceDir
        ) { fileName, completed, total, type in
            Task { @MainActor in
                updateInstallProgress(
                    fileName: fileName,
                    completed: completed,
                    total: total,
                    type: type
                )
                viewModel.objectWillChange.send()
            }
        }

        if !overridesSuccess {
            handleInstallationResult(success: false, gameName: gameNameValidator.gameName)
            return
        }

        // 7. Prepare for installation
        let tempGameInfo = GameVersionInfo(
            id: UUID(),
            gameName: gameNameValidator.gameName,
            gameIcon: iconPath ?? "",
            gameVersion: selectedGameVersion,
            assetIndex: "",
            modLoader: indexInfo.loaderType
        )

        let (filesToDownload, requiredDependencies) =
            calculateInstallationCounts(from: indexInfo)

        viewModel.modPackInstallState.startInstallation(
            filesTotal: filesToDownload.count,
            dependenciesTotal: requiredDependencies.count
        )

        // 8. Download the integration package file (mod file)
        let filesSuccess = await ModPackDependencyInstaller.installModPackFiles(
            files: indexInfo.files,
            resourceDir: resourceDir,
            gameInfo: tempGameInfo
        ) { fileName, completed, total, type in
            Task { @MainActor in
                viewModel.objectWillChange.send()
                updateInstallProgress(
                    fileName: fileName,
                    completed: completed,
                    total: total,
                    type: type
                )
            }
        }

        if !filesSuccess {
            handleInstallationResult(success: false, gameName: gameNameValidator.gameName)
            return
        }

        // 9. Install dependencies
        let dependencySuccess = await ModPackDependencyInstaller.installModPackDependencies(
            dependencies: indexInfo.dependencies,
            gameInfo: tempGameInfo,
            resourceDir: resourceDir
        ) { fileName, completed, total, type in
            Task { @MainActor in
                viewModel.objectWillChange.send()
                updateInstallProgress(
                    fileName: fileName,
                    completed: completed,
                    total: total,
                    type: type
                )
            }
        }

        if !dependencySuccess {
            handleInstallationResult(success: false, gameName: gameNameValidator.gameName)
            return
        }

        // 10. Install the game itself
        let gameSuccess = await withCheckedContinuation { continuation in
            Task {
                await gameSetupService.saveGame(
                    gameName: gameNameValidator.gameName,
                    gameIcon: iconPath ?? "",
                    selectedGameVersion: selectedGameVersion,
                    selectedModLoader: indexInfo.loaderType,
                    specifiedLoaderVersion: indexInfo.loaderVersion,
                    pendingIconData: nil,
                    playerListViewModel: nil,
                    gameRepository: gameRepository,
                    onSuccess: {
                        continuation.resume(returning: true)
                    },
                    onError: { error, message in
                        Task { @MainActor in
                            Logger.shared.error("游戏设置失败: \(message)")
                            GlobalErrorHandler.shared.handle(error)
                        }
                        continuation.resume(returning: false)
                    }
                )
            }
        }

        handleInstallationResult(success: gameSuccess, gameName: gameNameValidator.gameName)
    }

    private func downloadModPackFile(
        selectedVersion: ModrinthProjectDetailVersion,
        projectDetail: ModrinthProjectDetail
    ) async -> URL? {
        let primaryFile =
            selectedVersion.files.first { $0.primary }
            ?? selectedVersion.files.first

        guard let fileToDownload = primaryFile else {
            let globalError = GlobalError.resource(
                chineseMessage: "没有找到可下载的文件",
                i18nKey: "No downloadable file",
                level: .notification
            )
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }

        return await viewModel.downloadModPackFile(
            file: fileToDownload,
            projectDetail: projectDetail
        )
    }

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
            Logger.shared.error("计算 overrides 文件总数失败: \(error.localizedDescription)")
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
                Logger.shared.error(
                    "创建目录失败: \(dir.path), 错误: \(error.localizedDescription)"
                )
                GlobalErrorHandler.shared.handle(
                    GlobalError.fileSystem(
                        chineseMessage: "创建目录失败: \(dir.path)",
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

    private func updateInstallProgress(
        fileName: String,
        completed: Int,
        total: Int,
        type: ModPackDependencyInstaller.DownloadType
    ) {
        switch type {
        case .files:
            viewModel.modPackInstallState.updateFilesProgress(
                fileName: fileName,
                completed: completed,
                total: total
            )
        case .dependencies:
            viewModel.modPackInstallState.updateDependenciesProgress(
                dependencyName: fileName,
                completed: completed,
                total: total
            )
        case .overrides:
            viewModel.modPackInstallState.updateOverridesProgress(
                overrideName: fileName,
                completed: completed,
                total: total
            )
        }
    }

    private func handleInstallationResult(success: Bool, gameName: String) {
        if success {
            Logger.shared.info("整合包依赖安装完成: \(gameName)")
            // Clean up index data no longer needed to free up memory
            viewModel.clearParsedIndexInfo()
            dismiss()
        } else {
            Logger.shared.error("整合包依赖安装失败: \(gameName)")
            // Clean created game folders
            Task {
                await cleanupGameDirectories(gameName: gameName)
            }
            let globalError = GlobalError.resource(
                chineseMessage: "整合包依赖安装失败",
                i18nKey: "Modpack dependencies failed",
                level: .notification
            )
            GlobalErrorHandler.shared.handle(globalError)
            viewModel.modPackInstallState.reset()
            gameSetupService.downloadState.reset()
            // Clean up index data no longer needed to free up memory
            viewModel.clearParsedIndexInfo()
        }
        isProcessing = false
    }

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
}
