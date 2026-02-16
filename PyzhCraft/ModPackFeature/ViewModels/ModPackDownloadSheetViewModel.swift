import CommonCrypto
import SwiftUI
import ZIPFoundation

private enum ModrinthIndexError: Error {
    case emptyIndex
}

// MARK: - View Model
@MainActor
class ModPackDownloadSheetViewModel: ObservableObject {
    @Published var projectDetail: ModrinthProjectDetail?
    @Published var availableGameVersions: [String] = []
    @Published var filteredModPackVersions: [ModrinthProjectDetailVersion] = []
    @Published var isLoadingModPackVersions = false
    @Published var isLoadingProjectDetails = true
    @Published var lastParsedIndexInfo: ModrinthIndexInfo?

    // Integration package installation progress status
    @Published var modPackInstallState = ModPackInstallState()

    // Integration package file download progress status
    @Published var modPackDownloadProgress: Int64 = 0  // Number of bytes downloaded
    @Published var modPackTotalSize: Int64 = 0  // Total file size
    // MARK: - Memory Management
    /// Clean up index data no longer needed to free up memory
    /// Called after ModPack installation is complete
    func clearParsedIndexInfo() {
        lastParsedIndexInfo = nil
    }

    /// Clean up all integration package import related data and temporary files
    func cleanupAllData() {
        // Clean index data
        clearParsedIndexInfo()

        // Clean project details data
        projectDetail = nil
        availableGameVersions = []
        filteredModPackVersions = []
        allModPackVersions = []

        // Clean installation status
        modPackInstallState.reset()

        // Clean download progress
        modPackDownloadProgress = 0
        modPackTotalSize = 0

        // Clean temporary files
        cleanupTempFiles()
    }

