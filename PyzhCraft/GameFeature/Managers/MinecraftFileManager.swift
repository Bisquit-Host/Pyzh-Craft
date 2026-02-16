import CommonCrypto
import Foundation

// MARK: - Constants
private enum Constants {
    static let metaSubdirectories = [
        AppConstants.DirectoryNames.versions,
        AppConstants.DirectoryNames.libraries,
        AppConstants.DirectoryNames.natives,
        AppConstants.DirectoryNames.assets,
        "\(AppConstants.DirectoryNames.assets)/indexes",
        "\(AppConstants.DirectoryNames.assets)/objects",
    ]
    static let assetChunkSize = 500
    static let downloadTimeout: TimeInterval = 30
    static let retryCount = 3
    static let retryDelay: TimeInterval = 2
    static let memoryBufferSize = 1024 * 1024  // 1MB buffer for file operations
}

// MARK: - MinecraftFileManager
class MinecraftFileManager {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let session: URLSession
    private let coreFilesCount = NSLockingCounter()
    private let resourceFilesCount = NSLockingCounter()
    private var coreTotalFiles = 0
    private var resourceTotalFiles = 0
    private let downloadQueue = DispatchQueue(
        label: "com.launcher.download",
        qos: .userInitiated
    )

    var onProgressUpdate: ((String, Int, Int, DownloadType) -> Void)?

    enum DownloadType {
        case core, resources
    }

