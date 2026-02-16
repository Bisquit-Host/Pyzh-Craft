import CryptoKit
import Foundation

class ModScanner {
    static let shared = ModScanner()

    private init() {}

    /// Main entrance: Get ModrinthProjectDetail (silent version)
    func getModrinthProjectDetail(
        for fileURL: URL,
        completion: @escaping (ModrinthProjectDetail?) -> Void
    ) {
        Task {
            do {
                let detail = try await getModrinthProjectDetailThrowing(
                    for: fileURL
                )
                completion(detail)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error(
                    "获取 Modrinth 项目详情失败: \(globalError.chineseMessage)"
                )
                GlobalErrorHandler.shared.handle(globalError)
                completion(nil)
            }
        }
    }

    /// Main entrance: Get ModrinthProjectDetail (throws exception version)
    func getModrinthProjectDetailThrowing(
        for fileURL: URL
    ) async throws -> ModrinthProjectDetail? {
        guard let hash = try Self.sha1HashThrowing(of: fileURL) else {
            throw GlobalError.validation(
                chineseMessage: "无法计算文件哈希值",
                i18nKey: "File Hash Calculation Failed",
                level: .silent
            )
        }

        if let cached = getModCacheFromDatabase(hash: hash) {
            // Update file name to current actual file name (may have been renamed to .disabled)
            var updatedCached = cached
            updatedCached.fileName = fileURL.lastPathComponent
            return updatedCached
        }

        // Query by file hash using fetchModrinthDetail
        let detail = await withCheckedContinuation { continuation in
            ModrinthService.fetchModrinthDetail(by: hash) { detail in
                continuation.resume(returning: detail)
            }
        }

        if let detail = detail {
            // Set local file name
            var detailWithFileName = detail
            detailWithFileName.fileName = fileURL.lastPathComponent
            saveToCache(hash: hash, detail: detailWithFileName)
            return detailWithFileName
        } else {
            // Try local parsing
            let (modid, version) =
                try ModMetadataParser.parseModMetadataThrowing(fileURL: fileURL)

            // If the CF query fails or modid is not parsed, it will fall back to the local logic
            if let modid = modid, let version = version {
                // Create a back-up object using the parsed metadata
                let fallbackDetail = createFallbackDetail(
                    fileURL: fileURL,
                    modid: modid,
                    version: version
                )
                saveToCache(hash: hash, detail: fallbackDetail)
                return fallbackDetail
            } else {
                // The ultimate back-up strategy: Use filenames to create basic information
                let fallbackDetail = createFallbackDetailFromFileName(
                    fileURL: fileURL
                )
                saveToCache(hash: hash, detail: fallbackDetail)
                return fallbackDetail
            }
        }
    }

    // MARK: - Mod Cache (Database)