    /// Clean up temporary files (modpack_download and modpack_extraction directories) and execute them in the background to avoid blocking the main thread
    func cleanupTempFiles() {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let tempBaseDir = fm.temporaryDirectory
            let downloadDir = tempBaseDir.appendingPathComponent("modpack_download")
            if fm.fileExists(atPath: downloadDir.path) {
                do {
                    try fm.removeItem(at: downloadDir)
                    Logger.shared.info("已清理临时下载目录: \(downloadDir.path)")
                } catch {
                    Logger.shared.warning("清理临时下载目录失败: \(error.localizedDescription)")
                }
            }
            let extractionDir = tempBaseDir.appendingPathComponent("modpack_extraction")
            if fm.fileExists(atPath: extractionDir.path) {
                do {
                    try fm.removeItem(at: extractionDir)
                    Logger.shared.info("已清理临时解压目录: \(extractionDir.path)")
                } catch {
                    Logger.shared.warning("清理临时解压目录失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private var allModPackVersions: [ModrinthProjectDetailVersion] = []
    private var gameRepository: GameRepository?

    func setGameRepository(_ repository: GameRepository) {
        self.gameRepository = repository
    }

    /// Apply preloaded project details to avoid repeated loading within the sheet
    func applyPreloadedDetail(_ detail: ModrinthProjectDetail) {
        projectDetail = detail
        availableGameVersions = CommonUtil.sortMinecraftVersions(detail.gameVersions)
        isLoadingProjectDetails = false
    }

    // MARK: - Data Loading
    func loadProjectDetails(projectId: String) async {
        isLoadingProjectDetails = true

        do {
            projectDetail =
                try await ModrinthService.fetchProjectDetailsThrowing(
                    id: projectId
                )
            let gameVersions = projectDetail?.gameVersions ?? []
            availableGameVersions = CommonUtil.sortMinecraftVersions(gameVersions)
        } catch {
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
        }

        isLoadingProjectDetails = false
    }

    func loadModPackVersions(for gameVersion: String) async {
        guard let projectDetail = projectDetail else { return }

        isLoadingModPackVersions = true

        do {
            allModPackVersions =
                try await ModrinthService.fetchProjectVersionsThrowing(
                    id: projectDetail.id
                )
            filteredModPackVersions = allModPackVersions
                .filter { version in
                    version.gameVersions.contains(gameVersion)
                }
                .sorted { version1, version2 in
                    // Sort by release date, newest first
                    version1.datePublished > version2.datePublished
                }
        } catch {
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
        }

        isLoadingModPackVersions = false
    }

    // MARK: - File Operations

    func downloadModPackFile(
        file: ModrinthVersionFile,
        projectDetail: ModrinthProjectDetail
    ) async -> URL? {
        do {
            // Create temporary directory
            let tempDir = try createTempDirectory(for: "modpack_download")
            let savePath = tempDir.appendingPathComponent(file.filename)

            // Reset download progress
            modPackDownloadProgress = 0
            modPackTotalSize = 0

            // Use a download method that supports progress callbacks
            do {
                _ = try await downloadFileWithProgress(
                    urlString: file.url,
                    destinationURL: savePath,
                    expectedSha1: file.hashes.sha1
                )
                return savePath
            } catch {
                let globalError = GlobalError.from(error)
                handleDownloadError(
                    globalError.chineseMessage,
                    globalError.i18nKeyString
                )
                return nil
            }
        } catch {
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }
    /// Download files and support progress callbacks
    private func downloadFileWithProgress(
        urlString: String,
        destinationURL: URL,
        expectedSha1: String?
    ) async throws -> URL {
        // Create URL
        guard let url = URL(string: urlString) else {
            throw GlobalError.validation(i18nKey: "Invalid Download URL",
                level: .notification
            )
        }

        // Apply proxy (if required)
        let finalURL: URL = {
            if let host = url.host,
               host == "github.com" || host == "raw.githubusercontent.com" {
                return URLConfig.applyGitProxyIfNeeded(url)
            }
            return url
        }()

        // Create target directory
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Check if the file already exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            if let expectedSha1 = expectedSha1, !expectedSha1.isEmpty {
                let actualSha1 = try DownloadManager.calculateFileSHA1(at: destinationURL)
                if actualSha1 == expectedSha1 {
                    // The file already exists and the verification has passed, and the setting progress is completed
                    if let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
                       let fileSize = attributes[.size] as? Int64 {
                        modPackTotalSize = fileSize
                        modPackDownloadProgress = fileSize
                    }
                    return destinationURL
                }
            } else {
                // Without SHA1 verification, return directly
                if let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
                   let fileSize = attributes[.size] as? Int64 {
                    modPackTotalSize = fileSize
                    modPackDownloadProgress = fileSize
                }
                return destinationURL
            }
        }

        // Get file size
        let fileSize = try await getFileSize(from: finalURL)
        modPackTotalSize = fileSize

        // Create a progress tracker
        let progressCallback: (Int64, Int64) -> Void = { [weak self] downloadedBytes, totalBytes in
            Task { @MainActor in
                self?.modPackDownloadProgress = downloadedBytes
                if totalBytes > 0 {
                    self?.modPackTotalSize = totalBytes
                }
            }
        }
        let progressTracker = ModPackDownloadProgressTracker(
            totalSize: fileSize,
            progressCallback: progressCallback
        )

        // Create URLSession
        let config = URLSessionConfiguration.default
        let session = URLSession(
            configuration: config,
            delegate: progressTracker,
            delegateQueue: nil
        )

        // Download file
        return try await withCheckedThrowingContinuation { continuation in
            progressTracker.completionHandler = { result in
                switch result {
                case .success(let tempURL):
                    do {
                        // SHA1 verification
                        if let expectedSha1 = expectedSha1, !expectedSha1.isEmpty {
                            let actualSha1 = try DownloadManager.calculateFileSHA1(at: tempURL)
                            if actualSha1 != expectedSha1 {
                                throw GlobalError.validation(i18nKey: "SHA1 Check Failed",
                                    level: .notification
                                )
                            }
                        }

                        // Move files to destination
                        if fileManager.fileExists(atPath: destinationURL.path) {
                            try fileManager.replaceItem(
                                at: destinationURL,
                                withItemAt: tempURL,
                                backupItemName: nil,
                                options: [],
                                resultingItemURL: nil
                            )
                        } else {
                            try fileManager.moveItem(at: tempURL, to: destinationURL)
                        }

                        continuation.resume(returning: destinationURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            let downloadTask = session.downloadTask(with: finalURL)
            downloadTask.resume()
        }
    }

    /// Get remote file size
    private func getFileSize(from url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GlobalError.download(i18nKey: "Cannot get file size",
                level: .notification
            )
        }

        guard let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
              let fileSize = Int64(contentLength) else {
            throw GlobalError.download(i18nKey: "Cannot get file size",
                level: .notification
            )
        }

        return fileSize
    }
    func downloadGameIcon(
        projectDetail: ModrinthProjectDetail,
        gameName: String
    ) async -> String? {
        do {
            // Verify icon URL
            guard let iconUrl = projectDetail.iconUrl else {
                return nil
            }

            // Get game directory
            let gameDirectory = AppPaths.profileDirectory(gameName: gameName)

            // Make sure the game directory exists
            try FileManager.default.createDirectory(
                at: gameDirectory,
                withIntermediateDirectories: true
            )

            // Determine icon file name and path
            let iconFileName = "default_game_icon.png"
            let iconPath = gameDirectory.appendingPathComponent(iconFileName)

            // Use DownloadManager to download icon files (error handling and temporary file cleaning included)
            do {
                _ = try await DownloadManager.downloadFile(
                    urlString: iconUrl,
                    destinationURL: iconPath,
                    expectedSha1: nil
                )
                return iconFileName
            } catch {
                handleDownloadError(
                    "下载游戏图标失败",
                    "Icon download failed"
                )
                return nil
            }
        } catch {
            handleDownloadError(
                "下载游戏图标失败",
                "Icon download failed"
            )
            return nil
        }
    }

    func extractModPack(modPackPath: URL) async -> URL? {
        do {
            let fileExtension = modPackPath.pathExtension.lowercased()

            // Check file format
            guard fileExtension == "zip" || fileExtension == "mrpack" else {
                handleDownloadError(
                    "不支持的整合包格式: \(fileExtension)",
                    "Unsupported modpack format"
                )
                return nil
            }

            // Check if the source file exists
            let modPackPathString = modPackPath.path
            guard FileManager.default.fileExists(atPath: modPackPathString)
            else {
                handleDownloadError(
                    "整合包文件不存在: \(modPackPathString)",
                    "File Not Found"
                )
                return nil
            }

            // Get source file size
            let sourceAttributes = try FileManager.default.attributesOfItem(
                atPath: modPackPathString
            )
            let sourceSize = sourceAttributes[.size] as? Int64 ?? 0

            guard sourceSize > 0 else {
                handleDownloadError("整合包文件为空", "Modpack is empty")
                return nil
            }

            // Create a temporary decompression directory
            let tempDir = try createTempDirectory(for: "modpack_extraction")

            // Unzip files using ZIPFoundation
            try FileManager.default.unzipItem(at: modPackPath, to: tempDir)

            // Keep only critical logs
            return tempDir
        } catch {
            handleDownloadError(
                "解压整合包失败: \(error.localizedDescription)",
                "Extraction failed"
            )
            return nil
        }
    }

    func parseModrinthIndex(extractedPath: URL) async -> ModrinthIndexInfo? {
            // Parse Modrinth format first
        if let modrinthInfo = await parseModrinthIndexInternal(extractedPath: extractedPath) {
            return modrinthInfo
        }

        // If it is not Modrinth format, try to parse CurseForge format
        if let modrinthInfo = await CurseForgeManifestParser.parseManifest(extractedPath: extractedPath) {
            // Set lastParsedIndexInfo to show mod loader progress bar
            lastParsedIndexInfo = modrinthInfo
            return modrinthInfo
        }

        // None of the formats are supported
        handleDownloadError(
            "不支持的整合包格式，请使用 Modrinth (.mrpack) 或 CurseForge (.zip) 格式的整合包",
            "Unsupported modpack format"
        )
        return nil
    }

    private func parseModrinthIndexInternal(extractedPath: URL) async -> ModrinthIndexInfo? {
        let indexPath = extractedPath.appendingPathComponent(AppConstants.modrinthIndexFileName)
        do {
            let modPackIndex: ModrinthIndex? = try await Task.detached(priority: .userInitiated) { () throws -> ModrinthIndex? in
                let indexPathString = indexPath.path
                guard FileManager.default.fileExists(atPath: indexPathString) else { return nil }
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: indexPathString)
                let fileSize = fileAttributes[.size] as? Int64 ?? 0
                guard fileSize > 0 else { throw ModrinthIndexError.emptyIndex }
                let indexData = try Data(contentsOf: indexPath)
                return try JSONDecoder().decode(ModrinthIndex.self, from: indexData)
            }.value

            guard let modPackIndex = modPackIndex else { return nil }
            let loaderInfo = determineLoaderInfo(from: modPackIndex.dependencies)
            let indexInfo = ModrinthIndexInfo(
                gameVersion: modPackIndex.dependencies.minecraft ?? "unknown",
                loaderType: loaderInfo.type,
                loaderVersion: loaderInfo.version,
                modPackName: modPackIndex.name,
                modPackVersion: modPackIndex.versionId,
                summary: modPackIndex.summary,
                files: modPackIndex.files,
                dependencies: modPackIndex.dependencies.dependencies ?? []
            )
            lastParsedIndexInfo = indexInfo
            return indexInfo
        } catch ModrinthIndexError.emptyIndex {
            handleDownloadError("modrinth.index.json 文件为空", "Modrinth index is empty")
            return nil
        } catch {
            if error is DecodingError {
                Logger.shared.error("解析 modrinth.index.json 失败: JSON 格式错误")
            }
            return nil
        }
    }

    // MARK: - Helper Methods

    private func createTempDirectory(for purpose: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(purpose)
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        return tempDir
    }

    private func validateFileSize(
        tempFileURL: URL,
        httpResponse: HTTPURLResponse
    ) -> Bool {
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(
                atPath: tempFileURL.path
            )
            let actualSize = fileAttributes[.size] as? Int64 ?? 0

            if let expectedSize = httpResponse.value(
                forHTTPHeaderField: "Content-Length"
            ), let expectedSizeInt = Int64(expectedSize), actualSize != expectedSizeInt {
                handleDownloadError(
                    "文件大小不匹配，预期: \(expectedSizeInt)，实际: \(actualSize)",
                    "File size mismatch"
                )
                return false
            }
            return true
        } catch {
            handleDownloadError(
                "无法获取文件大小: \(error.localizedDescription)",
                "File Read Failed"
            )
            return false
        }
    }

    private func validateFileIntegrity(
        tempFileURL: URL,
        expectedSha1: String
    ) -> Bool {
        do {
            let actualSha1 = try SHA1Calculator.sha1(ofFileAt: tempFileURL)
            if actualSha1 != expectedSha1 {
                handleDownloadError(
                    "文件校验失败，SHA1不匹配",
                    "SHA1 mismatch"
                )
                return false
            }
            return true
        } catch {
            handleDownloadError(
                "SHA1校验失败: \(error.localizedDescription)",
                "SHA1 Check Failed"
            )
            return false
        }
    }

    private func handleDownloadError(_ message: String, _ i18nKey: String) {
        let globalError = GlobalError(
            type: .resource,
            i18nKey: i18nKey,
            level: .notification
        )
        GlobalErrorHandler.shared.handle(globalError)
    }

    private func determineLoaderInfo(
        from dependencies: ModrinthIndexDependencies
    ) -> (type: String, version: String) {
        // Check various loaders, sorted by priority
        // Check formats with -loader suffix first
        if let forgeVersion = dependencies.forgeLoader {
            return ("forge", forgeVersion)
        } else if let fabricVersion = dependencies.fabricLoader {
            return ("fabric", fabricVersion)
        } else if let quiltVersion = dependencies.quiltLoader {
            return ("quilt", quiltVersion)
        } else if let neoforgeVersion = dependencies.neoforgeLoader {
            return ("neoforge", neoforgeVersion)
        }

        // Check format without -loader suffix
        if let forgeVersion = dependencies.forge {
            return ("forge", forgeVersion)
        } else if let fabricVersion = dependencies.fabric {
            return ("fabric", fabricVersion)
        } else if let quiltVersion = dependencies.quilt {
            return ("quilt", quiltVersion)
        } else if let neoforgeVersion = dependencies.neoforge {
            return ("neoforge", neoforgeVersion)
        }

        // Returns to vanilla by default
        return ("vanilla", "unknown")
    }
}
// MARK: - Modrinth Index Models
struct ModrinthIndex: Codable {
    let formatVersion: Int
    let game: String
    let versionId: String
    let name: String
    let summary: String?
    let files: [ModrinthIndexFile]
    let dependencies: ModrinthIndexDependencies

    enum CodingKeys: String, CodingKey {
        case formatVersion, game, versionId, name, summary, files, dependencies
    }
}

// MARK: - File Hashes (optimize memory usage)
/// Optimized file hash structure, using structures instead of dictionaries to reduce memory usage
/// Common hashes (sha1, sha512) are stored as attributes, other hashes are stored in an optional dictionary
struct ModrinthIndexFileHashes: Codable {
    /// SHA1 hash (most commonly used)
    let sha1: String?
    /// SHA512 hash (less commonly used)
    let sha512: String?
    /// Other hash types (less commonly used, lazy storage)
    let other: [String: String]?

    /// Created from dictionary (for JSON decoding)
    init(from dict: [String: String]) {
        self.sha1 = dict["sha1"]
        self.sha512 = dict["sha512"]

        // Only store non-standard hashes
        var otherDict: [String: String] = [:]
        for (key, value) in dict {
            if key != "sha1" && key != "sha512" {
                otherDict[key] = value
            }
        }
        self.other = otherDict.isEmpty ? nil : otherDict
    }

    /// Custom decoding, decoding from JSON dictionary
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: String].self)
        self.init(from: dict)
    }

    /// Encoded into dictionary format (for JSON encoding)
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var dict: [String: String] = [:]

        if let sha1 = sha1 {
            dict["sha1"] = sha1
        }
        if let sha512 = sha512 {
            dict["sha512"] = sha512
        }
        if let other = other {
            dict.merge(other) { _, new in new }
        }

        try container.encode(dict)
    }

    /// Dictionary access compatibility (backward compatibility)
    subscript(key: String) -> String? {
        switch key {
        case "sha1": sha1
        case "sha512": sha512
        default: other?[key]
        }
    }
}

struct ModrinthIndexFile: Codable {
    let path: String
    let hashes: ModrinthIndexFileHashes
    let downloads: [String]
    let fileSize: Int
    let env: ModrinthIndexFileEnv?
    let source: FileSource?
    // CurseForge-specific fields, used to delay obtaining file details
    let curseForgeProjectId: Int?
    let curseForgeFileId: Int?

