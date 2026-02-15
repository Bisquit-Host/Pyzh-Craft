import Foundation

// MARK: - JSONDecoder Extension for Modrinth Date Handling
private extension JSONDecoder {
    /// Configures the decoder with Modrinth's custom date decoding strategy
    func configureForModrinth() {
        self.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)

            if let date = formatter.date(from: dateStr) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(dateStr)"
            )
        }
    }
}

enum ModrinthService {

    static func fetchVersionInfo(from version: String) async throws -> MinecraftVersionManifest {
        let cacheKey = "version_info_\(version)"

        // Check cache
        if let cachedVersionInfo: MinecraftVersionManifest = AppCacheManager.shared.get(namespace: "version_info", key: cacheKey, as: MinecraftVersionManifest.self) {
            return cachedVersionInfo
        }

        // Get version information from API
        let versionInfo = try await fetchVersionInfoThrowing(from: version)

        // Cache the entire version information
        AppCacheManager.shared.setSilently(
            namespace: "version_info",
            key: cacheKey,
            value: versionInfo
        )

        return versionInfo
    }

    static func queryVersionTime(from version: String) async -> String {
        let cacheKey = "version_time_\(version)"

        // Check cache
        if let cachedTime: String = AppCacheManager.shared.get(namespace: "version_time", key: cacheKey, as: String.self) {
            return cachedTime
        }

        do {
            // Use cached version information to avoid repeated API calls
            let versionInfo = try await Self.fetchVersionInfo(from: version)
            let formattedTime = CommonUtil.formatRelativeTime(versionInfo.releaseTime)

            // Cache version time information
            AppCacheManager.shared.setSilently(
                namespace: "version_time",
                key: cacheKey,
                value: formattedTime
            )
            return formattedTime
        } catch {
            return ""
        }
    }

    static func fetchVersionInfoThrowing(from version: String) async throws -> MinecraftVersionManifest {
        let url = URLConfig.API.Modrinth.versionInfo(version: version)

        // Use a unified API client
        let data = try await APIClient.get(url: url)

        do {
            let decoder = JSONDecoder()
            decoder.configureForModrinth()
            let versionInfo = try decoder.decode(MinecraftVersionManifest.self, from: data)
            return versionInfo
        } catch {
            if error is GlobalError {
                throw error
            } else {
                throw GlobalError.validation(
                    chineseMessage: "解析版本信息失败",
                    i18nKey: "error.validation.version_info_parse_failed",
                    level: .notification
                )
            }
        }
    }

