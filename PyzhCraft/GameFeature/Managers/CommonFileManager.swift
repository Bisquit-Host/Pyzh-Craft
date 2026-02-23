import Foundation

class CommonFileManager {
    let librariesDir: URL
    let session: URLSession
    var onProgressUpdate: ((String, Int, Int) -> Void)?
    private let fileManager = FileManager.default
    private let retryCount = 3
    private let retryDelay: TimeInterval = 2

    init(librariesDir: URL) {
        self.librariesDir = librariesDir
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost =
            GeneralSettingsManager.shared.concurrentDownloads
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    actor Counter {
        private var value = 0

        func increment() -> Int {
            value += 1
            return value
        }
    }

    /// Download the Forge JAR file (silent version)
    /// - Parameter libraries: list of library files to download
    func downloadForgeJars(libraries: [ModrinthLoaderLibrary]) async {
        do {
            try await downloadForgeJarsThrowing(libraries: libraries)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to download Forge JAR file: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// Download the Forge JAR file (throws exception version)
    /// - Parameter libraries: list of library files to download
    /// - Throws: GlobalError when download fails
    func downloadForgeJarsThrowing(libraries: [ModrinthLoaderLibrary]) async throws {
        let tasks = libraries.compactMap { lib -> JarDownloadTask? in
            guard lib.downloadable else { return nil }

            // Prefer using LibraryDownloads.artifact
            if let downloads = lib.downloads, let artifactUrl = downloads.artifact.url, let artifactPath = downloads.artifact.path {
                return JarDownloadTask(
                    name: lib.name,
                    url: artifactUrl,
                    destinationPath: artifactPath,
                    expectedSha1: downloads.artifact.sha1.isEmpty ? nil : downloads.artifact.sha1
                )
            }

            guard let url = CommonService.mavenCoordinateToURL(lib: lib) else { return nil }
            return JarDownloadTask(
                name: lib.name,
                url: url,
                destinationPath: CommonService.mavenCoordinateToDefaultPath(lib.name),
                expectedSha1: nil
            )
        }

        do {
            try await BatchJarDownloader.download(
                tasks: tasks,
                metaLibrariesDir: AppPaths.librariesDirectory,
                onProgressUpdate: self.onProgressUpdate
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("JAR download failed: \(globalError.chineseMessage)")
            throw GlobalError.download(
                i18nKey: "JAR Download Failed",
                level: .notification
            )
        }
    }

    /// Download the FabricJAR file (silent version)
    /// - Parameter libraries: list of library files to download
    func downloadFabricJars(libraries: [ModrinthLoaderLibrary]) async {
        do {
            try await downloadFabricJarsThrowing(libraries: libraries)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to download JAR file: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// Download the FabricJAR file (throws exception version)
    /// - Parameter libraries: list of library files to download
    /// - Throws: GlobalError when download fails
    func downloadFabricJarsThrowing(libraries: [ModrinthLoaderLibrary]) async throws {
        let tasks = libraries.compactMap { lib -> JarDownloadTask? in
            guard lib.downloadable else { return nil }
            guard let url = CommonService.mavenCoordinateToURL(lib: lib) else { return nil }
            return JarDownloadTask(
                name: lib.name,
                url: url,
                destinationPath: CommonService.mavenCoordinateToDefaultPath(lib.name),
                expectedSha1: ""
            )
        }

        do {
            try await BatchJarDownloader.download(
                tasks: tasks,
                metaLibrariesDir: AppPaths.librariesDirectory,
                onProgressUpdate: self.onProgressUpdate
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("JAR download failed: \(globalError.chineseMessage)")
            throw GlobalError.download(
                i18nKey: "JAR Download Failed",
                level: .notification
            )
        }
    }

    /// Execute processors
    /// - Parameters:
    ///   - processors: processor list
    ///   - librariesDir: library directory
    ///   - gameVersion: game version
    ///   - data: data field, used for placeholder replacement
    ///   - gameName: game name (optional)
    ///   - onProgressUpdate: progress update callback (optional, including current processor index and total number of processors)
    /// - Throws: GlobalError when processing fails
    func executeProcessors(processors: [Processor], librariesDir: URL, gameVersion: String, data: [String: SidedDataEntry]? = nil, gameName: String? = nil, onProgressUpdate: ((String, Int, Int) -> Void)? = nil) async throws {
        // Filter out the client-side processor
        let clientProcessors = processors.filter { processor in
            guard let sides = processor.sides else { return true } // If sides is not specified, it will be executed by default
            return sides.contains(AppConstants.EnvironmentTypes.client)
        }

        guard !clientProcessors.isEmpty else {
            Logger.shared.info("The client-side processor was not found and execution was skipped")
            return
        }

        Logger.shared.info("Find \(clientProcessors.count) client processors and start execution")

        // Use the original data field from version.json and add the necessary environment variables
        var processorData: [String: String] = [:]

        // Add basic environment variables
        processorData["SIDE"] = AppConstants.EnvironmentTypes.client
        processorData["MINECRAFT_VERSION"] = gameVersion
        processorData["LIBRARY_DIR"] = librariesDir.path

        // Add Minecraft JAR path
        let minecraftJarPath = AppPaths.versionsDirectory.appendingPathComponent(gameVersion).appendingPathComponent("\(gameVersion).jar")
        processorData["MINECRAFT_JAR"] = minecraftJarPath.path

        // Add instance path (profile directory)
        if let gameName = gameName {
            processorData["ROOT"] = AppPaths.profileDirectory(gameName: gameName).path
        }

        // Parse the data field in version.json
        if let data = data {
            for (key, sidedEntry) in data {
                processorData[key] = Self.extractClientValue(from: sidedEntry.client) ?? sidedEntry.client
            }
        }

        // Obtain the corresponding Java version through gameVersion and only obtain it once to avoid repeated requests and verification in each processor
        let versionInfo = try await ModrinthService.fetchVersionInfo(from: gameVersion)
        let javaPath = JavaManager.shared.findJavaExecutable(version: versionInfo.javaVersion.component)

        for (index, processor) in clientProcessors.enumerated() {
            do {
                let processorName = processor.jar ?? String(localized: "Unknown")
                let message = String(
                    format: String(
                        localized: "Executing processor \(Int32(index + 1))/\(Int32(clientProcessors.count)): \(processorName)"
                    )
                )
                onProgressUpdate?(message, index + 1, clientProcessors.count)
                try await executeProcessor(
                    processor,
                    librariesDir: librariesDir,
                    gameVersion: gameVersion,
                    javaPath: javaPath,
                    data: processorData,
                    onProgressUpdate: onProgressUpdate
                )
            } catch {
                Logger.shared.error("Execution processor failed: \(error.localizedDescription)")
                throw GlobalError.download(
                    i18nKey: "Processor Start Failed",
                    level: .notification
                )
            }
        }
    }

    /// Execute a single processor
    /// - Parameters:
    ///   - processor: processor
    ///   - librariesDir: library directory
    ///   - gameVersion: game version
    ///   - javaPath: Java executable path (parsed/verified in advance)
    ///   - data: data field, used for placeholder replacement
    ///   - onProgressUpdate: progress update callback (optional, including current processor index and total number of processors)
    /// - Throws: GlobalError when processing fails
    private func executeProcessor(_ processor: Processor, librariesDir: URL, gameVersion: String, javaPath: String, data: [String: String]? = nil, onProgressUpdate: ((String, Int, Int) -> Void)? = nil) async throws {
        try await ProcessorExecutor.executeProcessor(
            processor,
            librariesDir: librariesDir,
            gameVersion: gameVersion,
            javaPath: javaPath,
            data: data
        )
    }

    /// Extract client-side data from the data field value
    /// - Parameter value: the value of the data field
    /// - Returns: client-side data, if it cannot be parsed, return nil
    static func extractClientValue(from value: String) -> String? {
        // If it is in Maven coordinate format, convert it directly to a path
        if value.contains(":") && !value.hasPrefix("[") && !value.hasPrefix("{") {
            return CommonService.convertMavenCoordinateToPath(value)
        }

        // If it is in array format, directly extract the content and convert it to a path
        if value.hasPrefix("[") && value.hasSuffix("]") {
            let content = String(value.dropFirst().dropLast())
            if content.contains(":") {
                return CommonService.convertMavenCoordinateToPath(content)
            }
            return content
        }
        return value
    }
}