    enum CodingKeys: String, CodingKey {
        case path, hashes, downloads, fileSize, env, source, curseForgeProjectId, curseForgeFileId
    }

    // Provide a default initializer for compatibility
    init(
        path: String,
        hashes: ModrinthIndexFileHashes,
        downloads: [String],
        fileSize: Int,
        env: ModrinthIndexFileEnv? = nil,
        source: FileSource? = nil,
        curseForgeProjectId: Int? = nil,
        curseForgeFileId: Int? = nil
    ) {
        self.path = path
        self.hashes = hashes
        self.downloads = downloads
        self.fileSize = fileSize
        self.env = env
        self.source = source
        self.curseForgeProjectId = curseForgeProjectId
        self.curseForgeFileId = curseForgeFileId
    }

    // Initializers compatible with older versions of dictionary formats
    init(
        path: String,
        hashes: [String: String],
        downloads: [String],
        fileSize: Int,
        env: ModrinthIndexFileEnv? = nil,
        source: FileSource? = nil,
        curseForgeProjectId: Int? = nil,
        curseForgeFileId: Int? = nil
    ) {
        self.path = path
        self.hashes = ModrinthIndexFileHashes(from: hashes)
        self.downloads = downloads
        self.fileSize = fileSize
        self.env = env
        self.source = source
        self.curseForgeProjectId = curseForgeProjectId
        self.curseForgeFileId = curseForgeFileId
    }
}

enum FileSource: String, Codable {
    case modrinth, curseforge
}

struct ModrinthIndexFileEnv: Codable {
    let client: String?
    let server: String?
}

struct ModrinthIndexDependencies: Codable {
    let minecraft: String?
    let forgeLoader: String?
    let fabricLoader: String?
    let quiltLoader: String?
    let neoforgeLoader: String?
    // Add properties without -loader suffix
    let forge: String?
    let fabric: String?
    let quilt: String?
    let neoforge: String?
    let dependencies: [ModrinthIndexProjectDependency]?

