import Foundation

/// CurseForge Services
/// Provide a unified CurseForge API access interface
enum CurseForgeService {

    // MARK: - Private Helpers

    /// Get the CurseForge API request header (including API key, if available)
    private static func getHeaders() -> [String: String] {
        var headers: [String: String] = ["Accept": "application/json"]
        if let apiKey = AppConstants.curseForgeAPIKey {
            headers["x-api-key"] = apiKey
        }
        return headers
    }

    // MARK: - Public Methods

    /// Get CurseForge file details
    /// - Parameters:
    ///   - projectId: project ID
    ///   - fileId: file ID
    /// - Returns: file details, if the acquisition fails, return nil
    static func fetchFileDetail(projectId: Int, fileId: Int) async -> CurseForgeModFileDetail? {
        do {
            return try await fetchFileDetailThrowing(projectId: projectId, fileId: fileId)
        } catch {
            Logger.shared.error("获取 CurseForge 文件详情失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get CurseForge file details (throws exception version)
    /// - Parameters:
    ///   - projectId: project ID
    ///   - fileId: file ID
    /// - Returns: File details
    /// - Throws: Network error or parsing error
    static func fetchFileDetailThrowing(projectId: Int, fileId: Int) async throws -> CurseForgeModFileDetail {
        // Use the configured CurseForge API URL
        let url = URLConfig.API.CurseForge.fileDetail(projectId: projectId, fileId: fileId)

        return try await tryFetchFileDetail(from: url.absoluteString)
    }

    /// Get CurseForge module details
    /// - Parameter modId: Module ID
    /// - Returns: Module details, if the acquisition fails, return nil
    static func fetchModDetail(modId: Int) async -> CurseForgeModDetail? {
        do {
            return try await fetchModDetailThrowing(modId: modId)
        } catch {
            Logger.shared.error("获取 CurseForge 模组详情失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get CurseForge module details (throws exception version)
    /// - Parameter modId: Module ID
    /// - Returns: Module details
    /// - Throws: Network error or parsing error
    static func fetchModDetailThrowing(modId: Int) async throws -> CurseForgeModDetail {
        // Use the configured CurseForge API URL
        let url = URLConfig.API.CurseForge.modDetail(modId: modId)

        return try await tryFetchModDetail(from: url.absoluteString)
    }

    /// Get CurseForge module description (throws exception version)
    /// - Parameter modId: Module ID
    /// - Returns: Description content in HTML format
    /// - Throws: Network error or parsing error
    static func fetchModDescriptionThrowing(modId: Int) async throws -> String {
        // Use the configured CurseForge API URL
        let url = URLConfig.API.CurseForge.modDescription(modId: modId)

        return try await tryFetchModDescription(from: url.absoluteString)
    }

    /// Get CurseForge project file list
    /// - Parameters:
    ///   - projectId: project ID
    ///   - gameVersion: game version filtering (optional)
    ///   - modLoaderType: Mod loader type filtering (optional)
    /// - Returns: file list, returns nil if acquisition fails
    static func fetchProjectFiles(projectId: Int, gameVersion: String? = nil, modLoaderType: Int? = nil) async -> [CurseForgeModFileDetail]? {
        do {
            return try await fetchProjectFilesThrowing(projectId: projectId, gameVersion: gameVersion, modLoaderType: modLoaderType)
        } catch {
            Logger.shared.error("获取 CurseForge 项目文件列表失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get CurseForge project file list (throws exception version)
    /// - Parameters:
    ///   - projectId: project ID
    ///   - gameVersion: game version filtering (optional)
    ///   - modLoaderType: Mod loader type filtering (optional)
    ///   - modDetail: Module details obtained in advance (optional, used to reuse and reduce requests)
    /// - Returns: file list
    /// - Throws: Network error or parsing error
    static func fetchProjectFilesThrowing(
        projectId: Int,
        gameVersion: String? = nil,
        modLoaderType: Int? = nil,
    ) async throws -> [CurseForgeModFileDetail] {
        // Parse file information from modDetail without calling projectFiles API
        let modDetailToUse = try await fetchModDetailThrowing(modId: projectId)

        var files: [CurseForgeModFileDetail] = []

        // Get the file list from latestFiles first
        if let latestFilesIndexes = modDetailToUse.latestFilesIndexes, !latestFilesIndexes.isEmpty {
            // If latestFiles does not exist, construct file details from latestFilesIndexes
            // Group by fileId to collect all game versions
            var fileIndexMap: [Int: [CurseForgeFileIndex]] = [:]
            for index in latestFilesIndexes {
                fileIndexMap[index.fileId, default: []].append(index)
            }

            // Construct file details for each unique fileId
            for (fileId, indexes) in fileIndexMap {
                guard let firstIndex = indexes.first else { continue }

                // Collect all matching game versions
                let gameVersions = indexes.map { $0.gameVersion }

                // Build download link using fileId and fileName
                let downloadUrl = URLConfig.API.CurseForge.fallbackDownloadUrl(
                    fileId: fileId,
                    fileName: firstIndex.filename
                ).absoluteString

                // Construction file details
                let fileDetail = CurseForgeModFileDetail(
                    id: fileId,
                    displayName: firstIndex.filename,
                    fileName: firstIndex.filename,
                    downloadUrl: downloadUrl,
                    fileDate: "", // There is no date information in latestFilesIndexes
                    releaseType: firstIndex.releaseType,
                    gameVersions: gameVersions,
                    dependencies: nil,
                    changelog: nil,
                    fileLength: nil,
                    hash: nil,
                    hashes: nil,
                    modules: nil,
                    projectId: projectId,
                    projectName: modDetailToUse.name,
                    authors: modDetailToUse.authors
                )
                files.append(fileDetail)
            }
        }

        // Filter based on gameVersion and modLoaderType
        var filteredFiles = files

        if let gameVersion = gameVersion {
            filteredFiles = filteredFiles.filter { file in
                file.gameVersions.contains(gameVersion)
            }
        }

        // If modLoaderType is specified, modLoader information needs to be obtained from latestFilesIndexes for filtering
        if let modLoaderType = modLoaderType {
            if let latestFilesIndexes = modDetailToUse.latestFilesIndexes {
                // Get the fileId collection matching modLoaderType
                let matchingFileIds = Set(latestFilesIndexes
                    .filter { $0.modLoader == modLoaderType }
                    .map { $0.fileId })

                // Keep only matching files
                filteredFiles = filteredFiles.filter { file in
                    matchingFileIds.contains(file.id)
                }
            }
            // Unable to filter by modLoaderType when latestFilesIndexes does not exist
            // In this case all files are returned (possibly including unmatched loaders)
        }

        // Get full file details (including hashes) for each file
        // Use batch processing to limit the number of concurrencies to avoid excessive memory usage
        let maxConcurrentTasks = 20 // Limit the maximum number of concurrent tasks
        var filesWithHashes: [CurseForgeModFileDetail] = []
        // Process files in batches, up to maxConcurrentTasks per batch
        var currentIndex = 0
        while currentIndex < filteredFiles.count {
            let endIndex = min(currentIndex + maxConcurrentTasks, filteredFiles.count)
            let batch = Array(filteredFiles[currentIndex..<endIndex])
            currentIndex = endIndex

            await withTaskGroup(of: (Int, CurseForgeModFileDetail?).self) { group in
                for file in batch {
                    group.addTask {
                        do {
                            let fileDetail = try await fetchFileDetailThrowing(projectId: projectId, fileId: file.id)
                            return (file.id, fileDetail)
                        } catch {
                            Logger.shared.warning("获取文件详情失败 (fileId: \(file.id)): \(error.localizedDescription)")
                            return (file.id, nil)
                        }
                    }
                }

                // Create a mapping of fileId to file details
                var fileDetailMap: [Int: CurseForgeModFileDetail] = [:]
                for await (fileId, fileDetail) in group {
                    if let detail = fileDetail {
                        fileDetailMap[fileId] = detail
                    }
                }

                // Update the file list using the obtained file details (including hashes)
                for file in batch {
                    if let detailedFile = fileDetailMap[file.id] {
                        // Extract the hash with algo = 1 from the hashes array
                        let sha1Hash = detailedFile.hashes?.first { $0.algo == 1 }

                        // Create updated file details, retaining the original information but updating the hash
                        let updatedFile = CurseForgeModFileDetail(
                            id: file.id,
                            displayName: file.displayName,
                            fileName: file.fileName,
                            downloadUrl: file.downloadUrl ?? detailedFile.downloadUrl,
                            fileDate: file.fileDate.isEmpty ? detailedFile.fileDate : file.fileDate,
                            releaseType: file.releaseType,
                            gameVersions: file.gameVersions,
                            dependencies: file.dependencies ?? detailedFile.dependencies,
                            changelog: file.changelog ?? detailedFile.changelog,
                            fileLength: file.fileLength ?? detailedFile.fileLength,
                            hash: sha1Hash ?? file.hash ?? detailedFile.hash,
                            hashes: detailedFile.hashes,
                            modules: file.modules ?? detailedFile.modules,
                            projectId: file.projectId,
                            projectName: file.projectName,
                            authors: file.authors
                        )
                        filesWithHashes.append(updatedFile)
                    } else {
                        // If obtaining details fails, keep the original file
                        filesWithHashes.append(file)
                    }
                }
            }
        }

        return filesWithHashes
    }

    // MARK: - Search Methods

    /// Search items (silent version)
    /// - Parameters:
    ///   - gameId: game ID (432 for Minecraft)
    ///   - classId: content type ID (optional)
    ///   - categoryId: category ID (optional, will be overridden by categoryIds)
    ///   - categoryIds: Category ID list (optional, will cover categoryId, up to 10)
    ///   - gameVersion: game version (optional, will be overridden by gameVersions)
    ///   - gameVersions: Game version list (optional, will overwrite gameVersion, up to 4)
    ///   - searchFilter: search keyword (optional)
    ///   - modLoaderType: Mod loader type (optional, will be overridden by modLoaderTypes)
    ///   - modLoaderTypes: Mod loader type list (optional, will override modLoaderType, up to 5)
    ///   - index: page index (optional)
    ///   - pageSize: size of each page (optional)
    /// - Returns: search results, empty results are returned if failed
    /// - Note: API limitations: categoryIds can be up to 10, gameVersions can be up to 4, modLoaderTypes can be up to 5
    static func searchProjects(
        gameId: Int = 432,
        classId: Int? = nil,
        categoryId: Int? = nil,
        categoryIds: [Int]? = nil,
        gameVersion: String? = nil,
        gameVersions: [String]? = nil,
        searchFilter: String? = nil,
        modLoaderType: Int? = nil,
        modLoaderTypes: [Int]? = nil,
        index: Int = 0,
        pageSize: Int = 20
    ) async -> CurseForgeSearchResult {
        do {
            return try await searchProjectsThrowing(
                gameId: gameId,
                classId: classId,
                categoryId: categoryId,
                categoryIds: categoryIds,
                gameVersion: gameVersion,
                gameVersions: gameVersions,
                searchFilter: searchFilter,
                modLoaderType: modLoaderType,
                modLoaderTypes: modLoaderTypes,
                index: index,
                pageSize: pageSize
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("搜索 CurseForge 项目失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return CurseForgeSearchResult(data: [], pagination: nil)
        }
    }

    /// Search project (throws exception version)
    /// - Parameters:
    ///   - gameId: game ID (432 for Minecraft)
    ///   - classId: content type ID (optional)
    ///   - categoryId: category ID (optional, will be overridden by categoryIds)
    ///   - categoryIds: Category ID list (optional, will cover categoryId, up to 10)
    ///   - gameVersion: game version (optional, will be overridden by gameVersions)
    ///   - gameVersions: Game version list (optional, will overwrite gameVersion, up to 4)
    ///   - searchFilter: search keyword (optional)
    ///   - modLoaderType: Mod loader type (optional, will be overridden by modLoaderTypes)
    ///   - modLoaderTypes: Mod loader type list (optional, will override modLoaderType, up to 5)
    ///   - index: page index (optional)
    ///   - pageSize: size of each page (optional)
    /// - Returns: search results
    /// - Throws: GlobalError when the operation fails
    /// - Note:
    ///   - If sortField and sortOrder are not passed, the default sorting of the CurseForge API will be used (usually by relevance)
    ///   - API restrictions: categoryIds can be up to 10, gameVersions can be up to 4, modLoaderTypes can be up to 5
    static func searchProjectsThrowing(
        gameId: Int = 432,
        classId: Int? = nil,
        categoryId: Int? = nil,
        categoryIds: [Int]? = nil,
        gameVersion: String? = nil,
        gameVersions: [String]? = nil,
        /// Original search keyword (blanks will be automatically collapsed and connected with "+", e.g. "fabric api" -> "fabric+api")
        searchFilter: String? = nil,
        modLoaderType: Int? = nil,
        modLoaderTypes: [Int]? = nil,
        index: Int = 0,
        pageSize: Int = 20
    ) async throws -> CurseForgeSearchResult {
        // Forced to use descending order by total downloads
        let effectiveSortField = 6
        let effectiveSortOrder = "desc"

        var components = URLComponents(
            url: URLConfig.API.CurseForge.search,
            resolvingAgainstBaseURL: true
        )

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "gameId", value: String(gameId)),
            URLQueryItem(name: "index", value: String(index)),
            URLQueryItem(name: "pageSize", value: String(min(pageSize, 50))),
        ]

        if let classId = classId {
            queryItems.append(URLQueryItem(name: "classId", value: String(classId)))
        }

        // categoryIds will override categoryId
        // API limit: Maximum 10 category IDs
        if let categoryIds = categoryIds, !categoryIds.isEmpty {
            let limitedCategoryIds = Array(categoryIds.prefix(10))
            // As required by the documentation, use the JSON array string format: ["6","7"]
            let stringIds = limitedCategoryIds.map { String($0) }
            let data = try JSONEncoder().encode(stringIds)
            guard let jsonArrayString = String(data: data, encoding: .utf8) else {
                throw GlobalError.validation(
                    chineseMessage: "编码 categoryIds 失败",
                    i18nKey: "Encode Category IDs Failed",
                    level: .notification
                )
            }
            queryItems.append(URLQueryItem(name: "categoryIds", value: jsonArrayString))
        } else if let categoryId = categoryId {
            queryItems.append(URLQueryItem(name: "categoryId", value: String(categoryId)))
        }

        // gameVersions will override gameVersion
        // API limit: up to 4 game versions
        if let gameVersions = gameVersions, !gameVersions.isEmpty {
            let limitedGameVersions = Array(gameVersions.prefix(4))
            // As required by the API documentation, use the JSON array string format: ["1.0","1.1"]
            let data = try JSONEncoder().encode(limitedGameVersions)
            guard let jsonArrayString = String(data: data, encoding: .utf8) else {
                throw GlobalError.validation(
                    chineseMessage: "编码 gameVersions 失败",
                    i18nKey: "Encode Game Versions Failed",
                    level: .notification
                )
            }
            queryItems.append(URLQueryItem(name: "gameVersions", value: jsonArrayString))
        } else if let gameVersion = gameVersion {
            queryItems.append(URLQueryItem(name: "gameVersion", value: gameVersion))
        }

        if let rawSearchFilter = searchFilter?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawSearchFilter.isEmpty {
            // Fold consecutive blank spaces and connect them with "+" to get a format similar to "fabric+api"
            let components = rawSearchFilter
                .split { $0.isWhitespace }
                .map(String.init)
            let normalizedSearchFilter = components.joined(separator: "+")
            queryItems.append(URLQueryItem(name: "searchFilter", value: normalizedSearchFilter))
        }

        // Sorting parameters: forced to add sortField=6, sortOrder=desc by default (reverse order of total downloads)
        queryItems.append(URLQueryItem(name: "sortField", value: String(effectiveSortField)))
        queryItems.append(URLQueryItem(name: "sortOrder", value: effectiveSortOrder))

        // modLoaderTypes overrides modLoaderType
        // API limit: maximum 5 loader types
        if let modLoaderTypes = modLoaderTypes, !modLoaderTypes.isEmpty {
            let limitedModLoaderTypes = Array(modLoaderTypes.prefix(5))
            let stringTypes = limitedModLoaderTypes.map { String($0) }
            // Use JSON array string format: ["1","4"]
            let data = try JSONEncoder().encode(stringTypes)
            guard let jsonArrayString = String(data: data, encoding: .utf8) else {
                throw GlobalError.validation(
                    chineseMessage: "编码 modLoaderTypes 失败",
                    i18nKey: "Encode Mod Loader Types Failed",
                    level: .notification
                )
            }
            queryItems.append(URLQueryItem(name: "modLoaderTypes", value: jsonArrayString))
        } else if let modLoaderType = modLoaderType {
            queryItems.append(URLQueryItem(name: "modLoaderType", value: String(modLoaderType)))
        }

        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw GlobalError.validation(
                chineseMessage: "构建搜索URL失败",
                i18nKey: "Search URL Build Failed",
                level: .notification
            )
        }

        let headers = getHeaders()
        let data = try await APIClient.get(url: url, headers: headers)
        let result = try JSONDecoder().decode(CurseForgeSearchResult.self, from: data)

        return result
    }

    // MARK: - Category Methods

    /// Get the category list (silent version)
    /// - Returns: Category list, returns empty array on failure
    static func fetchCategories() async -> [CurseForgeCategory] {
        do {
            return try await fetchCategoriesThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 CurseForge 分类列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    /// Get the category list (throws exception version)
    /// - Returns: Category list
    /// - Throws: GlobalError when the operation fails
    static func fetchCategoriesThrowing() async throws -> [CurseForgeCategory] {
        let headers = getHeaders()
        let data = try await APIClient.get(url: URLConfig.API.CurseForge.categories, headers: headers)
        let result = try JSONDecoder().decode(CurseForgeCategoriesResponse.self, from: data)
        return result.data
    }

    // MARK: - Game Version Methods

    /// Get the game version list (silent version)
    /// - Returns: Game version list, returns an empty array on failure
    static func fetchGameVersions() async -> [CurseForgeGameVersion] {
        do {
            return try await fetchGameVersionsThrowing()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 CurseForge 游戏版本列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    /// Get the game version list (throws exception version)
    /// - Returns: Game version list
    /// - Throws: GlobalError when the operation fails
    static func fetchGameVersionsThrowing() async throws -> [CurseForgeGameVersion] {
        let headers = getHeaders()
        let data = try await APIClient.get(url: URLConfig.API.CurseForge.gameVersions, headers: headers)
        let result = try JSONDecoder().decode(CurseForgeGameVersionsResponse.self, from: data)
        // Only approved and official versions are returned
        return result.data.filter { $0.approved && $0.version_type == "release" }
    }

    // MARK: - Project Detail Methods (as Modrinth format)

    /// Get project details (mapped to Modrinth format, silent version)
    /// - Parameter id: project ID
    /// - Returns: project details in Modrinth format, returns nil on failure
    static func fetchProjectDetailsAsModrinth(id: String) async -> ModrinthProjectDetail? {
        do {
            return try await fetchProjectDetailsAsModrinthThrowing(id: id)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取项目详情失败 (ID: \(id)): \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    /// Get project details (mapped to Modrinth format, throw exception version)
    /// - Parameter id: Project ID (may contain "cf-" prefix)
    /// - Returns: Project details in Modrinth format
    /// - Throws: GlobalError when the operation fails
    static func fetchProjectDetailsAsModrinthThrowing(id: String) async throws -> ModrinthProjectDetail {
        let (modId, _) = try parseCurseForgeId(id)

        // Concurrently obtain project details and descriptions
        async let cfDetailTask = fetchModDetailThrowing(modId: modId)
        async let descriptionTask = fetchModDescriptionThrowing(modId: modId)

        let cfDetail = try await cfDetailTask
        let description = try await descriptionTask

        guard let modrinthDetail = CurseForgeToModrinthAdapter.convert(cfDetail, description: description) else {
            throw GlobalError.validation(
                chineseMessage: "转换项目详情失败",
                i18nKey: "Project Detail Convert Failed",
                level: .notification
            )
        }
        return modrinthDetail
    }

    /// Get the project version list (mapped to Modrinth format, silent version)
    /// - Parameter id: project ID
    /// - Returns: Version list in Modrinth format, returning an empty array on failure
    static func fetchProjectVersionsAsModrinth(id: String) async -> [ModrinthProjectDetailVersion] {
        do {
            return try await fetchProjectVersionsAsModrinthThrowing(id: id)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取项目版本列表失败 (ID: \(id)): \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    /// Get the project version list (mapped to Modrinth format, throw exception version)
    /// - Parameter id: Project ID (may contain "cf-" prefix)
    /// - Returns: version list in Modrinth format
    /// - Throws: GlobalError when the operation fails
    static func fetchProjectVersionsAsModrinthThrowing(id: String) async throws -> [ModrinthProjectDetailVersion] {
        let (modId, normalizedId) = try parseCurseForgeId(id)

        let cfFiles = try await fetchProjectFilesThrowing(projectId: modId)
        return cfFiles.compactMap { CurseForgeToModrinthAdapter.convertVersion($0, projectId: normalizedId) }
    }

    /// Get a list of project versions (filtered versions, mapped to Modrinth format)
    /// - Parameters:
    ///   - id: project ID (may contain "cf-" prefix)
    ///   - selectedVersions: selected version
    ///   - selectedLoaders: selected loaders
    ///   - type: project type
    /// - Returns: filtered Modrinth format version list
    /// - Throws: GlobalError when the operation fails
    static func fetchProjectVersionsFilterAsModrinth(
        id: String,
        selectedVersions: [String],
        selectedLoaders: [String],
        type: String
    ) async throws -> [ModrinthProjectDetailVersion] {
        let (modId, normalizedId) = try parseCurseForgeId(id)

        // For light and shadow packages, resource packages, and data packages, CurseForge API does not support modLoaderType filtering
        let resourceTypeLowercased = type.lowercased()
        let shouldFilterByLoader = !(resourceTypeLowercased == "shader" ||
                                     resourceTypeLowercased == "resourcepack" ||
                                     resourceTypeLowercased == "datapack")

        // Convert loader name to CurseForge ModLoaderType (only for resource types that require filtered loaders)
        var modLoaderTypes: [Int] = []
        if shouldFilterByLoader {
            for loader in selectedLoaders {
                if let loaderType = CurseForgeModLoaderType.from(loader) {
                    modLoaderTypes.append(loaderType.rawValue)
                }
            }
        }

        // Get file list
        // Optimization: If the number of versions is small (<=3), obtain each version separately; otherwise, obtain all files at once and then filter
        var cfFiles: [CurseForgeModFileDetail] = []
        if !selectedVersions.isEmpty && selectedVersions.count <= 3 {
            // When the number of versions is small, get files for each version (more precise)
            for version in selectedVersions {
                // For light and shadow packages, resource packages, and data packages, the modLoaderType parameter is not passed
                let modLoaderType = shouldFilterByLoader && !modLoaderTypes.isEmpty ? modLoaderTypes.first : nil
                let files = try await fetchProjectFilesThrowing(
                    projectId: modId,
                    gameVersion: version,
                    modLoaderType: modLoaderType
                )
                cfFiles.append(contentsOf: files)
            }
        } else {
            // When the number of versions is large or empty, obtain all files at once and then filter them (reduce API calls and memory usage)
            cfFiles = try await fetchProjectFilesThrowing(
                projectId: modId,
                gameVersion: nil,
                modLoaderType: shouldFilterByLoader && !modLoaderTypes.isEmpty ? modLoaderTypes.first : nil
            )
        }

        // Deduplication: Deduplication according to fileId, keeping the first one
        var seenFileIds = Set<Int>()
        cfFiles = cfFiles.filter { file in
            if seenFileIds.contains(file.id) {
                return false
            }
            seenFileIds.insert(file.id)
            return true
        }

        // Filter files
        let filteredFiles = cfFiles.filter { file in
            // version matching
            let versionMatch = selectedVersions.isEmpty || !Set(file.gameVersions).isDisjoint(with: selectedVersions)

            // For light and shadow packages, resource packages, and data packages, there is no need to check loader matching
            // Other types need to match the loader, and the CurseForge API may not return it to simplify processing
            let loaderMatch = !shouldFilterByLoader || modLoaderTypes.isEmpty || true

            return versionMatch && loaderMatch
        }

        // Convert to Modrinth format, ensuring projectId contains "cf-" prefix
        return filteredFiles.compactMap { CurseForgeToModrinthAdapter.convertVersion($0, projectId: normalizedId) }
    }

    /// Filter out main files
    static func filterPrimaryFiles(from files: [CurseForgeModFileDetail]?) -> CurseForgeModFileDetail? {
        // CurseForge has no primary field and returns the first file
        return files?.first
    }

    // MARK: - Dependency Methods

    /// Get project dependencies (mapped to Modrinth format, silent version)
    /// - Parameters:
    ///   - type: project type
    ///   - cachePath: cache path
    ///   - id: project ID
    ///   - selectedVersions: selected version
    ///   - selectedLoaders: selected loaders
    /// - Returns: project dependencies, empty dependencies are returned on failure
    static func fetchProjectDependenciesAsModrinth(
        type: String,
        cachePath: URL,
        id: String,
        selectedVersions: [String],
        selectedLoaders: [String]
    ) async -> ModrinthProjectDependency {
        do {
            return try await fetchProjectDependenciesThrowingAsModrinth(
                type: type,
                cachePath: cachePath,
                id: id,
                selectedVersions: selectedVersions,
                selectedLoaders: selectedLoaders
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取 CurseForge 项目依赖失败 (ID: \(id)): \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return ModrinthProjectDependency(projects: [])
        }
    }

    /// Get project dependencies (mapped to Modrinth format, throw exception version)
    /// - Parameters:
    ///   - type: project type
    ///   - cachePath: cache path
    ///   - id: project ID
    ///   - selectedVersions: selected version
    ///   - selectedLoaders: selected loaders
    /// - Returns: project dependencies
    /// - Throws: GlobalError when the operation fails
    static func fetchProjectDependenciesThrowingAsModrinth(
        type: String,
        cachePath: URL,
        id: String,
        selectedVersions: [String],
        selectedLoaders: [String]
    ) async throws -> ModrinthProjectDependency {
        // 1. Get all filtered versions
        let versions = try await fetchProjectVersionsFilterAsModrinth(
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
        let maxConcurrentTasks = 20 // Limit the maximum number of concurrent tasks
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

                            // Normalize projectId: if it is purely numeric, add "cf-" prefix (CurseForge dependencies are usually purely numeric)
                            let normalizedProjectId: String
                            if !projectId.hasPrefix("cf-") && Int(projectId) != nil {
                                // Pure numbers, should be the CurseForge project
                                normalizedProjectId = "cf-\(projectId)"
                            } else {
                                normalizedProjectId = projectId
                            }

                            if let versionId = dep.versionId {
                                // If there is a versionId, you need to check whether it is the CurseForge version
                                if versionId.hasPrefix("cf-") {
                                    // CurseForge version, needs to be obtained from the file ID
                                    let fileId = Int(versionId.replacingOccurrences(of: "cf-", with: "")) ?? 0
                                    // Need to get modId from projectId
                                    let (modId, _) = try parseCurseForgeId(normalizedProjectId)
                                    let cfFile = try await fetchFileDetailThrowing(projectId: modId, fileId: fileId)
                                    guard let convertedVersion = CurseForgeToModrinthAdapter.convertVersion(cfFile, projectId: normalizedProjectId) else {
                                        return nil
                                    }
                                    depVersion = convertedVersion
                                } else {
                                    // Modrinth version, using ModrinthService
                                    depVersion = try await ModrinthService.fetchProjectVersionThrowing(id: versionId)
                                }
                            } else {
                                // If there is no versionId, use filtering logic to obtain compatible versions
                                // Check if it is a CurseForge project
                                if normalizedProjectId.hasPrefix("cf-") {
                                    // CurseForge project
                                    let depVersions = try await fetchProjectVersionsFilterAsModrinth(
                                        id: normalizedProjectId,
                                        selectedVersions: selectedVersions,
                                        selectedLoaders: selectedLoaders,
                                        type: type
                                    )
                                    guard let firstDepVersion = depVersions.first else {
                                        return nil
                                    }
                                    depVersion = firstDepVersion
                                } else {
                                    // modrinth project
                                    let depVersions = try await ModrinthService.fetchProjectVersionsFilter(
                                        id: normalizedProjectId,
                                        selectedVersions: selectedVersions,
                                        selectedLoaders: selectedLoaders,
                                        type: type
                                    )
                                    guard let firstDepVersion = depVersions.first else {
                                        return nil
                                    }
                                    depVersion = firstDepVersion
                                }
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
            guard let primaryFile = ModrinthService.filterPrimaryFiles(from: version.files) else {
                return true // If there is no main file, it is considered missing
            }
            // Use hash to check if it is installed
            return !ModScanner.shared.isModInstalledSync(hash: primaryFile.hashes.sha1, in: cachePath)
        }

        return ModrinthProjectDependency(projects: missingDependencyVersions)
    }

    // MARK: - Private Methods

    /// Attempts to obtain file details from the specified URL
    /// - Parameter urlString: API URL
    /// - Returns: File details
    /// - Throws: Network error or parsing error
    private static func tryFetchFileDetail(from urlString: String) async throws -> CurseForgeModFileDetail {
        guard let url = URL(string: urlString) else {
            throw GlobalError.validation(
                chineseMessage: "无效的镜像 API URL",
                i18nKey: "Network URL Error",
                level: .notification
            )
        }

        // Use a unified API client
        let headers = getHeaders()
        let data = try await APIClient.get(url: url, headers: headers)

        // Parse response
        let result = try JSONDecoder().decode(CurseForgeFileResponse.self, from: data)
        return result.data
    }

    /// Attempts to obtain module details from the specified URL
    /// - Parameter urlString: API URL
    /// - Returns: Module details
    /// - Throws: Network error or parsing error
    private static func tryFetchModDetail(from urlString: String) async throws -> CurseForgeModDetail {
        guard let url = URL(string: urlString) else {
            throw GlobalError.validation(
                chineseMessage: "无效的镜像 API URL",
                i18nKey: "Network URL Error",
                level: .notification
            )
        }

        // Use a unified API client
        let headers = getHeaders()
        let data = try await APIClient.get(url: url, headers: headers)

        // Parse response
        let result = try JSONDecoder().decode(CurseForgeModDetailResponse.self, from: data)
        return result.data
    }

    /// Attempts to obtain the mod description from the specified URL
    /// - Parameter urlString: API URL
    /// - Returns: Description content in HTML format
    /// - Throws: Network error or parsing error
    private static func tryFetchModDescription(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw GlobalError.validation(
                chineseMessage: "无效的镜像 API URL",
                i18nKey: "Network URL Error",
                level: .notification
            )
        }

        // Use a unified API client
        let headers = getHeaders()
        let data = try await APIClient.get(url: url, headers: headers)

        // Parse response
        let result = try JSONDecoder().decode(CurseForgeModDescriptionResponse.self, from: data)
        return result.data
    }

    /// Parses CF IDs, returning pure numeric IDs and prefixed standard IDs
    private static func parseCurseForgeId(_ id: String) throws -> (modId: Int, normalized: String) {
        let cleanId = id.replacingOccurrences(of: "cf-", with: "")
        guard let modId = Int(cleanId) else {
            throw GlobalError.validation(
                chineseMessage: "无效的项目 ID",
                i18nKey: "Invalid Project ID",
                level: .notification
            )
        }
        let normalizedId = id.hasPrefix("cf-") ? id : "cf-\(cleanId)"
        return (modId, normalizedId)
    }
}
/// CurseForge file response
private struct CurseForgeFileResponse: Codable {
    let data: CurseForgeModFileDetail
}
