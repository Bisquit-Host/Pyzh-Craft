import Foundation
import ZIPFoundation

/// Java runtime downloader
class JavaRuntimeService {
    static let shared = JavaRuntimeService()
    private let downloadSession = URLSession.shared

    // Progress callbacks - using actors to ensure thread safety
    private let progressActor = ProgressActor()
    // Uncheck callbacks - use actors to ensure thread safety
    private let cancelActor = CancelActor()

    // public interface methods
    func setProgressCallback(_ callback: @escaping (String, Int, Int) -> Void) {
        Task {
            await progressActor.setCallback(callback)
        }
    }

    func setCancelCallback(_ callback: @escaping () -> Bool) {
        Task {
            await cancelActor.setCallback(callback)
        }
    }

    /// Zulu JDK configuration for ARM platform specific version
    private static let armJavaVersions: [String: URL] = [
        "jre-legacy": URLConfig.API.JavaRuntimeARM.jreLegacy,
        "java-runtime-alpha": URLConfig.API.JavaRuntimeARM.javaRuntimeAlpha,
        "java-runtime-beta": URLConfig.API.JavaRuntimeARM.javaRuntimeBeta,
    ]

    /// Intel platform-specific version of Zulu JDK configuration
    private static let intelJavaVersions: [String: URL] = [
        "jre-legacy": URLConfig.API.JavaRuntimeIntel.jreLegacy,
        "java-runtime-alpha": URLConfig.API.JavaRuntimeIntel.javaRuntimeAlpha,
        "java-runtime-beta": URLConfig.API.JavaRuntimeIntel.javaRuntimeBeta,
    ]

