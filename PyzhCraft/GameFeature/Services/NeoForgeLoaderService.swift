import Foundation

enum NeoForgeLoaderService {
    /// Get a collection of version strings for all available NeoForge versions
    static func fetchAllNeoForgeVersions(for minecraftVersion: String) async throws -> LoaderVersion {
        guard let result = await CommonService.fetchAllLoaderVersions(type: "neo", minecraftVersion: minecraftVersion) else {
            throw GlobalError.resource(
                chineseMessage: "未找到 Minecraft \(minecraftVersion) 的 NeoForge 加载器版本",
                i18nKey: "error.resource.neoforge_loader_version_not_found",
                level: .notification
            )
        }
        return result
    }

    /// Get the NeoForge profile of the specified version
    /// - Parameters:
    ///   - minecraftVersion: Minecraft version
    ///   - loaderVersion: specified loader version
    /// - Returns: NeoForge profile of the specified version
    /// - Throws: GlobalError when the operation fails
    static func fetchSpecificNeoForgeProfile(for minecraftVersion: String, loaderVersion: String) async throws -> ModrinthLoader {
        let cacheKey = "\(minecraftVersion)-\(loaderVersion)"

        // 1. Check the global cache
        if let cached = AppCacheManager.shared.get(namespace: "neoforge", key: cacheKey, as: ModrinthLoader.self) {
            return cached
        }

        // 2. Directly download version.json of the specified version
        // Use a unified API client
        let url = URLConfig.API.Modrinth.loaderProfile(loader: "neo", version: loaderVersion)
        let data = try await APIClient.get(url: url)

        var result = try JSONDecoder().decode(ModrinthLoader.self, from: data)
        result = CommonService.processGameVersionPlaceholders(loader: result, gameVersion: minecraftVersion)
        // 3. Save to cache
        result.version = loaderVersion
        AppCacheManager.shared.setSilently(namespace: "neoforge", key: cacheKey, value: result)

        return result
    }

    /// Set a specific version of the NeoForge loader (silent version)
    /// - Parameters:
    ///   - gameVersion: game version
    ///   - loaderVersion: specified loader version
    ///   - gameInfo: game information
    ///   - onProgressUpdate: progress update callback
    /// - Returns: Set the result, return nil on failure
    static func setupWithSpecificVersion(
        for gameVersion: String,
        loaderVersion: String,
        gameInfo: GameVersionInfo,
        onProgressUpdate: @escaping (String, Int, Int) -> Void
    ) async -> (loaderVersion: String, classpath: String, mainClass: String)? {
        do {
            return try await setupWithSpecificVersionThrowing(
                for: gameVersion,
                loaderVersion: loaderVersion,
                gameInfo: gameInfo,
                onProgressUpdate: onProgressUpdate
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("NeoForge 指定版本设置失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    /// Set the specified version of the NeoForge loader (throws exception version)
    /// - Parameters:
    ///   - gameVersion: game version
    ///   - loaderVersion: specified loader version
    ///   - gameInfo: game information
    ///   - onProgressUpdate: progress update callback
    /// - Returns: Set results
    /// - Throws: GlobalError when the operation fails
    static func setupWithSpecificVersionThrowing(
        for gameVersion: String,
        loaderVersion: String,
        gameInfo: GameVersionInfo,
        onProgressUpdate: @escaping (String, Int, Int) -> Void
    ) async throws -> (loaderVersion: String, classpath: String, mainClass: String) {
        Logger.shared.info("开始设置指定版本的 NeoForge 加载器: \(loaderVersion)")

        let neoForgeProfile = try await fetchSpecificNeoForgeProfile(for: gameVersion, loaderVersion: loaderVersion)
        let librariesDirectory = AppPaths.librariesDirectory
        let fileManager = CommonFileManager(librariesDir: librariesDirectory)
        fileManager.onProgressUpdate = onProgressUpdate

        // Step 1: Download all downloadable=true library files
        let downloadableLibraries = neoForgeProfile.libraries.filter { $0.downloads != nil }
        let totalDownloads = downloadableLibraries.count
        await fileManager.downloadForgeJars(libraries: neoForgeProfile.libraries)

        // Step 2: Execute processors (if they exist)
        if let processors = neoForgeProfile.processors, !processors.isEmpty {
            try await fileManager.executeProcessors(
                processors: processors,
                librariesDir: librariesDirectory,
                gameVersion: gameVersion,
                data: neoForgeProfile.data,
                gameName: gameInfo.gameName
            ) { message, currentProcessor, totalProcessors in
                // Convert processor progress messages to download progress format
                // Total number of tasks = number of downloads + number of processors
                let totalTasks = totalDownloads + totalProcessors
                let completedTasks = totalDownloads + currentProcessor
                onProgressUpdate(message, completedTasks, totalTasks)
            }
        }

        let classpathString = CommonService.generateClasspath(from: neoForgeProfile, librariesDir: librariesDirectory)
        let mainClass = neoForgeProfile.mainClass

        guard let version = neoForgeProfile.version else {
            throw GlobalError.resource(
                chineseMessage: "NeoForge profile 缺少版本信息",
                i18nKey: "error.resource.neoforge_missing_version",
                level: .notification
            )
        }

        return (loaderVersion: version, classpath: classpathString, mainClass: mainClass)
    }
}

extension NeoForgeLoaderService: ModLoaderHandler {}