    private func getModCacheFromDatabase(hash: String) -> ModrinthProjectDetail? {
        guard let jsonData = ModCacheManager.shared.get(hash: hash) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(ModrinthProjectDetail.self, from: jsonData)
        } catch {
            Logger.shared.error("解码 mod 缓存失败: \(error.localizedDescription)")
            return nil
        }
    }

    func saveToCache(hash: String, detail: ModrinthProjectDetail) {
        do {
            let jsonData = try JSONEncoder().encode(detail)
            ModCacheManager.shared.setSilently(hash: hash, jsonData: jsonData)
        } catch {
            Logger.shared.error("编码 mod 缓存失败: \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(GlobalError.validation(
                chineseMessage: "保存 mod 缓存失败: \(error.localizedDescription)",
                i18nKey: "Failed to save mod cache: %@",
                level: .silent
            ))
        }
    }

    // MARK: - Hash

    static func sha1Hash(of url: URL) -> String? {
        SHA1Calculator.sha1Silent(ofFileAt: url)
    }

    static func sha1HashThrowing(of url: URL) throws -> String? {
        try SHA1Calculator.sha1(ofFileAt: url)
    }

    // MARK: - Fallback Methods

    /// A closer look at the public field structure of ModrinthProjectDetail
    private struct CommonFallbackFields {
        let description: String
        let categories: [String]
        let clientSide: String
        let serverSide: String
        let body: String
        let additionalCategories: [String]?
        let issuesUrl: String?
        let sourceUrl: String?
        let wikiUrl: String?
        let discordUrl: String?
        let projectType: String
        let downloads: Int
        let iconUrl: String?
        let team: String
        let published: Date
        let updated: Date
        let followers: Int
        let license: License?
        let gameVersions: [String]
        let loaders: [String]
        let type: String?
    }

    /// Create public fields of the base ModrinthProjectDetail
    private func createBaseFallbackDetail(fileURL: URL) -> (fileName: String, baseFileName: String) {
        let fileName = fileURL.lastPathComponent
        let baseFileName = fileName.replacingOccurrences(
            of: ".\(fileURL.pathExtension)",
            with: ""
        )
        return (fileName, baseFileName)
    }

    /// Create a public part of ModrinthProjectDetail
    private func createCommonFallbackFields(fileName: String, baseFileName: String) -> CommonFallbackFields {
        return CommonFallbackFields(
            description: "local：\(fileName)",
            categories: ["unknown"],
            clientSide: "optional",
            serverSide: "optional",
            body: "",
            additionalCategories: nil,
            issuesUrl: nil,
            sourceUrl: nil,
            wikiUrl: nil,
            discordUrl: nil,
            projectType: "mod",
            downloads: 0,
            iconUrl: nil,
            team: "local",
            published: Date(),
            updated: Date(),
            followers: 0,
            license: nil,
            gameVersions: [],
            loaders: [],
            type: nil
        )
    }

    /// Use the parsed metadata to create a backend ModrinthProjectDetail
    private func createFallbackDetail(
        fileURL: URL,
        modid: String,
        version: String
    ) -> ModrinthProjectDetail {
        let (fileName, baseFileName) = createBaseFallbackDetail(fileURL: fileURL)
        let common = createCommonFallbackFields(fileName: fileName, baseFileName: baseFileName)

        return ModrinthProjectDetail(
            slug: modid,
            title: baseFileName,
            description: common.description,
            categories: common.categories,
            clientSide: common.clientSide,
            serverSide: common.serverSide,
            body: common.body,
            additionalCategories: common.additionalCategories,
            issuesUrl: common.issuesUrl,
            sourceUrl: common.sourceUrl,
            wikiUrl: common.wikiUrl,
            discordUrl: common.discordUrl,
            projectType: common.projectType,
            downloads: common.downloads,
            iconUrl: common.iconUrl,
            id: "local_\(modid)_\(UUID().uuidString.prefix(8))",
            team: common.team,
            published: common.published,
            updated: common.updated,
            followers: common.followers,
            license: common.license,
            versions: [version],
            gameVersions: common.gameVersions,
            loaders: common.loaders,
            type: common.type,
            fileName: fileName
        )
    }

    /// Use file names to create the most basic template ModrinthProjectDetail
    private func createFallbackDetailFromFileName(
        fileURL: URL
    ) -> ModrinthProjectDetail {
        let (fileName, baseFileName) = createBaseFallbackDetail(fileURL: fileURL)
        let common = createCommonFallbackFields(fileName: fileName, baseFileName: baseFileName)

        return ModrinthProjectDetail(
            slug: baseFileName.lowercased().replacingOccurrences(
                of: " ",
                with: "-"
            ),
            title: baseFileName,
            description: common.description,
            categories: common.categories,
            clientSide: common.clientSide,
            serverSide: common.serverSide,
            body: common.body,
            additionalCategories: common.additionalCategories,
            issuesUrl: common.issuesUrl,
            sourceUrl: common.sourceUrl,
            wikiUrl: common.wikiUrl,
            discordUrl: common.discordUrl,
            projectType: common.projectType,
            downloads: common.downloads,
            iconUrl: common.iconUrl,
            id: "file_\(baseFileName)_\(UUID().uuidString.prefix(8))",
            team: common.team,
            published: common.published,
            updated: common.updated,
            followers: common.followers,
            license: common.license,
            versions: ["unknown"],
            gameVersions: common.gameVersions,
            loaders: common.loaders,
            type: common.type,
            fileName: fileName
        )
    }
}