    /// Get the special runtime URL corresponding to the current architecture
    private func specialJavaRuntimeURL(for version: String) -> URL? {
        switch Architecture.current {
        case .arm64:
            return Self.armJavaVersions[version]
        case .x86_64:
            return Self.intelJavaVersions[version]
        }
    }
    /// Parse the Java runtime API and obtain the version name supported by the gamecore platform
    func getGamecoreSupportedVersions() async throws -> [String] {
        let json = try await fetchJavaRuntimeAPI()
        guard let gamecore = json["gamecore"] as? [String: Any] else {
            throw GlobalError.validation(
                chineseMessage: "未找到gamecore平台数据",
                i18nKey: "error.validation.gamecore_not_found",
                level: .notification
            )
        }

        let versionNames = Array(gamecore.keys)
        return versionNames
    }
    /// Get the corresponding Java runtime data based on the current system (macOS) and CPU architecture
    func getMacJavaRuntimeData() async throws -> [String: Any] {
        let json = try await fetchJavaRuntimeAPI()
        let platform = getCurrentMacPlatform()
        guard let platformData = json[platform] as? [String: Any] else {
            throw GlobalError.validation(
                chineseMessage: "未找到\(platform)平台数据",
                i18nKey: "error.validation.platform_data_not_found",
                level: .notification
            )
        }

        return platformData
    }
    /// Get the corresponding Java runtime data based on the passed version name
    func getMacJavaRuntimeData(for version: String) async throws -> [[String: Any]] {
        let platformData = try await getMacJavaRuntimeData()
        guard let versionData = platformData[version] as? [[String: Any]] else {
            Logger.shared.error("版本 \(version) 的数据类型不正确，期望 [[String: Any]]，实际: \(type(of: platformData[version]))")
            throw GlobalError.validation(
                chineseMessage: "未找到版本 \(version) 的数据",
                i18nKey: "error.validation.version_data_not_found",
                level: .notification
            )
        }

        return versionData
    }
    /// Get the manifest URL of the specified version
    func getManifestURL(for version: String) async throws -> String {
        let versionData = try await getMacJavaRuntimeData(for: version)
        // Version data is an array, take the first element
        guard let firstVersion = versionData.first,
              let manifest = firstVersion["manifest"] as? [String: Any],
              let manifestURL = manifest["url"] as? String else {
            Logger.shared.error("无法解析版本 \(version) 的数据结构")
            throw GlobalError.validation(
                chineseMessage: "未找到版本 \(version) 的manifest URL",
                i18nKey: "error.validation.manifest_url_not_found",
                level: .notification
            )
        }

        Logger.shared.info("找到版本 \(version) 的manifest URL: \(manifestURL)")
        return manifestURL
    }
    /// Download the specified version of Java runtime
    func downloadJavaRuntime(for version: String) async throws {
        // Check whether it is a special version of the current architecture (Zulu JDK)
        if let bundledVersionURL = specialJavaRuntimeURL(for: version) {
            try await downloadBundledJavaRuntime(version: version, url: bundledVersionURL)
            return
        }

        let manifestURL = try await getManifestURL(for: version)
        // Download manifest.json
        let manifestData = try await fetchDataFromURL(manifestURL)
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let files = manifest["files"] as? [String: Any] else {
            throw GlobalError.validation(
                chineseMessage: "解析manifest.json失败",
                i18nKey: "error.validation.manifest_parse_failed",
                level: .notification
            )
        }

        // Create target directory
        let targetDirectory = AppPaths.runtimeDirectory.appendingPathComponent(version)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        // Calculate the total number of files - only count items whose type is file and actually need to be downloaded
        let totalFiles = files
            .compactMap { filePath, fileInfo -> Int? in
                guard let fileData = fileInfo as? [String: Any],
                      let fileType = fileData["type"] as? String,
                      fileType == "file" else {
                    return nil
                }

                // Check if the file already exists
                let localFilePath = targetDirectory.appendingPathComponent(filePath)
                let fileExists = FileManager.default.fileExists(atPath: localFilePath.path)

                // Only files that do not exist are counted in the total
                return fileExists ? nil : 1
            }
            .reduce(0, +)

        // Create a semaphore to control the number of concurrencies
        let semaphore = AsyncSemaphore(
            value: GeneralSettingsManager.shared.concurrentDownloads
        )

        // Create counters for progress tracking
        let counter = Counter()

        // Download all files using concurrent
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (filePath, fileInfo) in files {
                group.addTask { [progressActor, cancelActor, self] in
                    // Check if it should be canceled
                    if await cancelActor.shouldCancel() {
                        Logger.shared.info("Java下载已被取消")
                        throw GlobalError.download(
                            chineseMessage: "下载已被取消",
                            i18nKey: "error.download.cancelled",
                            level: .notification
                        )
                    }

                    guard let fileData = fileInfo as? [String: Any],
                          let downloads = fileData["downloads"] as? [String: Any] else {
                        return
                    }

                    // Get file type and executable attributes
                    let fileType = fileData["type"] as? String
                    let isExecutable = fileData["executable"] as? Bool ?? false

                    // Only use raw format
                    guard let raw = downloads["raw"] as? [String: Any] else {
                        Logger.shared.warning("文件 \(filePath) 没有RAW格式，跳过")
                        return
                    }

                    guard let fileURL = raw["url"] as? String else {
                        return
                    }

                    // Get the expected SHA1 value
                    let expectedSHA1 = raw["sha1"] as? String

                    // Determine local file path
                    let localFilePath = targetDirectory.appendingPathComponent(filePath)

                    // Wait for semaphore
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    // Check if the file already exists
                    let fileExistsBefore = FileManager.default.fileExists(atPath: localFilePath.path)

                    // Use DownloadManager to download files, which already includes file existence check and SHA1 verification
                    _ = try await DownloadManager.downloadFile(
                        urlString: fileURL,
                        destinationURL: localFilePath,
                        expectedSha1: expectedSHA1
                    )

                    // If the file type is "file" and executable is true, add execution permissions to the file
                    if fileType == "file" && isExecutable {
                        try setExecutablePermission(for: localFilePath)
                    }

                    // Only projects with type file are counted in the number of completed files
                    // and only increment the count when the file is actually downloaded (the file didn't exist before)
                    if fileType == "file" && !fileExistsBefore {
                        // Verify that the file exists and has content
                        do {
                            let fileAttributes = try FileManager.default.attributesOfItem(atPath: localFilePath.path)
                            if let fileSize = fileAttributes[.size] as? Int64, fileSize > 0 {
                                let completed = await counter.increment()
                                await progressActor.callProgressUpdate(filePath, completed, totalFiles)
                            }
                        } catch {
                            Logger.shared.warning("无法验证文件 \(filePath) 的下载状态: \(error.localizedDescription)")
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
    }
    /// Get Java runtime API data
    private func fetchJavaRuntimeAPI() async throws -> [String: Any] {
        let url = URLConfig.API.JavaRuntime.allRuntimes
        let data = try await fetchDataFromURL(url.absoluteString)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GlobalError.validation(
                chineseMessage: "解析JSON失败",
                i18nKey: "error.validation.json_parse_failed",
                level: .notification
            )
        }

        return json
    }

    /// Download data from specified URL
    /// - Parameter urlString: URL string
    /// - Returns: downloaded data
    private func fetchDataFromURL(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw GlobalError.validation(
                chineseMessage: "无效的URL",
                i18nKey: "error.validation.invalid_url",
                level: .notification
            )
        }

        let (data, response) = try await downloadSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GlobalError.network(
                chineseMessage: "下载失败",
                i18nKey: "error.network.download_failed",
                level: .notification
            )
        }

        return data
    }
    /// Get the current macOS platform identification
    private func getCurrentMacPlatform() -> String {
        Architecture.current.macPlatformId
    }

    /// Set execution permissions for files
    /// - Parameter filePath: file path
    private func setExecutablePermission(for filePath: URL) throws {
        let fileManager = FileManager.default

        // Get current file permissions
        let currentAttributes = try fileManager.attributesOfItem(atPath: filePath.path)
        var currentPermissions = currentAttributes[.posixPermissions] as? UInt16 ?? 0o644

        // Add execution permissions (owner, group, other)
        currentPermissions |= 0o111

        // Set new permissions
        try fileManager.setAttributes([.posixPermissions: currentPermissions], ofItemAtPath: filePath.path)
    }

    /// Download the special Java runtime for your current architecture (from Zulu JDK)
    /// - Parameters:
    ///   - version: version name
    ///   - url: download URL
    private func downloadBundledJavaRuntime(version: String, url: URL) async throws {
        // Create target directory
        let targetDirectory = AppPaths.runtimeDirectory.appendingPathComponent(version)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        // Download the zip file to a temporary location
        let tempZipPath = targetDirectory.appendingPathComponent("temp_java.zip")

        // Download zip file (with byte size progress)
        try await downloadZipWithProgress(
            from: url,
            to: tempZipPath,
            fileName: "\(version).zip"
        )

        // Unzip the zip file
        try await extractAndProcessBundledJavaRuntime(
            zipPath: tempZipPath,
            targetDirectory: targetDirectory
        )

        // Update Progress - Complete
        await progressActor.callProgressUpdate("Java运行时 \(version) 安装完成", 1, 1)
    }

    /// Unzip and process the special Java runtime zip file
    /// - Parameters:
    ///   - zipPath: zip file path
    ///   - targetDirectory: target directory
    private func extractAndProcessBundledJavaRuntime(zipPath: URL, targetDirectory: URL) async throws {
        let fileManager = FileManager.default

        // The final jre.bundle path
        let finalJreBundlePath = targetDirectory.appendingPathComponent("jre.bundle")

        // If the target location already exists, delete it first
        if fileManager.fileExists(atPath: finalJreBundlePath.path) {
            try fileManager.removeItem(at: finalJreBundlePath)
        }

        // Selectively unzip the JRE folder in the zip file
        do {
            try extractSpecificFolderFromZip(
                zipPath: zipPath,
                destinationPath: finalJreBundlePath
            )
        } catch {
            Logger.shared.error("解压Java运行时失败: \(error.localizedDescription)")

            throw GlobalError.validation(
                chineseMessage: "解压Java运行时失败: \(error.localizedDescription)",
                i18nKey: "error.validation.extract_failed",
                level: .notification
            )
        }

        // Delete the downloaded compressed package
        try? fileManager.removeItem(at: zipPath)
    }

    /// Selectively extract zulu folder from zip file
    /// - Parameters:
    ///   - zipPath: zip file path
    ///   - destinationPath: destination path after decompression
    private func extractSpecificFolderFromZip(zipPath: URL, destinationPath: URL) throws {
        let fileManager = FileManager.default

        // Open zip file
        let archive: Archive
        do {
            archive = try Archive(url: zipPath, accessMode: .read)
        } catch {
            throw GlobalError.validation(
                chineseMessage: "无法打开zip文件: \(error.localizedDescription)",
                i18nKey: "error.validation.cannot_open_zip",
                level: .notification
            )
        }

        // Find the entry for the zulu folder
        var targetFolderEntries: [Entry] = []
        var targetFolderPrefix: String?

        for entry in archive {
            let path = entry.path

            // Find folders starting with "zulu-"
            let pathComponents = path.split(separator: "/")

            for (index, component) in pathComponents.enumerated() {
                let componentStr = String(component)
                if componentStr.hasPrefix("zulu-") && componentStr.contains(".jre") {
                    if targetFolderPrefix == nil {
                        // Find the zulu folder and build the complete prefix path
                        let prefixComponents = pathComponents[0...index]
                        targetFolderPrefix = prefixComponents.joined(separator: "/")
                        if let prefix = targetFolderPrefix, !prefix.isEmpty {
                            targetFolderPrefix = prefix + "/"
                        }
                    }
                    break
                }
            }

            // If the target prefix is ​​found, collect all matching entries
            if let prefix = targetFolderPrefix, path.hasPrefix(prefix) {
                targetFolderEntries.append(entry)
            }
        }

        guard !targetFolderEntries.isEmpty, let prefix = targetFolderPrefix else {
            throw GlobalError.validation(
                chineseMessage: "在zip文件中未找到zulu文件夹",
                i18nKey: "error.validation.zulu_folder_not_found_in_zip",
                level: .notification
            )
        }

        // Extract all entries of the target folder
        for entry in targetFolderEntries {
            // Calculate path relative to target folder
            let relativePath = String(entry.path.dropFirst(prefix.count))
            let outputPath = destinationPath.appendingPathComponent(relativePath)

            // Skip symbolic link entries
            if entry.type == .symlink {
                continue
            }

            do {
                // If it is a directory, create the directory
                if entry.type == .directory {
                    try fileManager.createDirectory(at: outputPath, withIntermediateDirectories: true)
                } else if entry.type == .file {
                    // Make sure the parent directory exists
                    let parentDir = outputPath.deletingLastPathComponent()
                    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

                    // Unzip the file
                    _ = try archive.extract(entry, to: outputPath)
                } else {
                    continue
                }
            } catch {
                // Check for specific ZIPFoundation errors
                if let archiveError = error as? Archive.ArchiveError {
                    // Special handling of symbolic link errors
                    if String(describing: archiveError) == "uncontainedSymlink" {
                        continue // Skip this entry and continue with the next one
                    }
                }

                // For other errors, log and throw
                Logger.shared.error("解压失败: \(entry.path) - \(error.localizedDescription)")
                throw error
            }
        }
    }

    /// Download ZIP file and display byte size progress
    /// - Parameters:
    ///   - url: download URL
    ///   - destinationURL: destination file path
    ///   - fileName: displayed file name
    private func downloadZipWithProgress(from url: URL, to destinationURL: URL, fileName: String) async throws {
        // Get the file size first
        let fileSize = try await getFileSize(from: url)

        // Set initial progress
        await progressActor.callProgressUpdate(fileName, 0, Int(fileSize))

        // Create a progress tracker
        let progressCallback: (Int64, Int64) -> Void = { [progressActor] downloadedBytes, totalBytes in
            // Pass actual number of bytes for byte size progress display
            Task {
                await progressActor.callProgressUpdate(fileName, Int(downloadedBytes), Int(totalBytes))
            }
        }
        let progressTracker = DownloadProgressTracker(totalSize: fileSize, progressCallback: progressCallback)

        // Create URLSession configuration
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: progressTracker, delegateQueue: nil)

        // Use the downloadTask method to download and cooperate with the progress callback
        return try await withCheckedThrowingContinuation { continuation in
            // Set completion callback
            progressTracker.completionHandler = { result in
                switch result {
                case .success(let tempURL):
                    do {
                        let fileManager = FileManager.default

                        // If the target file already exists, delete it first
                        if fileManager.fileExists(atPath: destinationURL.path) {
                            try fileManager.removeItem(at: destinationURL)
                        }

                        // Move temporary files to destination
                        try fileManager.moveItem(at: tempURL, to: destinationURL)
                        continuation.resume()
                    } catch {
                        Logger.shared.error("移动下载文件失败: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    Logger.shared.error("下载失败: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }

            // Create download task and start
            let downloadTask = session.downloadTask(with: url)
            downloadTask.resume()
        }
    }

    /// Get remote file size
    private func getFileSize(from url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        // Use a unified API client (HEAD requests need to return response headers)
        let (_, httpResponse) = try await APIClient.performRequestWithResponse(request: request)

        guard httpResponse.statusCode == 200 else {
            throw GlobalError.network(
                chineseMessage: "无法获取文件大小 - HTTP状态码: \(httpResponse.statusCode)",
                i18nKey: "error.network.cannot_get_file_size",
                level: .notification
            )
        }

        guard let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
              let fileSize = Int64(contentLength) else {
            throw GlobalError.network(
                chineseMessage: "无法获取文件大小 - 缺少或无效的Content-Length头部",
                i18nKey: "error.network.cannot_get_file_size",
                level: .notification
            )
        }

        return fileSize
    }
}

/// Download progress tracker
private class DownloadProgressTracker: NSObject, URLSessionDownloadDelegate {
    private let progressCallback: (Int64, Int64) -> Void
    private let totalFileSize: Int64
    var completionHandler: ((Result<URL, Error>) -> Void)?

    init(totalSize: Int64, progressCallback: @escaping (Int64, Int64) -> Void) {
        self.totalFileSize = totalSize
        self.progressCallback = progressCallback
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Use real download progress
        let actualTotalSize = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : totalFileSize

        if actualTotalSize > 0 {
            // Make sure to call the progress callback on the main thread
            DispatchQueue.main.async { [weak self] in
                self?.progressCallback(totalBytesWritten, actualTotalSize)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Call completion callback
        completionHandler?(.success(location))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler?(.failure(error))
        }
    }
}

/// Thread-safe counter for tracking concurrent download progress
private actor Counter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

/// Thread-safe progress callback actors
private actor ProgressActor {
    private var callback: ((String, Int, Int) -> Void)?

    func setCallback(_ callback: @escaping (String, Int, Int) -> Void) {
        self.callback = callback
    }

    func callProgressUpdate(_ fileName: String, _ completed: Int, _ total: Int) {
        callback?(fileName, completed, total)
    }
}

/// Thread-safe unchecking of actors
private actor CancelActor {
    private var callback: (() -> Bool)?

    func setCallback(_ callback: @escaping () -> Bool) {
        self.callback = callback
    }

    func shouldCancel() -> Bool {
        callback?() ?? false
    }
}