    enum CodingKeys: String, CodingKey {
        case minecraft,
             forgeLoader = "forge-loader",
             fabricLoader = "fabric-loader",
             quiltLoader = "quilt-loader",
             neoforgeLoader = "neoforge-loader",
             forge, fabric, quilt, neoforge, dependencies
    }
}

struct ModrinthIndexProjectDependency: Codable {
    let projectId: String?
    let versionId: String?
    let dependencyType: String

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id",
             versionId = "version_id",
             dependencyType = "dependency_type"
    }
}

// MARK: - Modrinth Index Info
struct ModrinthIndexInfo {
    let gameVersion: String
    let loaderType: String
    let loaderVersion: String
    let modPackName: String
    let modPackVersion: String
    let summary: String?
    let files: [ModrinthIndexFile]
    let dependencies: [ModrinthIndexProjectDependency]
    let source: FileSource

    init(
        gameVersion: String,
        loaderType: String,
        loaderVersion: String,
        modPackName: String,
        modPackVersion: String,
        summary: String?,
        files: [ModrinthIndexFile],
        dependencies: [ModrinthIndexProjectDependency],
        source: FileSource = .modrinth
    ) {
        self.gameVersion = gameVersion
        self.loaderType = loaderType
        self.loaderVersion = loaderVersion
        self.modPackName = modPackName
        self.modPackVersion = modPackVersion
        self.summary = summary
        self.files = files
        self.dependencies = dependencies
        self.source = source
    }
}
// MARK: - ModPack Install State
@MainActor
class ModPackInstallState: ObservableObject {
    @Published var isInstalling = false
    @Published var filesProgress: Double = 0
    @Published var dependenciesProgress: Double = 0
    @Published var overridesProgress: Double = 0
    @Published var currentFile: String = ""
    @Published var currentDependency: String = ""
    @Published var currentOverride: String = ""
    @Published var filesTotal: Int = 0
    @Published var dependenciesTotal: Int = 0
    @Published var overridesTotal: Int = 0
    @Published var filesCompleted: Int = 0
    @Published var dependenciesCompleted: Int = 0
    @Published var overridesCompleted: Int = 0