    static func searchProjects(
        facets: [[String]]? = nil,
        offset: Int = 0,
        limit: Int,
        query: String?
    ) async -> ModrinthResult {
        return await Task {
            try await searchProjectsThrowing(
                facets: facets,
                index: AppConstants.modrinthIndex,
                offset: offset,
                limit: limit,
                query: query
            )
        }.catching { error in
            let globalError = GlobalError.from(error)
            Logger.shared.error("搜索 Modrinth 项目失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return ModrinthResult(hits: [], offset: offset, limit: limit, totalHits: 0)
        }
    }

    static func searchProjectsThrowing(
        facets: [[String]]? = nil,
        index: String,
        offset: Int = 0,
        limit: Int,
        query: String?
    ) async throws -> ModrinthResult {
        guard var components = URLComponents(
            url: URLConfig.API.Modrinth.search,
            resolvingAgainstBaseURL: true
        ) else {
            throw GlobalError.validation(
                chineseMessage: "构建URLComponents失败",
                i18nKey: "error.validation.url_components_build_failed",
                level: .notification
            )
        }
        var queryItems = [
            URLQueryItem(name: "index", value: index),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(min(limit, 100))),
        ]
        if let query = query {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        if let facets = facets {
            do {
                let facetsJson = try JSONEncoder().encode(facets)
                if let facetsString = String(data: facetsJson, encoding: .utf8) {
                    queryItems.append(
                        URLQueryItem(name: "facets", value: facetsString)
                    )
                }
            } catch {
                throw GlobalError.validation(
                    chineseMessage: "编码搜索条件失败: \(error.localizedDescription)",
                    i18nKey: "error.validation.search_condition_encode_failed",
                    level: .notification
                )
            }
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw GlobalError.validation(
                chineseMessage: "构建搜索URL失败",
                i18nKey: "error.validation.search_url_build_failed",
                level: .notification
            )
        }
        // Use a unified API client
        let data = try await APIClient.get(url: url)

        let decoder = JSONDecoder()
        decoder.configureForModrinth()
        let result = try decoder.decode(ModrinthResult.self, from: data)

        return result
    }

    static func fetchLoaders() async -> [Loader] {
        do {
            return try await fetchLoadersThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Modrinth 加载器列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    static func fetchLoadersThrowing() async throws -> [Loader] {
        // Use a unified API client
        let data = try await APIClient.get(url: URLConfig.API.Modrinth.loaderTag)
        let result = try JSONDecoder().decode([Loader].self, from: data)
        return result
    }

    static func fetchCategories() async -> [Category] {
        do {
            return try await fetchCategoriesThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Modrinth 分类列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    static func fetchCategoriesThrowing() async throws -> [Category] {
        // Use a unified API client
        let data = try await APIClient.get(url: URLConfig.API.Modrinth.categoryTag)
        let result = try JSONDecoder().decode([Category].self, from: data)
        return result
    }

    static func fetchGameVersions(includeSnapshots: Bool = false) async -> [GameVersion] {
        do {
            return try await fetchGameVersionsThrowing(includeSnapshots: includeSnapshots)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 Modrinth 游戏版本列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    static func fetchGameVersionsThrowing(
        includeSnapshots: Bool = false
    ) async throws -> [GameVersion] {
        // Use a unified API client
        let data = try await APIClient.get(url: URLConfig.API.Modrinth.gameVersionTag)
        let result = try JSONDecoder().decode([GameVersion].self, from: data)
        // By default, only official versions are returned. If includeSnapshots is true, all versions are returned
        return includeSnapshots ? result : result.filter { $0.version_type == "release" }
    }

    static func fetchProjectDetails(id: String) async -> ModrinthProjectDetail? {
        // Check if it is a CurseForge project (ID starts with "cf-")
        if id.hasPrefix("cf-") {
            return await CurseForgeService.fetchProjectDetailsAsModrinth(id: id)
        }

        // Using the Modrinth service
        do {
            return try await fetchProjectDetailsThrowing(id: id)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取项目详情失败 (ID: \(id)): \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    static func fetchProjectDetailsThrowing(id: String) async throws -> ModrinthProjectDetail {
        // Check if it is a CurseForge project (ID starts with "cf-")
        if id.hasPrefix("cf-") {
            return try await CurseForgeService.fetchProjectDetailsAsModrinthThrowing(id: id)
        }

        // Using the Modrinth service
        let url = URLConfig.API.Modrinth.project(id: id)

        // Use a unified API client
        let data = try await APIClient.get(url: url)

        let decoder = JSONDecoder()
        decoder.configureForModrinth()
        var detail = try decoder.decode(ModrinthProjectDetail.self, from: data)

        // Only keep the official version of the game with pure numbers (including dots), such as 1.20.4
        let releaseGameVersions = detail.gameVersions.filter {
            $0.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil
        }
        detail.gameVersions = CommonUtil.sortMinecraftVersions(releaseGameVersions)

        return detail
    }

    static func fetchProjectVersions(id: String) async -> [ModrinthProjectDetailVersion] {
        // Check if it is a CurseForge project (ID starts with "cf-")
        if id.hasPrefix("cf-") {
            return await CurseForgeService.fetchProjectVersionsAsModrinth(id: id)
        }

        do {
            return try await fetchProjectVersionsThrowing(id: id)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取项目版本列表失败 (ID: \(id)): \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    static func fetchProjectVersionsThrowing(id: String) async throws -> [ModrinthProjectDetailVersion] {
        // Check if it is a CurseForge project (ID starts with "cf-")
        if id.hasPrefix("cf-") {
            return try await CurseForgeService.fetchProjectVersionsAsModrinthThrowing(id: id)
        }

        let url = URLConfig.API.Modrinth.version(id: id)

        // Use a unified API client
        let data = try await APIClient.get(url: url)

        let decoder = JSONDecoder()
        decoder.configureForModrinth()
        return try decoder.decode([ModrinthProjectDetailVersion].self, from: data)
    }

    static func fetchProjectVersionsFilter(
            id: String,
            selectedVersions: [String],
            selectedLoaders: [String],
            type: String
        ) async throws -> [ModrinthProjectDetailVersion] {
            // Check if it is a CurseForge project (ID starts with "cf-")
            if id.hasPrefix("cf-") {
                return try await CurseForgeService.fetchProjectVersionsFilterAsModrinth(
                    id: id,
                    selectedVersions: selectedVersions,
                    selectedLoaders: selectedLoaders,
                    type: type
                )
            }

            let versions = try await fetchProjectVersionsThrowing(id: id)
            var loaders = selectedLoaders
            if type == "datapack" {
                loaders = ["datapack"]
            } else if type == "resourcepack" {
                loaders = ["minecraft"]
            }
            return versions.filter { version in
                // Both version and loader matching must be met
                let versionMatch = selectedVersions.isEmpty || !Set(version.gameVersions).isDisjoint(with: selectedVersions)

                // For shader and resourcepack, loader matching is not checked
                let loaderMatch: Bool
                if type == "shader" || type == "resourcepack" {
                    loaderMatch = true
                } else {
                    loaderMatch = loaders.isEmpty || !Set(version.loaders).isDisjoint(with: loaders)
                }

                return versionMatch && loaderMatch
            }
        }

    static func fetchProjectDependencies(
        type: String,
        cachePath: URL,
        id: String,
        selectedVersions: [String],
        selectedLoaders: [String]
    ) async -> ModrinthProjectDependency {
        do {
            return try await fetchProjectDependenciesThrowing(
                type: type,
                cachePath: cachePath,
                id: id,
                selectedVersions: selectedVersions,
                selectedLoaders: selectedLoaders
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取项目依赖失败 (ID: \(id)): \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return ModrinthProjectDependency(projects: [])
        }
    }

    static func fetchProjectDependenciesThrowing(
        type: String,
        cachePath: URL,
        id: String,
        selectedVersions: [String],
        selectedLoaders: [String]
    ) async throws -> ModrinthProjectDependency {
        // Check if it is a CurseForge project (ID starts with "cf-")
        if id.hasPrefix("cf-") {
            return try await CurseForgeService.fetchProjectDependenciesThrowingAsModrinth(
                type: type,
                cachePath: cachePath,
                id: id,
                selectedVersions: selectedVersions,
                selectedLoaders: selectedLoaders
            )
        }

        // 1. Get all filtered versions
        let versions = try await fetchProjectVersionsFilter(
            id: id,
            selectedVersions: selectedVersions,
            selectedLoaders: selectedLoaders,
            type: type
        )
        // Only take the first version
        guard let firstVersion = versions.first else {
            return ModrinthProjectDependency(projects: [])
        }

        // 2. Concurrently obtain compatible versions of all dependent projects (use batch processing to limit the number of concurrencies)
        let requiredDeps = firstVersion.dependencies.filter { $0.dependencyType == "required" && $0.projectId != nil }
        let maxConcurrentTasks = 10 // Limit the maximum number of concurrent tasks
        var allDependencyVersions: [ModrinthProjectDetailVersion] = []

        // Process dependencies in batches, with a maximum of maxConcurrentTasks per batch
        var currentIndex = 0
        while currentIndex < requiredDeps.count {
            let endIndex = min(currentIndex + maxConcurrentTasks, requiredDeps.count)
            let batch = Array(requiredDeps[currentIndex..<endIndex])
            currentIndex = endIndex

            let batchResults: [ModrinthProjectDetailVersion] = await withTaskGroup(of: ModrinthProjectDetailVersion?.self) { group in
                for dep in batch {
                    guard let projectId = dep.projectId else { continue }
                    group.addTask {
                        do {
                            let depVersion: ModrinthProjectDetailVersion

                            if let versionId = dep.versionId {
                                // If there is a versionId, directly obtain the specified version
                                depVersion = try await fetchProjectVersionThrowing(id: versionId)
                            } else {
                                // If there is no versionId, use filtering logic to obtain compatible versions
                                let depVersions = try await fetchProjectVersionsFilter(
                                    id: projectId,
                                    selectedVersions: selectedVersions,
                                    selectedLoaders: selectedLoaders,
                                    type: type
                                )
                                guard let firstDepVersion = depVersions.first else {
                                    Logger.shared.warning("未找到兼容的依赖版本 (ID: \(projectId))")
                                    return nil
                                }
                                depVersion = firstDepVersion
                            }

                            return depVersion
                        } catch {
                            let globalError = GlobalError.from(error)
                            Logger.shared.error("获取依赖项目版本失败 (ID: \(projectId)): \(globalError.chineseMessage)")
                            return nil
                        }
                    }
                }

                var results: [ModrinthProjectDetailVersion] = []
                for await result in group {
                    if let version = result {
                        results.append(version)
                    }
                }

                return results
            }

            allDependencyVersions.append(contentsOf: batchResults)
        }

        // 3. Use hash to check whether it is installed and filter out missing dependencies
        let missingDependencyVersions = allDependencyVersions.filter { version in
            // Get the hash of the main file
            guard let primaryFile = Self.filterPrimaryFiles(from: version.files) else {
                return true // If there is no main file, it is considered missing
            }
            // Use hash to check if it is installed
            return !ModScanner.shared.isModInstalledSync(hash: primaryFile.hashes.sha1, in: cachePath)
        }

        return ModrinthProjectDependency(projects: missingDependencyVersions)
    }

    static func fetchProjectVersionThrowing(id: String) async throws -> ModrinthProjectDetailVersion {
        let url = URLConfig.API.Modrinth.versionId(versionId: id)

        // Use a unified API client
        let data = try await APIClient.get(url: url)

        let decoder = JSONDecoder()
        decoder.configureForModrinth()
        return try decoder.decode(ModrinthProjectDetailVersion.self, from: data)
    }

    // Filter master file
    static func filterPrimaryFiles(from files: [ModrinthVersionFile]?) -> ModrinthVersionFile? {
        return files?.first { $0.primary == true }
    }

    static func fetchModrinthDetail(by hash: String, completion: @escaping (ModrinthProjectDetail?) -> Void) {
        let url = URLConfig.API.Modrinth.versionFile(hash: hash)
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }

            let decoder = JSONDecoder()
            decoder.configureForModrinth()

            guard let version = try? decoder.decode(ModrinthProjectDetailVersion.self, from: data) else {
                completion(nil)
                return
            }

            Task {
                do {
                    let detail = try await Self.fetchProjectDetailsThrowing(id: version.projectId)
                    await MainActor.run {
                        completion(detail)
                    }
                } catch {
                    let globalError = GlobalError.from(error)
                    Logger.shared.error("通过哈希获取项目详情失败 (Hash: \(hash)): \(globalError.chineseMessage)")
                    GlobalErrorHandler.shared.handle(globalError)
                    await MainActor.run {
                        completion(nil)
                    }
                }
            }
        }
        task.resume()
    }
}

// Extension to support catching errors in async function returning a value.
private extension Task where Success == ModrinthResult, Failure == Error {
    func catching(_ handler: @escaping (Error) -> ModrinthResult) async -> ModrinthResult {
        do {
            return try await value
        } catch {
            return handler(error)
        }
    }
}
