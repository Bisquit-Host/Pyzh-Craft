import Foundation

enum QuiltLoaderService {

    /// Get all Loader versions (silent versions)
    /// - Parameter minecraftVersion: Minecraft version
    /// - Returns: loader version list, returns empty array on failure
    static func fetchAllQuiltLoaders(for minecraftVersion: String) async -> [QuiltLoaderResponse] {
        do {
            return try await fetchAllQuiltLoadersThrowing(for: minecraftVersion)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Fabric 加载器版本失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    /// Get all available Quilt Loader versions
    static func fetchAllQuiltLoadersThrowing(for minecraftVersion: String) async throws -> [QuiltLoaderResponse] {
        let url = URLConfig.API.Quilt.loaderBase.appendingPathComponent(minecraftVersion)
        // Use a unified API client
        let data = try await APIClient.get(url: url)
        let decoder = JSONDecoder()
        let allLoaders = try decoder.decode([QuiltLoaderResponse].self, from: data)
        return allLoaders.filter { !$0.loader.version.lowercased().contains("beta") && !$0.loader.version.lowercased().contains("pre") }
    }

    /// Get the specified version of Quilt Loader
    /// - Parameters:
    ///   - minecraftVersion: Minecraft version
    ///   - loaderVersion: specified loader version
    /// - Returns: Specified version of loader
    /// - Throws: GlobalError when the operation fails
    static func fetchSpecificLoaderVersion(for minecraftVersion: String, loaderVersion: String) async throws -> ModrinthLoader {
        let cacheKey = "\(minecraftVersion)-\(loaderVersion)"

        // 1. Check the global cache
        if let cached = AppCacheManager.shared.get(namespace: "quilt", key: cacheKey, as: ModrinthLoader.self) {
            return cached
        }

        // 2. Directly download version.json of the specified version
        // Use a unified API client
        let url = URLConfig.API.Modrinth.loaderProfile(loader: "quilt", version: loaderVersion)
        let data = try await APIClient.get(url: url)

        var result = try JSONDecoder().decode(ModrinthLoader.self, from: data)
        result.version = loaderVersion
        result = CommonService.processGameVersionPlaceholders(loader: result, gameVersion: minecraftVersion)
        // 3. Save to cache
        AppCacheManager.shared.setSilently(namespace: "quilt", key: cacheKey, value: result)

        return result
    }

    /// Set the specified version of the Quilt loader (silent version)
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
            Logger.shared.error("Quilt 指定版本设置失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    /// Set the specified version of the Quilt loader (throws exception version)
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
        Logger.shared.info("开始设置指定版本的 Quilt 加载器: \(loaderVersion)")

        let quiltProfile = try await fetchSpecificLoaderVersion(for: gameVersion, loaderVersion: loaderVersion)
        let librariesDirectory = AppPaths.librariesDirectory
        let fileManager = CommonFileManager(librariesDir: librariesDirectory)
        fileManager.onProgressUpdate = onProgressUpdate

        await fileManager.downloadFabricJars(libraries: quiltProfile.libraries)

        let classpathString = CommonService.generateFabricClasspath(from: quiltProfile, librariesDir: librariesDirectory)
        let mainClass = quiltProfile.mainClass
        guard let version = quiltProfile.version else {
            throw GlobalError.resource(
                chineseMessage: "Quilt profile 缺少版本信息",
                i18nKey: "error.resource.quilt_missing_version",
                level: .notification
            )
        }
        return (loaderVersion: version, classpath: classpathString, mainClass: mainClass)
    }
}

extension QuiltLoaderService: ModLoaderHandler {}