    func reset() {
        isInstalling = false
        filesProgress = 0
        dependenciesProgress = 0
        overridesProgress = 0
        currentFile = ""
        currentDependency = ""
        currentOverride = ""
        filesTotal = 0
        dependenciesTotal = 0
        overridesTotal = 0
        filesCompleted = 0
        dependenciesCompleted = 0
        overridesCompleted = 0
    }

    func startInstallation(
        filesTotal: Int,
        dependenciesTotal: Int,
        overridesTotal: Int = 0
    ) {
        self.filesTotal = filesTotal
        self.dependenciesTotal = dependenciesTotal
        // Only set total if overrides have not yet started to avoid overwriting completed progress
        if self.overridesTotal == 0 {
            self.overridesTotal = overridesTotal
        }
        self.isInstalling = true
        self.filesProgress = 0
        self.dependenciesProgress = 0
        // Only reset progress if overrides have not completed yet, retain progress of completed overrides
        if self.overridesCompleted == 0 {
            self.overridesProgress = 0
        }
        self.filesCompleted = 0
        self.dependenciesCompleted = 0
        // Keep completed overrides progress without resetting it
    }

    func updateFilesProgress(fileName: String, completed: Int, total: Int) {
        currentFile = fileName
        filesCompleted = completed
        filesTotal = total
        filesProgress = calculateProgress(completed: completed, total: total)
        objectWillChange.send()
    }

