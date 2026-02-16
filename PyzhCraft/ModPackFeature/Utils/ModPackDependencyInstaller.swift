import Foundation

/// The integration package depends on the installation service
/// Responsible for installing all required dependencies defined in the integration package
enum ModPackDependencyInstaller {

    // MARK: - Download Type
    enum DownloadType {
        case files, dependencies, overrides
    }

    // MARK: - Main Installation Method

    /// Install all required dependencies for the modpack version
    /// - Parameters:
    ///   - indexInfo: parsed integration package index information
    ///   - gameInfo: game information
    ///   - extractedPath: the path after decompression
    ///   - onProgressUpdate: progress update callback
    /// - Returns: Whether the installation was successful
    static func installVersionDependencies(
        indexInfo: ModrinthIndexInfo,
        gameInfo: GameVersionInfo,
        extractedPath: URL? = nil,
        onProgressUpdate: ((String, Int, Int, DownloadType) -> Void)? = nil
    ) async -> Bool {
        // Get resource directory
        let resourceDir = AppPaths.profileDirectory(gameName: gameInfo.gameName)

        // Concurrently execute the installation of files and dependencies
        async let filesResult = installModPackFiles(
            files: indexInfo.files,
            resourceDir: resourceDir,
            gameInfo: gameInfo,
            onProgressUpdate: onProgressUpdate
        )

        async let dependenciesResult = installModPackDependencies(
            dependencies: indexInfo.dependencies,
            gameInfo: gameInfo,
            resourceDir: resourceDir,
            onProgressUpdate: onProgressUpdate
        )

        // Wait for both tasks to complete
        let (filesSuccess, dependenciesSuccess) = await (filesResult, dependenciesResult)

        // Check results
        if !filesSuccess {
            Logger.shared.error("整合包文件安装失败")
            return false
        }

        if !dependenciesSuccess {
            Logger.shared.error("整合包依赖安装失败")
            return false
        }

        return true
    }

    // MARK: - File Installation

