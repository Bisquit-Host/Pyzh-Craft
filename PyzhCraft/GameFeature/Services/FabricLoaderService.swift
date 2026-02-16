import Foundation

enum FabricLoaderService {

    /// Get all Loader versions (silent versions)
    /// - Parameter minecraftVersion: Minecraft version
    /// - Returns: loader version list, returns empty array on failure
    static func fetchAllLoaderVersions(for minecraftVersion: String) async -> [FabricLoader] {
        do {
            return try await fetchAllLoaderVersionsThrowing(for: minecraftVersion)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Fabric 加载器版本失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    /// Get all Loader versions (throw exception version)
    /// - Parameter minecraftVersion: Minecraft version
    /// - Returns: Loader version list
    /// - Throws: GlobalError when the operation fails
    static func fetchAllLoaderVersionsThrowing(for minecraftVersion: String) async throws -> [FabricLoader] {
        let url = URLConfig.API.Fabric.loader.appendingPathComponent(minecraftVersion)
        // Use a unified API client
        let data = try await APIClient.get(url: url)

        var result: [FabricLoader] = []
        do {
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in jsonArray {
                    let singleData = try JSONSerialization.data(withJSONObject: item)
                    let decoder = JSONDecoder()
                    if let loader = try? decoder.decode(FabricLoader.self, from: singleData) {
                        result.append(loader)
                    }
                }
            }
            return result
        } catch {
            throw GlobalError(type: .validation, i18nKey: "Fabric Loader Parse Failed",
                level: .notification
            )
        }
    }

    /// Get the specified version of Fabric Loader
    /// - Parameters:
    ///   - minecraftVersion: Minecraft version
    ///   - loaderVersion: specified loader version
    /// - Returns: Specified version of loader
    /// - Throws: GlobalError when the operation fails
    static func fetchSpecificLoaderVersion(for minecraftVersion: String, loaderVersion: String) async throws -> ModrinthLoader {
        let cacheKey = "\(minecraftVersion)-\(loaderVersion)"

        // 1. Check the global cache
        if let cached = AppCacheManager.shared.get(namespace: "fabric", key: cacheKey, as: ModrinthLoader.self) {
            return cached
        }

        // 2. Directly download version.json of the specified version
        // Use a unified API client
        let url = URLConfig.API.Modrinth.loaderProfile(loader: "fabric", version: loaderVersion)
        let data = try await APIClient.get(url: url)

        var result = try JSONDecoder().decode(ModrinthLoader.self, from: data)
        result.version = loaderVersion
        result = CommonService.processGameVersionPlaceholders(loader: result, gameVersion: minecraftVersion)
        // 3. Save to cache
        AppCacheManager.shared.setSilently(namespace: "fabric", key: cacheKey, value: result)
        return result
    }

    /// Set the specified version of Fabric loader (silent version)
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
            Logger.shared.error("Fabric 指定版本设置失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    /// Set the specified version of the Fabric loader (throws exception version)
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
        Logger.shared.info("开始设置指定版本的 Fabric 加载器: \(loaderVersion)")

        let fabricProfile = try await fetchSpecificLoaderVersion(for: gameVersion, loaderVersion: loaderVersion)
        let librariesDirectory = AppPaths.librariesDirectory
        let fileManager = CommonFileManager(librariesDir: librariesDirectory)
        fileManager.onProgressUpdate = onProgressUpdate

        await fileManager.downloadFabricJars(libraries: fabricProfile.libraries)

        let classpathString = CommonService.generateFabricClasspath(from: fabricProfile, librariesDir: librariesDirectory)
        let mainClass = fabricProfile.mainClass
        guard let version = fabricProfile.version else {
            throw GlobalError.validation(i18nKey: "Fabric loader version missing",
                level: .notification
            )
        }
        return (loaderVersion: version, classpath: classpathString, mainClass: mainClass)
    }
}

extension FabricLoaderService: ModLoaderHandler {}
