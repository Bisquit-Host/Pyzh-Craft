import Foundation

enum ForgeLoaderService {
    /// Get all available Forge version details via Modrinth API
    static func fetchAllForgeVersions(for minecraftVersion: String) async throws -> LoaderVersion {
        guard let result = await CommonService.fetchAllLoaderVersions(type: "forge", minecraftVersion: minecraftVersion) else {
            throw GlobalError.resource(
                chineseMessage: "未找到 Minecraft \(minecraftVersion) 的 Forge 加载器版本",
                i18nKey: "Forge Loader Version Not Found",
                level: .notification
            )
        }
        return result
    }

    /// Get the specified version of Forge profile
    /// - Parameters:
    ///   - minecraftVersion: Minecraft version
    ///   - loaderVersion: specified loader version
    /// - Returns: Forge profile of the specified version
    /// - Throws: GlobalError when the operation fails
    static func fetchSpecificForgeProfile(for minecraftVersion: String, loaderVersion: String) async throws -> ModrinthLoader {
        let cacheKey = "\(minecraftVersion)-\(loaderVersion)"

        // 1. Check the global cache
        if let cached = AppCacheManager.shared.get(namespace: "forge", key: cacheKey, as: ModrinthLoader.self) {
            return cached
        }

        // 2. Directly download version.json of the specified version
        // Use a unified API client
        let url = URLConfig.API.Modrinth.loaderProfile(loader: "forge", version: loaderVersion)
        let data = try await APIClient.get(url: url)

        var result = try JSONDecoder().decode(ModrinthLoader.self, from: data)
        result = CommonService.processGameVersionPlaceholders(loader: result, gameVersion: minecraftVersion)
        result.version = loaderVersion
        // 3. Save to cache
        AppCacheManager.shared.setSilently(namespace: "forge", key: cacheKey, value: result)

        return result
    }

    /// Set the specified version of the Forge loader (silent version)
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
            Logger.shared.error("Forge 指定版本设置失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    /// Set the specified version of the Forge loader (throws exception version)
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
        Logger.shared.info("开始设置指定版本的 Forge 加载器: \(loaderVersion)")

        let forgeProfile = try await fetchSpecificForgeProfile(for: gameVersion, loaderVersion: loaderVersion)
        let librariesDirectory = AppPaths.librariesDirectory
        let fileManager = CommonFileManager(librariesDir: librariesDirectory)
        fileManager.onProgressUpdate = onProgressUpdate

        // Step 1: Download all downloadable=true library files
        let downloadableLibraries = forgeProfile.libraries.filter { $0.downloads != nil }
        let totalDownloads = downloadableLibraries.count
        await fileManager.downloadForgeJars(libraries: forgeProfile.libraries)

        // Step 2: Execute processors (if they exist)
        if let processors = forgeProfile.processors, !processors.isEmpty {
            // Use the original data field from version.json
            try await fileManager.executeProcessors(
                processors: processors,
                librariesDir: librariesDirectory,
                gameVersion: gameVersion,
                data: forgeProfile.data,
                gameName: gameInfo.gameName
            ) { message, currentProcessor, totalProcessors in
                    // Convert processor progress messages to download progress format
                    // Total number of tasks = number of downloads + number of processors
                    let totalTasks = totalDownloads + totalProcessors
                    let completedTasks = totalDownloads + currentProcessor
                    onProgressUpdate(message, completedTasks, totalTasks)
            }
        }

        let classpathString = CommonService.generateClasspath(from: forgeProfile, librariesDir: librariesDirectory)
        let mainClass = forgeProfile.mainClass
        guard let version = forgeProfile.version else {
            throw GlobalError.resource(
                chineseMessage: "Forge profile 缺少版本信息",
                i18nKey: "Missing Forge version",
                level: .notification
            )
        }
        return (loaderVersion: version, classpath: classpathString, mainClass: mainClass)
    }
}

extension ForgeLoaderService: ModLoaderHandler {}
