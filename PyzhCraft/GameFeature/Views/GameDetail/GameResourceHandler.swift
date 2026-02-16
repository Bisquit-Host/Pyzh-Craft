import SwiftUI

enum GameResourceHandler {
    static func updateButtonState(
        gameInfo: GameVersionInfo?,
        project: ModrinthProject,
        gameRepository: GameRepository,
        addButtonState: Binding<ModrinthDetailCardView.AddButtonState>
    ) {
        guard let gameInfo = gameInfo else { return }
        // When there is no file hash, check whether the project ID is installed by scanning the directory
        let modsDir = AppPaths.modsDirectory(gameName: gameInfo.gameName)
        ModScanner.shared.scanResourceDirectory(modsDir) { details in
            let installed = details.contains { $0.id == project.projectId }
            DispatchQueue.main.async {
                if installed {
                    addButtonState.wrappedValue = .installed
                } else if addButtonState.wrappedValue == .installed {
                    addButtonState.wrappedValue = .idle
                }
            }
        }
    }

    // MARK: - file deletion

    /// Delete files (silent version)
    static func performDelete(fileURL: URL) {
        do {
            try performDeleteThrowing(fileURL: fileURL)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("删除文件失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// Delete file (throws exception version)
    static func performDeleteThrowing(fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw GlobalError.resource(
                i18nKey: "File Not Found",
                level: .notification
            )
        }

        // If it is a mod file, obtain the hash before deleting it so that it can be removed from the cache
        var hash: String?
        var gameName: String?
        if isModsDirectory(fileURL.deletingLastPathComponent()) {
            // Extract gameName from file path
            gameName = extractGameName(from: fileURL.deletingLastPathComponent())
            // Get the hash of the file
            hash = ModScanner.sha1Hash(of: fileURL)
        }

        do {
            try FileManager.default.removeItem(at: fileURL)

            // After the deletion is successful, if it is a mod, it will be removed from the cache
            if let hash = hash, let gameName = gameName {
                ModScanner.shared.removeModHash(hash, from: gameName)
            }
        } catch {
            throw GlobalError.fileSystem(
                i18nKey: "File Deletion Failed",
                level: .notification
            )
        }
    }

    /// Determine whether the directory is a mods directory
    /// - Parameter dir: directory URL
    /// - Returns: whether it is the mods directory
    private static func isModsDirectory(_ dir: URL) -> Bool {
        dir.lastPathComponent.lowercased() == "mods"
    }

    /// Extract game name from mods directory path
    /// - Parameter modsDir: mods directory URL
    /// - Returns: game name, returns nil if it cannot be extracted
    private static func extractGameName(from modsDir: URL) -> String? {
        // Mods directory structure: profileRootDirectory/gameName/mods, gameName is the parent directory
        let parentDir = modsDir.deletingLastPathComponent()
        return parentDir.lastPathComponent
    }

    // MARK: - Download method

    @MainActor
    static func downloadWithDependencies(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        query: String,
        gameRepository: GameRepository,
        updateButtonState: @escaping () -> Void
    ) async {
        do {
            try await downloadWithDependenciesThrowing(
                project: project,
                gameInfo: gameInfo,
                query: query,
                gameRepository: gameRepository
            )
            updateButtonState()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("下载依赖项失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    @MainActor
    static func downloadWithDependenciesThrowing(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        query: String,
        gameRepository: GameRepository
    ) async throws {
        guard let gameInfo = gameInfo else {
            throw GlobalError.validation(
                i18nKey: "Game Info Missing",
                level: .notification
            )
        }

        var actuallyDownloaded: [ModrinthProjectDetail] = []
        var visited: Set<String> = []

        await ModrinthDependencyDownloader.downloadAllDependenciesRecursive(
            for: project.projectId,
            gameInfo: gameInfo,
            query: query,
            gameRepository: gameRepository,
            actuallyDownloaded: &actuallyDownloaded,
            visited: &visited
        )
    }

    @MainActor
    static func downloadSingleResource(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        query: String,
        gameRepository: GameRepository,
        updateButtonState: @escaping () -> Void
    ) async {
        do {
            try await downloadSingleResourceThrowing(
                project: project,
                gameInfo: gameInfo,
                query: query,
                gameRepository: gameRepository
            )
            updateButtonState()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("下载单个资源失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    @MainActor
    static func downloadSingleResourceThrowing(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        query: String,
        gameRepository: GameRepository
    ) async throws {
        guard let gameInfo = gameInfo else {
            throw GlobalError.validation(
                i18nKey: "Game Info Missing",
                level: .notification
            )
        }

        _ = await ModrinthDependencyDownloader.downloadMainResourceOnly(
            mainProjectId: project.projectId,
            gameInfo: gameInfo,
            query: query,
            gameRepository: gameRepository,
            filterLoader: query != "shader"
        )
    }

    @MainActor
    static func prepareManualDependencies(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        depVM: DependencySheetViewModel
    ) async -> Bool {
        do {
            return try await prepareManualDependenciesThrowing(
                project: project,
                gameInfo: gameInfo,
                depVM: depVM
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("准备手动依赖项失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            depVM.missingDependencies = []
            depVM.dependencyVersions = [:]
            depVM.selectedDependencyVersion = [:]
            depVM.isLoadingDependencies = false
            depVM.resetDownloadStates()
            return false
        }
    }

    @MainActor
    static func prepareManualDependenciesThrowing(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        depVM: DependencySheetViewModel
    ) async throws -> Bool {
        guard let gameInfo = gameInfo else {
            throw GlobalError.validation(
                i18nKey: "Game Info Missing",
                level: .notification
            )
        }

        depVM.isLoadingDependencies = true

        let missing = await ModrinthDependencyDownloader.getMissingDependencies(
            for: project.projectId,
            gameInfo: gameInfo
        )

        if missing.isEmpty {
            depVM.isLoadingDependencies = false
            return false
        }

        var versionDict: [String: [ModrinthProjectDetailVersion]] = [:]
        var selectedVersionDict: [String: String] = [:]

        // Use server-side filtering method, consistent with global resource installation logic
        // Preset game versions and loaders
        for dep in missing {
            do {
                // Use the same server-side filtering method as global resource installation
                let filteredVersions = try await ModrinthService.fetchProjectVersionsFilter(
                    id: dep.id,
                    selectedVersions: [gameInfo.gameVersion],
                    selectedLoaders: [gameInfo.modLoader],
                    type: "mod"
                )

                versionDict[dep.id] = filteredVersions
                // Like global resource installation, the first version is automatically selected
                if let firstVersion = filteredVersions.first {
                    selectedVersionDict[dep.id] = firstVersion.id
                }
            } catch {
                // If the version of a dependency fails to be obtained, an error will be logged but other dependencies will continue to be processed
                let globalError = GlobalError.from(error)
                Logger.shared.error("获取依赖 \(dep.title) 的版本失败: \(globalError.chineseMessage)")
                // Set an empty version list to let users know that this dependency cannot be installed
                versionDict[dep.id] = []
            }
        }

        depVM.missingDependencies = missing
        depVM.dependencyVersions = versionDict
        depVM.selectedDependencyVersion = selectedVersionDict
        depVM.isLoadingDependencies = false
        depVM.resetDownloadStates()
        return true
    }

    @MainActor
    static func downloadAllDependenciesAndMain(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        depVM: DependencySheetViewModel,
        query: String,
        gameRepository: GameRepository,
        updateButtonState: @escaping () -> Void
    ) async {
        do {
            try await downloadAllDependenciesAndMainThrowing(
                project: project,
                gameInfo: gameInfo,
                depVM: depVM,
                query: query,
                gameRepository: gameRepository
            )
            updateButtonState()
            depVM.showDependenciesSheet = false
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("下载所有依赖项失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            depVM.overallDownloadState = .failed
        }
    }

    @MainActor
    static func downloadAllDependenciesAndMainThrowing(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        depVM: DependencySheetViewModel,
        query: String,
        gameRepository: GameRepository
    ) async throws {
        guard let gameInfo = gameInfo else {
            throw GlobalError.validation(
                i18nKey: "Game Info Missing",
                level: .notification
            )
        }

        let dependencies = depVM.missingDependencies
        let selectedVersions = depVM.selectedDependencyVersion
        let dependencyVersions = depVM.dependencyVersions

        let allSucceeded =
            await ModrinthDependencyDownloader.downloadManualDependenciesAndMain(
                dependencies: dependencies,
                selectedVersions: selectedVersions,
                dependencyVersions: dependencyVersions,
                mainProjectId: project.projectId,
                mainProjectVersionId: nil,  // Use the latest version
                gameInfo: gameInfo,
                query: query,
                gameRepository: gameRepository,
                onDependencyDownloadStart: { depId in
                    depVM.dependencyDownloadStates[depId] = .downloading
                },
                onDependencyDownloadFinish: { depId, success in
                    depVM.dependencyDownloadStates[depId] =
                        success ? .success : .failed
                }
            )

        if !allSucceeded {
            throw GlobalError.download(
                i18nKey: "Dependencies Failed",
                level: .notification
            )
        }
    }

    @MainActor
    static func downloadMainResourceAfterDependencies(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        depVM: DependencySheetViewModel,
        query: String,
        gameRepository: GameRepository,
        updateButtonState: @escaping () -> Void
    ) async {
        do {
            try await downloadMainResourceAfterDependenciesThrowing(
                project: project,
                gameInfo: gameInfo,
                query: query,
                gameRepository: gameRepository
            )
            updateButtonState()
            depVM.showDependenciesSheet = false
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("下载主资源失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    @MainActor
    static func downloadMainResourceAfterDependenciesThrowing(
        project: ModrinthProject,
        gameInfo: GameVersionInfo?,
        query: String,
        gameRepository: GameRepository
    ) async throws {
        guard let gameInfo = gameInfo else {
            throw GlobalError.validation(
                i18nKey: "Game Info Missing",
                level: .notification
            )
        }

        let (success, _, _) =
            await ModrinthDependencyDownloader.downloadMainResourceOnly(
                mainProjectId: project.projectId,
                gameInfo: gameInfo,
                query: query,
                gameRepository: gameRepository
            )

        if !success {
            throw GlobalError.download(
                i18nKey: "Main Resource Failed",
                level: .notification
            )
        }
    }

    @MainActor
    static func retryDownloadDependency(
        dep: ModrinthProjectDetail,
        gameInfo: GameVersionInfo?,
        depVM: DependencySheetViewModel,
        query: String,
        gameRepository: GameRepository
    ) async {
        do {
            try await retryDownloadDependencyThrowing(
                dep: dep,
                gameInfo: gameInfo,
                depVM: depVM,
                query: query,
                gameRepository: gameRepository
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("重试下载依赖项失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            depVM.dependencyDownloadStates[dep.id] = .failed
        }
    }

    @MainActor
    static func retryDownloadDependencyThrowing(
        dep: ModrinthProjectDetail,
        gameInfo: GameVersionInfo?,
        depVM: DependencySheetViewModel,
        query: String,
        gameRepository: GameRepository
    ) async throws {
        guard let gameInfo = gameInfo else {
            throw GlobalError.validation(
                i18nKey: "Game Info Missing",
                level: .notification
            )
        }

        guard let versionId = depVM.selectedDependencyVersion[dep.id] else {
            throw GlobalError(type: .resource, i18nKey: "Version ID missing",
                level: .notification
            )
        }

        guard let versions = depVM.dependencyVersions[dep.id] else {
            throw GlobalError(type: .resource, i18nKey: "Version info missing",
                level: .notification
            )
        }

        guard let version = versions.first(where: { $0.id == versionId }) else {
            throw GlobalError(type: .resource, i18nKey: "Version not found",
                level: .notification
            )
        }

        guard
            let primaryFile = ModrinthService.filterPrimaryFiles(
                from: version.files
            )
        else {
            throw GlobalError.resource(
                i18nKey: "Primary File Not Found",
                level: .notification
            )
        }

        depVM.dependencyDownloadStates[dep.id] = .downloading

        do {
            let fileURL = try await DownloadManager.downloadResource(
                for: gameInfo,
                urlString: primaryFile.url,
                resourceType: dep.projectType,
                expectedSha1: primaryFile.hashes.sha1
            )

            var resourceToAdd = dep
            resourceToAdd.fileName = primaryFile.filename
            resourceToAdd.type = query

            // If it is a mod, add it to the installation cache
            if query.lowercased() == "mod" {
                // Get the hash of the downloaded file
                if let hash = ModScanner.sha1Hash(of: fileURL) {
                    ModScanner.shared.addModHash(
                        hash,
                        to: gameInfo.gameName
                    )
                }
            }

            depVM.dependencyDownloadStates[dep.id] = .success
        } catch {
            throw GlobalError.download(
                i18nKey: "Dependency Download Failed",
                level: .notification
            )
        }
    }
}