    func updateDependenciesProgress(
        dependencyName: String,
        completed: Int,
        total: Int
    ) {
        currentDependency = dependencyName
        dependenciesCompleted = completed
        dependenciesTotal = total
        dependenciesProgress = calculateProgress(
            completed: completed,
            total: total
        )
        objectWillChange.send()
    }

    func updateOverridesProgress(
        overrideName: String,
        completed: Int,
        total: Int
    ) {
        currentOverride = overrideName
        overridesCompleted = completed
        overridesTotal = total
        overridesProgress = calculateProgress(
            completed: completed,
            total: total
        )
        objectWillChange.send()
    }

    private func calculateProgress(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 0.0 }
        return max(0.0, min(1.0, Double(completed) / Double(total)))
    }
}
// MARK: - Download Progress Tracker
private class ModPackDownloadProgressTracker: NSObject, URLSessionDownloadDelegate {
    private let progressCallback: (Int64, Int64) -> Void
    private let totalFileSize: Int64
    var completionHandler: ((Result<URL, Error>) -> Void)?

    init(totalSize: Int64, progressCallback: @escaping (Int64, Int64) -> Void) {
        self.totalFileSize = totalSize
        self.progressCallback = progressCallback
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let actualTotalSize = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : totalFileSize
        if actualTotalSize > 0 {
            DispatchQueue.main.async { [weak self] in
                self?.progressCallback(totalBytesWritten, actualTotalSize)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        completionHandler?(.success(location))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            completionHandler?(.failure(error))
        }
    }
}