extension ModScanner {
    // MARK: - public helper method

    /// Read directory and filter jar/zip files (throws exception version)
    private func readJarZipFiles(from dir: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw GlobalError.resource(
                chineseMessage: "目录不存在: \(dir.lastPathComponent)",
                i18nKey: "Directory Not Found",
                level: .silent
            )
        }

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw GlobalError.fileSystem(
                chineseMessage:
                    "读取目录失败: \(dir.lastPathComponent), 错误: \(error.localizedDescription)",
                i18nKey: "Directory Read Failed",
                level: .silent
            )
        }

        return files.filter {
            ["jar", "zip", "disable"].contains($0.pathExtension.lowercased())
        }
    }

    /// Read the directory and filter jar/zip files (silent version, returns an empty array when the directory does not exist)
    private func readJarZipFilesSilent(from dir: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return []
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )
            return files.filter {
                ["jar", "zip", "disable"].contains($0.pathExtension.lowercased())
            }
        } catch {
            return []
        }
    }

    /// Check if the mod is installed
    private func checkModInstalledCore(
        hash: String,
        gameName: String
    ) async -> Bool {
        let cachedMods = await ModInstallationCache.shared.getAllModsInstalled(for: gameName)
        return cachedMods.contains(hash)
    }

    /// Get all jar/zip files in the directory and their hash and cache details (silent version)
    public func localModDetails(in dir: URL) -> [(
        file: URL, hash: String, detail: ModrinthProjectDetail?
    )] {
        do {
            return try localModDetailsThrowing(in: dir)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取本地 mod 详情失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    /// Get all jar/zip files in the directory and their hash and cache details (throws exception version)
    public func localModDetailsThrowing(in dir: URL) throws -> [(
        file: URL, hash: String, detail: ModrinthProjectDetail?
    )] {
        let jarFiles = try readJarZipFiles(from: dir)
        return jarFiles.compactMap { fileURL in
            if let hash = ModScanner.sha1Hash(of: fileURL) {
                var detail = getModCacheFromDatabase(hash: hash)

                // If it is not found in the cache, use the cover-up strategy to create basic information
                if detail == nil {
                    detail = createFallbackDetailFromFileName(fileURL: fileURL)
                    // Save detailed information to the cache to avoid repeated creation
                    if let detail = detail {
                        saveToCache(hash: hash, detail: detail)
                    }
                } else {
                    // Update file name to current actual file name (may have been renamed to .disabled)
                    detail?.fileName = fileURL.lastPathComponent
                }

                return (file: fileURL, hash: hash, detail: detail)
            }
            return nil
        }
    }

    /// Asynchronous scan: only get all detailId (silent version)
    /// Execute in background thread, only read from cache, do not create fallback
    public func scanAllDetailIds(
        in dir: URL,
        completion: @escaping (Set<String>) -> Void
    ) {
        Task {
            do {
                let detailIds = try await scanAllDetailIdsThrowing(in: dir)
                completion(detailIds)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("扫描所有 detailId 失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
                completion(Set<String>())
            }
        }
    }

    // Return Set to improve lookup performance (O(1))
    public func scanAllDetailIdsThrowing(in dir: URL) async throws -> Set<String> {
        // If it is the mods directory, the cache will be returned first
        if isModsDirectory(dir) {
            if let gameName = extractGameName(from: dir) {
                // Check if cache exists (return cache even if empty)
                let hasCache = await ModInstallationCache.shared.hasCache(for: gameName)
                if hasCache {
                    let cachedMods = await ModInstallationCache.shared.getAllModsInstalled(for: gameName)
                    return cachedMods
                }
            }
        }

        // Perform file system operations on a background thread
        return try await Task.detached(priority: .userInitiated) {
            let jarFiles = try self.readJarZipFiles(from: dir)

            // Use TaskGroup to concurrently calculate hash and read cache
            let concurrentCount = GeneralSettingsManager.shared.concurrentDownloads
            let semaphore = AsyncSemaphore(value: concurrentCount)

            return await withTaskGroup(of: String?.self) { group in
                for fileURL in jarFiles {
                    group.addTask {
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }

                        guard let hash = ModScanner.sha1Hash(of: fileURL) else {
                            return nil
                        }

                        // Return hash directly without using slug
                        return hash
                    }
                }

                var hashes: Set<String> = []
                for await hash in group {
                    if let hash = hash {
                        hashes.insert(hash)
                    }
                }

                // If it is the mods directory, automatically cache the results
                if self.isModsDirectory(dir) {
                    if let gameName = self.extractGameName(from: dir) {
                        await ModInstallationCache.shared.setAllModsInstalled(
                            for: gameName,
                            hashes: hashes
                        )
                    }
                }

                return hashes
            }
        }.value
    }

    public func scanGameModsDirectory(game: GameVersionInfo) async {
        let modsDir = AppPaths.modsDirectory(gameName: game.gameName)

        // Check if directory exists
        guard FileManager.default.fileExists(atPath: modsDir.path) else {
            Logger.shared.debug("游戏 \(game.gameName) 的 mods 目录不存在，跳过扫描")
            return
        }

        do {
            let detailIds = try await scanAllDetailIdsThrowing(in: modsDir)
            Logger.shared.debug("游戏 \(game.gameName) 扫描完成，发现 \(detailIds.count) 个 mod")
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.warning("扫描游戏 \(game.gameName) 的 mods 目录失败: \(globalError.chineseMessage)")
            // No error notifications are shown because this is a background scan
        }
    }

    public func scanGameModsDirectorySync(game: GameVersionInfo) {
        let modsDir = AppPaths.modsDirectory(gameName: game.gameName)

        // Check if directory exists
        guard FileManager.default.fileExists(atPath: modsDir.path) else {
            Logger.shared.debug("游戏 \(game.gameName) 的 mods 目录不存在，跳过扫描")
            return
        }

        // Use Task to wait synchronously for asynchronous operations to complete
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            do {
                let detailIds = try await scanAllDetailIdsThrowing(in: modsDir)
                Logger.shared.debug("游戏 \(game.gameName) 扫描完成，发现 \(detailIds.count) 个 mod")
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.warning("扫描游戏 \(game.gameName) 的 mods 目录失败: \(globalError.chineseMessage)")
                // No error notifications are shown because this is a background scan
            }
        }
        semaphore.wait()
    }

    private func isModsDirectory(_ dir: URL) -> Bool {
        dir.lastPathComponent.lowercased() == "mods"
    }

    // mods directory structure: profileRootDirectory/gameName/mods
    private func extractGameName(from modsDir: URL) -> String? {
        let parentDir = modsDir.deletingLastPathComponent()
        return parentDir.lastPathComponent
    }

    /// Synchronization: Check cache only (checked by file hash)
    func isModInstalledSync(hash: String, in modsDir: URL) -> Bool {
        do {
            return try isModInstalledSyncThrowing(
                hash: hash,
                in: modsDir
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("检查 mod 安装状态失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }

    /// Synchronization: only check cache (throws exception version)
    func isModInstalledSyncThrowing(
        hash: String,
        in modsDir: URL
    ) throws -> Bool {
        guard let gameName = extractGameName(from: modsDir) else {
            return false
        }

        // Use DispatchSemaphore to wait for asynchronous results in a synchronous function
        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        Task {
            result = await checkModInstalledCore(hash: hash, gameName: gameName)
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    /// Asynchronous: only check cache (silent version)
    func isModInstalled(
        hash: String,
        in modsDir: URL,
        completion: @escaping (Bool) -> Void
    ) {
        Task {
            do {
                let result = try await isModInstalledThrowing(
                    hash: hash,
                    in: modsDir
                )
                completion(result)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error(
                    "检查 mod 安装状态失败: \(globalError.chineseMessage)"
                )
                GlobalErrorHandler.shared.handle(globalError)
                completion(false)
            }
        }
    }

    /// Asynchronous: only check cache (throw exception version)
    func isModInstalledThrowing(
        hash: String,
        in modsDir: URL
    ) async throws -> Bool {
        guard let gameName = extractGameName(from: modsDir) else {
            return false
        }

        return await checkModInstalledCore(hash: hash, gameName: gameName)
    }

    /// Scan directory and return all identified ModrinthProjectDetail (silent version)
    func scanResourceDirectory(
        _ dir: URL,
        completion: @escaping ([ModrinthProjectDetail]) -> Void
    ) {
        Task {
            do {
                let results = try await scanResourceDirectoryThrowing(dir)
                completion(results)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("扫描资源目录失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
                completion([])
            }
        }
    }

    /// Scan the directory and return all identified ModrinthProjectDetail (throws exception version)
    func scanResourceDirectoryThrowing(
        _ dir: URL
    ) async throws -> [ModrinthProjectDetail] {
        let jarFiles = try readJarZipFiles(from: dir)
        if jarFiles.isEmpty {
            return []
        }

        // Create a semaphore to control the number of concurrencies
        let concurrentCount = GeneralSettingsManager.shared.concurrentDownloads
        let semaphore = AsyncSemaphore(value: concurrentCount)

        // Scan files concurrently using TaskGroup
        let results = await withTaskGroup(of: ModrinthProjectDetail?.self) { group in
            for fileURL in jarFiles {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    return try? await self.getModrinthProjectDetailThrowing(
                        for: fileURL
                    )
                }
            }

            // Collect results
            var results: [ModrinthProjectDetail] = []
            for await result in group {
                if let detail = result {
                    results.append(detail)
                }
            }
            return results
        }

        return results
    }

    // MARK: - Page scanning

    /// Calculate paging range
    private func calculatePageRange(
        totalCount: Int,
        page: Int,
        pageSize: Int
    ) -> (startIndex: Int, endIndex: Int, hasMore: Bool)? {
        guard totalCount > 0 else {
            return nil
        }

        let safePage = max(page, 1)
        let safePageSize = max(pageSize, 1)
        let startIndex = (safePage - 1) * safePageSize
        let endIndex = min(startIndex + safePageSize, totalCount)

        guard startIndex < totalCount else {
            return nil
        }

        return (startIndex, endIndex, endIndex < totalCount)
    }

    /// Concurrently scan the file list and return details
    private func scanFilesConcurrently(
        fileURLs: [URL],
        semaphore: AsyncSemaphore
    ) async -> [ModrinthProjectDetail] {
        await withTaskGroup(of: ModrinthProjectDetail?.self) { group in
            for fileURL in fileURLs {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    return try? await self.getModrinthProjectDetailThrowing(
                        for: fileURL
                    )
                }
            }

            var results: [ModrinthProjectDetail] = []
            for await result in group {
                if let detail = result {
                    results.append(detail)
                }
            }
            return results
        }
    }

    /// Get a list of all jar/zip files in the directory (no parsing details, fast)
    func getAllResourceFiles(_ dir: URL) -> [URL] {
        do {
            return try getAllResourceFilesThrowing(dir)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("获取资源文件列表失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    /// Get the list of all jar/zip files in the directory (throws exception version)
    func getAllResourceFilesThrowing(_ dir: URL) throws -> [URL] {
        // Returns an empty array if the directory does not exist (no exception is thrown as this is the normal case)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return []
        }

        return try readJarZipFiles(from: dir)
    }

    /// Scan the directory in pages and parse only the files on the current page (silent version)
    func scanResourceDirectoryPage(
        _ dir: URL,
        page: Int,
        pageSize: Int,
        completion: @escaping ([ModrinthProjectDetail], Bool) -> Void
    ) {
        Task {
            do {
                let (results, hasMore) = try await scanResourceDirectoryPageThrowing(
                    dir,
                    page: page,
                    pageSize: pageSize
                )
                completion(results, hasMore)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("分页扫描资源目录失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
                completion([], false)
            }
        }
    }

    /// Paging scanning based on the file list, only parsing the files of the current page (silent version)
    func scanResourceFilesPage(
        fileURLs: [URL],
        page: Int,
        pageSize: Int,
        completion: @escaping ([ModrinthProjectDetail], Bool) -> Void
    ) {
        Task {
            do {
                let (results, hasMore) = try await scanResourceFilesPageThrowing(
                    fileURLs: fileURLs,
                    page: page,
                    pageSize: pageSize
                )
                completion(results, hasMore)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("分页扫描资源文件失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
                completion([], false)
            }
        }
    }

    /// Paging scanning based on the file list, only parsing the files of the current page (throws an exception version)
    func scanResourceFilesPageThrowing(
        fileURLs: [URL],
        page: Int,
        pageSize: Int
    ) async throws -> ([ModrinthProjectDetail], Bool) {
        guard let pageRange = calculatePageRange(
            totalCount: fileURLs.count,
            page: page,
            pageSize: pageSize
        ) else {
            return ([], false)
        }

        let pageFiles = Array(fileURLs[pageRange.startIndex..<pageRange.endIndex])
        let concurrentCount = GeneralSettingsManager.shared.concurrentDownloads
        let semaphore = AsyncSemaphore(value: concurrentCount)
        let results = await scanFilesConcurrently(fileURLs: pageFiles, semaphore: semaphore)

        return (results, pageRange.hasMore)
    }

    /// Paging scans the directory and only parses the files on the current page (throws an exception version)
    func scanResourceDirectoryPageThrowing(
        _ dir: URL,
        page: Int,
        pageSize: Int
    ) async throws -> ([ModrinthProjectDetail], Bool) {
        let jarFiles = try readJarZipFiles(from: dir)
        return try await scanResourceFilesPageThrowing(
            fileURLs: jarFiles,
            page: page,
            pageSize: pageSize
        )
    }
}

// MARK: - Mod Installation Cache
extension ModScanner {
    actor ModInstallationCache {
        static let shared = ModInstallationCache()

        private var cache: [String: Set<String>] = [:]

        private init() {}

        func addHash(_ hash: String, to gameName: String) {
            if var cached = cache[gameName] {
                cached.insert(hash)
                cache[gameName] = cached
            } else {
                // If cache does not exist, create a new collection
                cache[gameName] = [hash]
            }
        }

        func removeHash(_ hash: String, from gameName: String) {
            if var cached = cache[gameName] {
                cached.remove(hash)
                cache[gameName] = cached
            }
        }

        func getAllModsInstalled(for gameName: String) -> Set<String> {
            cache[gameName] ?? Set<String>()
        }

        func hasCache(for gameName: String) -> Bool {
            cache[gameName] != nil
        }

        func setAllModsInstalled(for gameName: String, hashes: Set<String>) {
            cache[gameName] = hashes
        }

        func removeGame(gameName: String) {
            cache.removeValue(forKey: gameName)
        }
    }

    func addModHash(_ hash: String, to gameName: String) {
        Task {
            await ModInstallationCache.shared.addHash(hash, to: gameName)
        }
    }

    func removeModHash(_ hash: String, from gameName: String) {
        Task {
            await ModInstallationCache.shared.removeHash(hash, from: gameName)
        }
    }

    func getAllModsInstalled(for gameName: String) async -> Set<String> {
        await ModInstallationCache.shared.getAllModsInstalled(for: gameName)
    }

    func clearModCache(for gameName: String) async {
        await ModInstallationCache.shared.removeGame(gameName: gameName)
    }
}