    // MARK: - Initialization
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Constants.downloadTimeout
        config.timeoutIntervalForResource = Constants.downloadTimeout
        config.httpMaximumConnectionsPerHost =
            GeneralSettingsManager.shared.concurrentDownloads
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// Clean game folder (when download fails or cancels)
    /// - Parameter gameName: game name
    /// - Throws: GlobalError when the operation fails
    func cleanupGameDirectories(gameName: String) throws {
        let profileDirectory = AppPaths.profileDirectory(gameName: gameName)

        // Check if the game folder exists
        guard fileManager.fileExists(atPath: profileDirectory.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: profileDirectory)
        } catch {
            throw GlobalError.fileSystem(
                chineseMessage: "清理游戏文件夹失败",
                i18nKey: "Game Deletion Failed",
                level: .notification
            )
        }
    }

    /// Download version file (silent version)
    /// - Parameters:
    ///   - manifest: Minecraft version list
    ///   - gameName: game name
    /// - Returns: Whether the download was successful
    func downloadVersionFiles(
        manifest: MinecraftVersionManifest,
        gameName: String
    ) async -> Bool {
        do {
            try await downloadVersionFilesThrowing(
                manifest: manifest,
                gameName: gameName
            )
            return true
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error(
                "下载 Minecraft 版本文件失败: \(globalError.chineseMessage)"
            )
            GlobalErrorHandler.shared.handle(globalError)
            return false
        }
    }

    /// Download version file (throws exception version)
    /// - Parameters:
    ///   - manifest: Minecraft version list
    ///   - gameName: game name
    /// - Throws: GlobalError when the operation fails
    func downloadVersionFilesThrowing(
        manifest: MinecraftVersionManifest,
        gameName: String
    ) async throws {
        try createDirectories(manifestId: manifest.id, gameName: gameName)

        // Use bounded task groups to limit concurrency
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                try await self?.downloadCoreFiles(manifest: manifest)
            }
            group.addTask { [weak self] in
                try await self?.downloadAssets(manifest: manifest)
            }

            try await group.waitForAll()
        }
    }

    // MARK: - Private Methods
    private func calculateTotalFiles(_ manifest: MinecraftVersionManifest) -> Int {
        let applicableLibraries = manifest.libraries.filter { shouldDownloadLibrary($0, minecraftVersion: manifest.id) }

        // Count the number of native libraries that will actually be downloaded (consistent with the download logic)
        let nativeLibraries = applicableLibraries.compactMap { (library: Library) -> Library? in
            // Check if there is a native library classifier and it is available for the current platform
            guard let classifiers = library.downloads.classifiers,
                  let natives = library.natives else { return nil }

            // Find the native library classifier corresponding to the current platform
            let osKey = natives.keys.first { isNativeClassifier($0, minecraftVersion: manifest.id) }
            guard let platformKey = osKey,
                  let classifierKey = natives[platformKey],
                  classifiers[classifierKey] != nil else { return nil }

            return library // Returns the library that will actually download the native library
        }.count

        return 1 + applicableLibraries.count + nativeLibraries + 2  // Client JAR + Libraries + Native Libraries + Asset Index + Logging Config
    }

    /// Check whether the classifier is a native library of the current platform
    private func isNativeClassifier(_ key: String, minecraftVersion: String? = nil) -> Bool {
        MacRuleEvaluator.isPlatformIdentifierSupported(key, minecraftVersion: minecraftVersion)
    }

    private func createDirectories(
        manifestId: String,
        gameName: String
    ) throws {
        let profileDirectory = AppPaths.profileDirectory(gameName: gameName)
        let directoriesToCreate =
            Constants.metaSubdirectories.map {
                AppPaths.metaDirectory.appendingPathComponent($0)
            } + [
                AppPaths.metaDirectory.appendingPathComponent(AppConstants.DirectoryNames.versions)
                    .appendingPathComponent(manifestId),
                profileDirectory,
            ]
        let profileSubfolders = AppPaths.profileSubdirectories.map {
            profileDirectory.appendingPathComponent($0)
        }
        let allDirectories = directoriesToCreate + profileSubfolders

        for directory in allDirectories where !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                throw GlobalError.fileSystem(
                    chineseMessage: "创建目录失败",
                    i18nKey: "Directory Creation Failed",
                    level: .notification
                )
            }
        }
    }

    private func downloadCoreFiles(manifest: MinecraftVersionManifest) async throws {
        coreTotalFiles = calculateTotalFiles(manifest)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                try await self?.downloadClientJar(manifest: manifest)
            }
            group.addTask { [weak self] in
                try await self?.downloadLibraries(manifest: manifest)
            }
            group.addTask { [weak self] in
                try await self?.downloadLoggingConfig(manifest: manifest)
            }

            try await group.waitForAll()
        }
    }

    private func downloadClientJar(
        manifest: MinecraftVersionManifest
    ) async throws {
        let versionDir = AppPaths.versionsDirectory.appendingPathComponent(
            manifest.id
        )
        let destinationURL = versionDir.appendingPathComponent(
            "\(manifest.id).jar"
        )

        do {
            _ = try await DownloadManager.downloadFile(
                urlString: manifest.downloads.client.url.absoluteString,
                destinationURL: destinationURL,
                expectedSha1: manifest.downloads.client.sha1
            )
            incrementCompletedFilesCount(
                fileName: "client.jar",
                type: .core
            )
        } catch {
            // Avoid creating large temporary strings in error handling
            if let globalError = error as? GlobalError {
                throw globalError
            } else {
                throw GlobalError.download(
                    chineseMessage: "下载客户端 JAR 文件失败",
                    i18nKey: "Client Jar Failed",
                    level: .notification
                )
            }
        }
    }

    private func downloadLibraries(
        manifest: MinecraftVersionManifest
    ) async throws {
        let osxLibraries = manifest.libraries.filter {
            shouldDownloadLibrary($0, minecraftVersion: manifest.id)
        }

        // Create a semaphore to control the number of concurrencies
        let semaphore = AsyncSemaphore(
            value: GeneralSettingsManager.shared.concurrentDownloads
        )

        // Get metaDirectory in advance to avoid repeated access in loops
        let metaDirectory = AppPaths.metaDirectory
        let minecraftVersion = manifest.id

        try await withThrowingTaskGroup(of: Void.self) { group in
            for library in osxLibraries {
                group.addTask { [weak self] in
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    try await self?.downloadLibrary(
                        library,
                        metaDirectory: metaDirectory,
                        minecraftVersion: minecraftVersion
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    private func downloadLibrary(
        _ library: Library,
        metaDirectory: URL,
        minecraftVersion: String
    ) async throws {
        // Checks whether the library's rules apply to the current system (contains downloadable check)
        guard shouldDownloadLibrary(library, minecraftVersion: minecraftVersion) else {
            return
        }

        // If path is nil, use Maven coordinates to generate the path
        let destinationURL: URL
        if let existingPath = library.downloads.artifact.path {
            // Check if existingPath is a full path
            if existingPath.hasPrefix("/") {
                // If it is a full path, use it directly
                destinationURL = URL(fileURLWithPath: existingPath)
            } else {
                // If it is a relative path, add it to the libraries directory
                destinationURL = metaDirectory.appendingPathComponent(AppConstants.DirectoryNames.libraries)
                    .appendingPathComponent(existingPath)
            }
        } else {
            // Generate full path using Maven coordinates
            let fullPath = CommonService.convertMavenCoordinateToPath(library.name)
            destinationURL = URL(fileURLWithPath: fullPath)
        }

        guard let artifactURL = library.downloads.artifact.url else {
            throw GlobalError.download(
                chineseMessage: "库文件缺少下载 URL",
                i18nKey: "Missing library URL",
                level: .notification
            )
        }

        do {
            // Get the URL string in advance to avoid repeated visits
            let urlString = artifactURL.absoluteString
            // DownloadManager.downloadFile already contains file existence, verification logic and autoreleasepool
            _ = try await DownloadManager.downloadFile(
                urlString: urlString,
                destinationURL: destinationURL,
                expectedSha1: library.downloads.artifact.sha1
            )
            await handleLibraryDownloadComplete(library: library, metaDirectory: metaDirectory, minecraftVersion: minecraftVersion)
        } catch {
            // Avoid creating large temporary strings in error handling
            if let globalError = error as? GlobalError {
                throw globalError
            } else {
                throw GlobalError.download(
                    chineseMessage: "下载库文件失败",
                    i18nKey: "Library Download Failed",
                    level: .notification
                )
            }
        }
    }

    private func downloadNativeLibrary(
        library: Library,
        classifiers: [String: LibraryArtifact],
        metaDirectory: URL,
        minecraftVersion: String
    ) async throws {
        // Find the native library classifier corresponding to the current platform
        guard let natives = library.natives else { return }

        let osKey = natives.keys.first { isNativeClassifier($0, minecraftVersion: minecraftVersion) }
        guard let platformKey = osKey,
              let classifierKey = natives[platformKey],
              let nativeArtifact = classifiers[classifierKey] else {
            return
        }

        // Generate target path - download the native library to the natives directory
        let destinationURL: URL
        if let existingPath = nativeArtifact.path {
            if existingPath.hasPrefix("/") {
                destinationURL = URL(fileURLWithPath: existingPath)
            } else {
                // Native libraries are downloaded to the natives directory instead of the libraries directory
                destinationURL = metaDirectory.appendingPathComponent(AppConstants.DirectoryNames.natives)
                    .appendingPathComponent(existingPath)
            }
        } else {
            let relativePath = CommonService.mavenCoordinateToRelativePath(library.name) ?? "\(library.name.replacingOccurrences(of: ":", with: "-")).jar"
            destinationURL = metaDirectory.appendingPathComponent(AppConstants.DirectoryNames.natives)
                .appendingPathComponent(relativePath)
        }

        guard let nativeURL = nativeArtifact.url else {
            throw GlobalError.download(
                chineseMessage: "原生库文件 \(library.name) 缺少下载 URL",
                i18nKey: "Missing native URL",
                level: .notification
            )
        }

        do {
            // DownloadManager.downloadFile already contains file existence and verification logic
            _ = try await DownloadManager.downloadFile(
                urlString: nativeURL.absoluteString,
                destinationURL: destinationURL,
                expectedSha1: nativeArtifact.sha1
            )

            // Use library name to avoid formatting strings creating temporary objects
            incrementCompletedFilesCount(
                fileName: library.name,
                type: .core
            )
        } catch {
            // Avoid creating large temporary strings in error handling
            if let globalError = error as? GlobalError {
                throw globalError
            } else {
                throw GlobalError.download(
                    chineseMessage: "下载原生库文件失败",
                    i18nKey: "Native Library Failed",
                    level: .notification
                )
            }
        }
    }

    private func downloadAssets(
        manifest: MinecraftVersionManifest
    ) async throws {
        let assetIndex = try await downloadAssetIndex(manifest: manifest)
        resourceTotalFiles = assetIndex.objects.count

        try await downloadAllAssets(assetIndex: assetIndex)
    }

    private func downloadAssetIndex(
        manifest: MinecraftVersionManifest
    ) async throws -> DownloadedAssetIndex {

        let destinationURL = AppPaths.metaDirectory.appendingPathComponent(
            "assets/indexes"
        )
        .appendingPathComponent("\(manifest.assetIndex.id).json")

        do {
            _ = try await DownloadManager.downloadFile(
                urlString: manifest.assetIndex.url.absoluteString,
                destinationURL: destinationURL,
                expectedSha1: manifest.assetIndex.sha1
            )
            let data = try Data(contentsOf: destinationURL)
            let assetIndexData = try JSONDecoder().decode(
                AssetIndexData.self,
                from: data
            )
            var totalSize = 0
            for object in assetIndexData.objects.values {
                totalSize += object.size
            }
            return DownloadedAssetIndex(
                id: manifest.assetIndex.id,
                url: manifest.assetIndex.url,
                sha1: manifest.assetIndex.sha1,
                totalSize: totalSize,
                objects: assetIndexData.objects
            )
        } catch {
            // Avoid creating large temporary strings in error handling
            if let globalError = error as? GlobalError {
                throw globalError
            } else {
                throw GlobalError.download(
                    chineseMessage: "下载资源索引失败",
                    i18nKey: "Asset Index Failed",
                    level: .notification
                )
            }
        }
    }

    private func downloadLoggingConfig(
        manifest: MinecraftVersionManifest
    ) async throws {
        let loggingFile = manifest.logging.client.file
        let versionDir = AppPaths.metaDirectory.appendingPathComponent(
            AppConstants.DirectoryNames.versions
        )
        .appendingPathComponent(manifest.id)

        let destinationURL = versionDir.appendingPathComponent(loggingFile.id)

        do {
            _ = try await DownloadManager.downloadFile(
                urlString: loggingFile.url.absoluteString,
                destinationURL: destinationURL,
                expectedSha1: loggingFile.sha1
            )
            incrementCompletedFilesCount(
                fileName: "logging.config",
                type: .core
            )
        } catch {
            // Avoid creating large temporary strings in error handling
            if let globalError = error as? GlobalError {
                throw globalError
            } else {
                throw GlobalError.download(
                    chineseMessage: "下载日志配置文件失败",
                    i18nKey: "Logging Config Failed",
                    level: .notification
                )
            }
        }
    }

    private func downloadAndSaveFile(
        from url: URL,
        to destinationURL: URL,
        sha1: String?,
        fileNameForNotification: String? = nil,
        type: DownloadType
    ) async throws {
        // Download files using DownloadManager (all optimizations included)
        do {
            _ = try await DownloadManager.downloadFile(
                urlString: url.absoluteString,
                destinationURL: destinationURL,
                expectedSha1: sha1
            )

            incrementCompletedFilesCount(
                fileName: fileNameForNotification
                    ?? destinationURL.lastPathComponent,
                type: type
            )
        } catch {
            // Avoid creating large temporary strings in error handling
            if let globalError = error as? GlobalError {
                throw globalError
            } else {
                throw GlobalError.download(
                    chineseMessage: "下载文件失败",
                    i18nKey: "File Download Failed",
                    level: .notification
                )
            }
        }
    }

    private func verifyExistingFile(
        at url: URL,
        expectedSha1: String
    ) async throws -> Bool {
        let fileSha1 = try await calculateFileSHA1(at: url)
        return fileSha1 == expectedSha1
    }

    private func calculateFileSHA1(at url: URL) async throws -> String {
        try SHA1Calculator.sha1(ofFileAt: url)
    }

    private func incrementCompletedFilesCount(
        fileName: String,
        type: DownloadType
    ) {
        let currentCount: Int
        let total: Int

        switch type {
        case .core:
            currentCount = coreFilesCount.increment()
            total = coreTotalFiles
        case .resources:
            currentCount = resourceFilesCount.increment()
            total = resourceTotalFiles
        }

        onProgressUpdate?(fileName, currentCount, total, type)
    }

    private func downloadAllAssets(
        assetIndex: DownloadedAssetIndex
    ) async throws {

        let objectsDirectory = AppPaths.metaDirectory.appendingPathComponent(
            "assets/objects"
        )
        let assets = Array(assetIndex.objects)

        // Create a semaphore to control the number of concurrencies
        let semaphore = AsyncSemaphore(
            value: GeneralSettingsManager.shared.concurrentDownloads
        )

        // Process assets in chunks to balance memory usage and performance
        for chunk in stride(
            from: 0,
            to: assets.count,
            by: Constants.assetChunkSize
        ) {
            let end = min(chunk + Constants.assetChunkSize, assets.count)
            let currentChunk = assets[chunk..<end]

            try await withThrowingTaskGroup(of: Void.self) { group in
                for (path, asset) in currentChunk {
                    group.addTask { [weak self] in
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }

                        try await self?.downloadAsset(
                            asset: asset,
                            path: path,
                            objectsDirectory: objectsDirectory
                        )
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    private func downloadAsset(
        asset: AssetIndexData.AssetObject,
        path: String,
        objectsDirectory: URL
    ) async throws {
        // Precompute hashPrefix to avoid repeated creation of strings
        let hashPrefix = String(asset.hash.prefix(2))
        let assetDirectory = objectsDirectory.appendingPathComponent(hashPrefix)
        let destinationURL = assetDirectory.appendingPathComponent(asset.hash)

        do {
            // Pre-build URL strings to avoid duplicate creation in loops
            let urlString = "https://resources.download.minecraft.net/\(hashPrefix)/\(asset.hash)"
            // DownloadManager.downloadFile already contains autoreleasepool
            _ = try await DownloadManager.downloadFile(
                urlString: urlString,
                destinationURL: destinationURL,
                expectedSha1: asset.hash
            )
            // Use simple file names and avoid formatting strings to create temporary objects
            let fileName = path.components(separatedBy: "/").last ?? path
            incrementCompletedFilesCount(
                fileName: fileName,
                type: .resources
            )
        } catch {
            // Avoid creating large temporary strings in error handling
            if let globalError = error as? GlobalError {
                throw globalError
            } else {
                throw GlobalError.download(
                    chineseMessage: "下载资源文件失败",
                    i18nKey: "Asset File Failed",
                    level: .notification
                )
            }
        }
    }
}

// MARK: - Asset Index Data Types
// Removed the definitions of DownloadedAssetIndex and AssetIndexData and directly reference the types in Models/MinecraftManifest.swift

// MARK: - Thread-safe Counter
final class NSLockingCounter {
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

// MARK: - Library extension (if needed)
extension Library {
    var artifactPath: String? {
        downloads.artifact.path
    }
    var artifactURL: URL? {
        downloads.artifact.url
    }
    var artifactSHA1: String? {
        downloads.artifact.sha1
    }
    // Other business related extensions
}

extension MinecraftFileManager {
    /// Logic after processing library download is completed
    private func handleLibraryDownloadComplete(library: Library, metaDirectory: URL, minecraftVersion: String) async {
        // Use library name to avoid formatting strings creating temporary objects
        incrementCompletedFilesCount(
            fileName: library.name,
            type: .core
        )

        // Handle native libraries
        if let classifiers = library.downloads.classifiers {
            do {
                try await downloadNativeLibrary(
                    library: library,
                    classifiers: classifiers,
                    metaDirectory: metaDirectory,
                    minecraftVersion: minecraftVersion
                )
            } catch {
                Logger.shared.error("下载原生库失败")
            }
        }
    }

    /// Determine whether the library should be downloaded
    private func shouldDownloadLibrary(_ library: Library, minecraftVersion: String? = nil) -> Bool {
        LibraryFilter.shouldDownloadLibrary(library, minecraftVersion: minecraftVersion)
    }

    /// Determine whether the library is allowed to be loaded under macOS (osx) (preserving backward compatibility)
    func isLibraryAllowedOnOSX(_ rules: [Rule]?) -> Bool {
        guard let rules = rules, !rules.isEmpty else { return true }
        return MacRuleEvaluator.isAllowed(rules)
    }
}