    /// Install integration package files
    /// - Parameters:
    ///   - files: file list
    ///   - resourceDir: resource directory
    ///   - gameInfo: game information
    ///   - onProgressUpdate: progress update callback
    /// - Returns: Whether the installation was successful
    static func installModPackFiles(
        files: [ModrinthIndexFile],
        resourceDir: URL,
        gameInfo: GameVersionInfo,
        onProgressUpdate: ((String, Int, Int, DownloadType) -> Void)?
    ) async -> Bool {
        // Filter out the files that need to be downloaded
        let filesToDownload = filterDownloadableFiles(files)

        // Notification to start downloading
        onProgressUpdate?("Starting to download modpack files".localized(), 0, filesToDownload.count, .files)

        // Create a semaphore to control the number of concurrencies
        let semaphore = AsyncSemaphore(value: GeneralSettingsManager.shared.concurrentDownloads)

        // Use a counter to track the number of files completed
        let completedCount = ModPackCounter()

        // Use TaskGroup to download files concurrently
        let results = await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, file) in filesToDownload.enumerated() {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    // Optimization: Download files (autoreleasepool has been used internally to optimize)
                    let success = await downloadSingleFile(file: file, resourceDir: resourceDir, gameInfo: gameInfo)

                    // update progress
                    if success {
                        let currentCount = completedCount.increment()
                        onProgressUpdate?(file.path, currentCount, filesToDownload.count, .files)
                    }

                    return (index, success)
                }
            }

            // Collect results
            var results: [(Int, Bool)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 } // Sort by index
        }

        // Check if all downloads are successful
        let successCount = results.filter { $0.1 }.count
        let failedCount = results.count - successCount

        if failedCount > 0 {
            Logger.shared.error("有 \(failedCount) 个文件下载失败")
            return false
        }

        // Notification download completed
        onProgressUpdate?("Modpack files download completed".localized(), filesToDownload.count, filesToDownload.count, .files)

        return true
    }

    /// Filter downloadable files
    /// - Parameter files: file list
    /// - Returns: filtered file list
    private static func filterDownloadableFiles(_ files: [ModrinthIndexFile]) -> [ModrinthIndexFile] {
        return files.filter { file in
            // Only check the client field, ignore the server
            if let env = file.env, let client = env.client, client.lowercased() == "unsupported" {
                return false
            }
            return true
        }
    }

    /// Download a single file
    /// - Parameters:
    ///   - file: file information
    ///   - resourceDir: resource directory
    ///   - gameInfo: game information (optional, used for compatibility check)
    /// - Returns: Whether the download is successful
    private static func downloadSingleFile(file: ModrinthIndexFile, resourceDir: URL, gameInfo: GameVersionInfo? = nil) async -> Bool {
        // Check if it is a CurseForge file (needs to delay getting details)
        if file.source == .curseforge,
           let projectId = file.curseForgeProjectId,
           let fileId = file.curseForgeFileId {
            // CurseForge Files: Get real file details when downloading
            return await downloadCurseForgeFile(
                projectId: projectId,
                fileId: fileId,
                resourceDir: resourceDir,
                gameInfo: gameInfo
            )
        } else {
            // Modrinth file: use original logic
            return await downloadModrinthFile(file: file, resourceDir: resourceDir)
        }
    }

    /// Download CurseForge files (concurrently obtain file details)
    /// - Parameters:
    ///   - projectId: project ID
    ///   - fileId: file ID
    ///   - resourceDir: resource directory
    ///   - gameInfo: game information (optional, used for compatibility check)
    /// - Returns: Whether the download is successful
    private static func downloadCurseForgeFile(projectId: Int, fileId: Int, resourceDir: URL, gameInfo: GameVersionInfo? = nil) async -> Bool {
        // Concurrently obtain file details and module details to reduce repeated requests
        async let fileDetailTask = CurseForgeService.fetchFileDetail(projectId: projectId, fileId: fileId)
        async let modDetailTask: CurseForgeModDetail? = try? await CurseForgeService.fetchModDetailThrowing(modId: projectId)

        let fileDetail = await fileDetailTask
        let modDetail = await modDetailTask

        // Preferred specified file (if details exist)
        if let fileDetail = fileDetail {
            if await downloadCurseForgeFileWithDetail(
                fileDetail: fileDetail,
                projectId: projectId,
                resourceDir: resourceDir,
                modDetail: modDetail
            ) {
                return true
            }
        }

        // Main policy failed or download failed, fallback matches by version/loader
        return await downloadCurseForgeFileWithFallback(
            projectId: projectId,
            resourceDir: resourceDir,
            gameInfo: gameInfo,
            modDetail: modDetail
        )
    }

    /// Use alternate strategy to download CurseForge files (exactly match game version and loader)
    /// - Parameters:
    ///   - projectId: project ID
    ///   - resourceDir: resource directory
    ///   - gameInfo: game information (optional, used for compatibility check)
    /// - Returns: Whether the download is successful
    private static func downloadCurseForgeFileWithFallback(projectId: Int, resourceDir: URL, gameInfo: GameVersionInfo?, modDetail: CurseForgeModDetail? = nil) async -> Bool {
        // Game information is required for exact matching
        guard let gameInfo = gameInfo else {
            Logger.shared.error("缺少游戏信息，无法进行文件过滤: \(projectId)")
            return false
        }

        // Exactly match game version and loader
        let modLoaderTypeValue = CurseForgeModLoaderType.from(gameInfo.modLoader)?.rawValue
        let filteredFiles: [CurseForgeModFileDetail]

        if let modDetail = modDetail {
            // Reuse the obtained module details to avoid repeated network requests
            filteredFiles = filterFiles(
                from: modDetail,
                projectId: projectId,
                gameVersion: gameInfo.gameVersion,
                modLoaderType: modLoaderTypeValue
            )
        } else {
            // Return to the original logic when network requests are still needed
            guard let files = await CurseForgeService.fetchProjectFiles(
                projectId: projectId,
                gameVersion: gameInfo.gameVersion,
                modLoaderType: modLoaderTypeValue
            ) else {
                Logger.shared.error("精确匹配失败，未找到兼容文件: \(projectId)")
                return false
            }
            filteredFiles = files
        }

        guard !filteredFiles.isEmpty else {
            Logger.shared.error("精确匹配失败，未找到兼容文件: \(projectId)")
            return false
        }

        if let fileToDownload = filteredFiles.first {
            return await downloadCurseForgeFileWithDetail(
                fileDetail: fileToDownload,
                projectId: projectId,
                resourceDir: resourceDir,
                modDetail: modDetail
            )
        }

        Logger.shared.error("未找到可下载的文件: \(projectId)")
        return false
    }

    /// Download CurseForge files using file details
    /// - Parameters:
    ///   - fileDetail: file details
    ///   - projectId: project ID
    ///   - resourceDir: resource directory
    /// - Returns: Whether the download is successful
    private static func downloadCurseForgeFileWithDetail(
        fileDetail: CurseForgeModFileDetail,
        projectId: Int,
        resourceDir: URL,
        modDetail: CurseForgeModDetail? = nil
    ) async -> Bool {
        do {
            // Confirm download URL
            let downloadUrl: String
            if let directUrl = fileDetail.downloadUrl, !directUrl.isEmpty {
                downloadUrl = directUrl
            } else {
                // Use configured alternative download address
                downloadUrl = URLConfig.API.CurseForge.fallbackDownloadUrl(fileId: fileDetail.id, fileName: fileDetail.fileName).absoluteString
            }

            // Determine subdirectories based on file details (give priority to the obtained module details to avoid repeated requests)
            let effectiveModDetail: CurseForgeModDetail
            if let modDetail = modDetail {
                effectiveModDetail = modDetail
            } else {
                effectiveModDetail = try await CurseForgeService.fetchModDetailThrowing(modId: projectId)
            }

            let subDirectory = effectiveModDetail.directoryName
            let destinationPath = resourceDir.appendingPathComponent(subDirectory).appendingPathComponent(fileDetail.fileName)

            // Make sure the directory exists
            try FileManager.default.createDirectory(
                at: destinationPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Download file
            let downloadedFile = try await DownloadManager.downloadFile(
                urlString: downloadUrl,
                destinationURL: destinationPath,
                expectedSha1: fileDetail.hash?.value
            )

            // Write to Modrinth style cache (using existing CF→Modrinth conversion interface)
            if let hash = ModScanner.sha1Hash(of: downloadedFile) {
                // Convert CurseForge project details to ModrinthProjectDetail
                if let cfAsModrinth = CurseForgeToModrinthAdapter.convert(effectiveModDetail) {
                    var detailWithFile = cfAsModrinth
                    detailWithFile.fileName = fileDetail.fileName
                    detailWithFile.type = "mod"
                    ModScanner.shared.saveToCache(hash: hash, detail: detailWithFile)
                }
            }

            return true
        } catch {
            Logger.shared.error("下载 CurseForge 文件失败: \(fileDetail.fileName)")
            return false
        }
    }

    /// Filter files based on acquired module details to avoid additional network requests
    private static func filterFiles(
        from modDetail: CurseForgeModDetail,
        projectId: Int,
        gameVersion: String?,
        modLoaderType: Int?
    ) -> [CurseForgeModFileDetail] {
        var files: [CurseForgeModFileDetail] = []

        if let latestFiles = modDetail.latestFiles, !latestFiles.isEmpty {
            files = latestFiles
        } else if let latestFilesIndexes = modDetail.latestFilesIndexes, !latestFilesIndexes.isEmpty {
            var fileIndexMap: [Int: [CurseForgeFileIndex]] = [:]
            for index in latestFilesIndexes {
                fileIndexMap[index.fileId, default: []].append(index)
            }

            for (fileId, indexes) in fileIndexMap {
                guard let firstIndex = indexes.first else { continue }
                let gameVersions = indexes.map { $0.gameVersion }
                let downloadUrl = URLConfig.API.CurseForge.fallbackDownloadUrl(
                    fileId: fileId,
                    fileName: firstIndex.filename
                ).absoluteString

                let fileDetail = CurseForgeModFileDetail(
                    id: fileId,
                    displayName: firstIndex.filename,
                    fileName: firstIndex.filename,
                    downloadUrl: downloadUrl,
                    fileDate: "",
                    releaseType: firstIndex.releaseType,
                    gameVersions: gameVersions,
                    dependencies: nil,
                    changelog: nil,
                    fileLength: nil,
                    hash: nil,
                    hashes: nil,
                    modules: nil,
                    projectId: projectId,
                    projectName: modDetail.name,
                    authors: modDetail.authors
                )
                files.append(fileDetail)
            }
        }

        // gameVersion filter
        if let gameVersion = gameVersion {
            files = files.filter { $0.gameVersions.contains(gameVersion) }
        }

        // modLoaderType filtering (depends on latestFilesIndexes information)
        if let modLoaderType = modLoaderType,
           let latestFilesIndexes = modDetail.latestFilesIndexes {
            let matchingIds = Set(
                latestFilesIndexes
                    .filter { $0.modLoader == modLoaderType }
                    .map { $0.fileId }
            )
            files = files.filter { matchingIds.contains($0.id) }
        }

        return files
    }

    /// Download Modrinth files
    /// - Parameters:
    ///   - file: file information
    ///   - resourceDir: resource directory
    /// - Returns: Whether the download is successful
    private static func downloadModrinthFile(file: ModrinthIndexFile, resourceDir: URL) async -> Bool {
        guard let urlString = file.downloads.first, !urlString.isEmpty else {
            Logger.shared.error("文件无可用下载链接: \(file.path)")
            return false
        }

        do {
            // Optimization: Pre-calculate the target path to avoid repeated creation
            // Use autoreleasepool to wrap the synchronization part and release temporary objects in time
            let destinationPath = autoreleasepool {
                resourceDir.appendingPathComponent(file.path)
            }

            // DownloadManager.downloadFile already contains autoreleasepool
            let downloadedFile = try await DownloadManager.downloadFile(
                urlString: urlString,
                destinationURL: destinationPath,
                expectedSha1: file.hashes["sha1"]
            )

            // Save to cache
            if let hash = ModScanner.sha1Hash(of: downloadedFile) {
                // Use fetchModrinthDetail to get real project details
                await withCheckedContinuation { continuation in
                    ModrinthService.fetchModrinthDetail(by: hash) { projectDetail in
                        if let detail = projectDetail {
                            // Add file information to detail
                            var detailWithFile = detail
                            detailWithFile.fileName = (file.path as NSString).lastPathComponent
                            detailWithFile.type = "mod"

                            // cache
                            ModScanner.shared.saveToCache(hash: hash, detail: detailWithFile)
                        }
                        continuation.resume()
                    }
                }
            }

            return true
        } catch {
            Logger.shared.error("下载文件失败: \(file.path)")
            return false
        }
    }

    // MARK: - Dependency Installation

    /// Install integration package dependencies
    /// - Parameters:
    ///   - dependencies: dependency list
    ///   - gameInfo: game information
    ///   - resourceDir: resource directory
    ///   - onProgressUpdate: progress update callback
    /// - Returns: Whether the installation was successful
    static func installModPackDependencies(
        dependencies: [ModrinthIndexProjectDependency],
        gameInfo: GameVersionInfo,
        resourceDir: URL,
        onProgressUpdate: ((String, Int, Int, DownloadType) -> Void)?
    ) async -> Bool {
        // Filter out required dependencies
        let requiredDependencies = dependencies.filter { $0.dependencyType == "required" }

        // Notification to start downloading
        onProgressUpdate?("Starting to install modpack dependencies".localized(), 0, requiredDependencies.count, .dependencies)

        // Create a semaphore to control the number of concurrencies
        let semaphore = AsyncSemaphore(value: GeneralSettingsManager.shared.concurrentDownloads)

        // Use counters to track the number of completed dependencies
        let completedCount = ModPackCounter()

        // Use TaskGroup to install dependencies concurrently
        let results = await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, dep) in requiredDependencies.enumerated() {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    // Check if you need to skip
                    if await shouldSkipDependency(dep: dep, gameInfo: gameInfo, resourceDir: resourceDir) {
                        // Skip also update progress
                        let currentCount = completedCount.increment()
                        onProgressUpdate?("Skipping already installed dependency".localized(), currentCount, requiredDependencies.count, .dependencies)
                        return (index, true) // Skip as success
                    }

                    // Install dependencies
                    let success = await installDependency(dep: dep, gameInfo: gameInfo, resourceDir: resourceDir)

                    // update progress
                    if success {
                        let currentCount = completedCount.increment()
                        let dependencyName = dep.projectId ?? "未知依赖"
                        onProgressUpdate?(dependencyName, currentCount, requiredDependencies.count, .dependencies)
                    }

                    return (index, success)
                }
            }

            // Collect results
            var results: [(Int, Bool)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 } // Sort by index
        }

        // Check if all installations were successful
        let successCount = results.filter { $0.1 }.count
        let failedCount = results.count - successCount

        if failedCount > 0 {
            Logger.shared.error("有 \(failedCount) 个依赖安装失败")
            return false
        }

        // Notification that installation is complete
        onProgressUpdate?("Modpack dependencies installation completed".localized(), requiredDependencies.count, requiredDependencies.count, .dependencies)

        return true
    }

    /// Check if dependencies need to be skipped
    /// - Parameters:
    ///   - dep: dependency information
    ///   - gameInfo: game information
    ///   - resourceDir: resource directory
    /// - Returns: Whether to skip
    private static func shouldSkipDependency(
        dep: ModrinthIndexProjectDependency,
        gameInfo: GameVersionInfo,
        resourceDir: URL
    ) async -> Bool {
        // Skip Fabric API installation on Quilt
        if dep.projectId == "P7dR8mSH" && gameInfo.modLoader.lowercased() == "quilt" {
            return true
        }

        // Check if it is installed (using hash)
        if let projectId = dep.projectId {
            // Get project version information to get file hash
            if let versionId = dep.versionId {
                // If there is a specified version ID, get the version directly
                if let version = try? await ModrinthService.fetchProjectVersionThrowing(id: versionId),
                   let primaryFile = ModrinthService.filterPrimaryFiles(from: version.files) {
                    if ModScanner.shared.isModInstalledSync(hash: primaryFile.hashes.sha1, in: resourceDir) {
                        return true
                    }
                }
            } else {
                // Otherwise get compatible version
                let versions = try? await ModrinthService.fetchProjectVersionsFilter(
                    id: projectId,
                    selectedVersions: [gameInfo.gameVersion],
                    selectedLoaders: [gameInfo.modLoader],
                    type: "mod"
                )
                if let version = versions?.first,
                   let primaryFile = ModrinthService.filterPrimaryFiles(from: version.files) {
                    if ModScanner.shared.isModInstalledSync(hash: primaryFile.hashes.sha1, in: resourceDir) {
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: - Overrides Installation

    /// Install the overrides folder contents
    /// - Parameters:
    ///   - extractedPath: the path after decompression
    ///   - resourceDir: resource directory
    ///   - onProgressUpdate: progress update callback
    /// - Returns: Whether the installation was successful
    static func installOverrides(
        extractedPath: URL,
        resourceDir: URL,
        onProgressUpdate: ((String, Int, Int, DownloadType) -> Void)?
    ) async -> Bool {
        // Check Modrinth format overrides first
        var overridesPath = extractedPath.appendingPathComponent("overrides")

        // If not present, check the CurseForge format overrides folder
        if !FileManager.default.fileExists(atPath: overridesPath.path) {
            // CurseForge formats may use different overrides pathnames
            let possiblePaths = [
                "overrides",
                "Override",
                "override",
            ]

            var foundPath: URL?
            for pathName in possiblePaths {
                let testPath = extractedPath.appendingPathComponent(pathName)
                if FileManager.default.fileExists(atPath: testPath.path) {
                    foundPath = testPath
                    break
                }
            }

            if let found = foundPath {
                overridesPath = found
            } else {
                // If there is no overrides folder, return success directly
                return true
            }
        }

        do {
            // Count the total number of files first so you can be notified of progress when you start
            let allFiles = try InstanceFileCopier.getAllFiles(in: overridesPath)
            let totalFiles = allFiles.count

            // If there are no files to be merged, success will be returned directly (no progress bar will be displayed)
            guard totalFiles > 0 else {
                return true
            }

            // Use a unified method of merging folders
            try await InstanceFileCopier.copyDirectory(
                from: overridesPath,
                to: resourceDir,
                fileFilter: nil  // overrides does not require filter files
            ) { fileName, completed, total in
                // Pass progress updates to the unified progress callback interface
                onProgressUpdate?(fileName, completed, total, .overrides)
            }

            return true
        } catch {
            Logger.shared.error("处理 overrides 文件夹失败: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Methods

    /// Install a single dependency
    /// - Parameters:
    ///   - dep: dependency information
    ///   - gameInfo: game information
    ///   - resourceDir: resource directory
    /// - Returns: Whether the installation was successful
    private static func installDependency(
        dep: ModrinthIndexProjectDependency,
        gameInfo: GameVersionInfo,
        resourceDir: URL
    ) async -> Bool {
        guard let projectId = dep.projectId else {
            Logger.shared.error("依赖缺少项目ID")
            return false
        }

        // Modrinth format: use original logic
        if let versionId = dep.versionId {
            // If a version ID is specified, use that version directly
            return await addProjectFromVersion(
                projectId: projectId,
                versionId: versionId,
                gameInfo: gameInfo,
                resourceDir: resourceDir
            )
        } else {
            // If no version ID is specified, get the latest compatible version
            return await addProjectFromLatestVersion(
                projectId: projectId,
                gameInfo: gameInfo,
                resourceDir: resourceDir
            )
        }
    }

    /// Install project from specified version
    /// - Parameters:
    ///   - projectId: project ID
    ///   - versionId: version ID
    ///   - gameInfo: game information
    ///   - resourceDir: resource directory
    /// - Returns: Whether the installation was successful
    private static func addProjectFromVersion(
        projectId: String,
        versionId: String,
        gameInfo: GameVersionInfo,
        resourceDir: URL
    ) async -> Bool {
        do {
            // Get version details
            let version = try await ModrinthService.fetchProjectVersionThrowing(id: versionId)

            // Check version compatibility
            guard version.gameVersions.contains(gameInfo.gameVersion) &&
                  version.loaders.contains(gameInfo.modLoader) else {
                Logger.shared.error("版本不兼容: \(versionId)")
                return false
            }

            // Get project details
            let projectDetail = try await ModrinthService.fetchProjectDetailsThrowing(id: projectId)

            // Download and install
            return await downloadAndInstallVersion(
                version: version,
                projectDetail: projectDetail,
                gameInfo: gameInfo,
                resourceDir: resourceDir
            )
        } catch {
            Logger.shared.error("获取版本详情失败")
            return false
        }
    }

    /// Install the project from the latest compatible version
    /// - Parameters:
    ///   - projectId: project ID
    ///   - gameInfo: game information
    ///   - resourceDir: resource directory
    /// - Returns: Whether the installation was successful
    private static func addProjectFromLatestVersion(
        projectId: String,
        gameInfo: GameVersionInfo,
        resourceDir: URL
    ) async -> Bool {
        do {
            // Get project details
            let projectDetail = try await ModrinthService.fetchProjectDetailsThrowing(id: projectId)

            // Get all versions
            let versions = try await ModrinthService.fetchProjectVersionsThrowing(id: projectId)

            // Sort by release date to find the latest compatible version
            let sortedVersions = versions.sorted { $0.datePublished > $1.datePublished }

            let latestCompatibleVersion = sortedVersions.first { version in
                version.gameVersions.contains(gameInfo.gameVersion) &&
                version.loaders.contains(gameInfo.modLoader)
            }

            guard let latestVersion = latestCompatibleVersion else {
                Logger.shared.error("未找到兼容版本: \(projectId)")
                return false
            }

            // Download and install
            return await downloadAndInstallVersion(
                version: latestVersion,
                projectDetail: projectDetail,
                gameInfo: gameInfo,
                resourceDir: resourceDir
            )
        } catch {
            Logger.shared.error("获取项目详情失败")
            return false
        }
    }

    /// Download and install version
    /// - Parameters:
    ///   - version: version information
    ///   - projectDetail: project details
    ///   - gameInfo: game information
    ///   - resourceDir: resource directory
    /// - Returns: Whether the installation was successful
    private static func downloadAndInstallVersion(
        version: ModrinthProjectDetailVersion,
        projectDetail: ModrinthProjectDetail,
        gameInfo: GameVersionInfo,
        resourceDir: URL
    ) async -> Bool {
        do {
            // Get main file
            guard let primaryFile = ModrinthService.filterPrimaryFiles(from: version.files) else {
                Logger.shared.error("未找到主文件: \(version.id)")
                return false
            }

            // Download file
            let downloadedFile = try await DownloadManager.downloadResource(
                for: gameInfo,
                urlString: primaryFile.url,
                resourceType: "mod",
                expectedSha1: primaryFile.hashes.sha1
            )

            // Save to cache
            if let hash = ModScanner.sha1Hash(of: downloadedFile) {
                // Create a cache using the project details passed in
                var detailWithFile = projectDetail
                detailWithFile.fileName = primaryFile.filename
                detailWithFile.type = "mod"
                ModScanner.shared.saveToCache(hash: hash, detail: detailWithFile)
            }

            return true
        } catch {
            Logger.shared.error("下载依赖失败")
            return false
        }
    }
}

// MARK: - Thread-safe Counter
final class ModPackCounter {
    private var count = 0
    private let lock = NSLock()

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        count = 0
    }
}
