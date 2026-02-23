import Foundation

enum MinecraftLaunchCommandBuilder {
    static func build(
        manifest: MinecraftVersionManifest,
        gameInfo: GameVersionInfo,
        launcherBrand: String,
        launcherVersion: String
    ) -> [String] {
        do {
            return try buildThrowing(
                manifest: manifest,
                gameInfo: gameInfo,
                launcherBrand: launcherBrand,
                launcherVersion: launcherVersion
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Build startup command failed: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    static func buildThrowing(
        manifest: MinecraftVersionManifest,
        gameInfo: GameVersionInfo,
        launcherBrand: String,
        launcherVersion: String
    ) throws -> [String] {
        // Verify and get the path
        let paths = try validateAndGetPaths(gameInfo: gameInfo, manifest: manifest)

        // Build classpath
        let classpath = buildClasspath(
            manifest.libraries,
            librariesDir: paths.librariesDir,
            clientJarPath: paths.clientJarPath,
            modClassPath: gameInfo.modClassPath,
            minecraftVersion: manifest.id
        )

        // variable mapping
        let variableMap: [String: String] = [
            "auth_player_name": "${auth_player_name}",
            "version_name": gameInfo.gameVersion,
            "game_directory": paths.gameDir,
            "assets_root": paths.assetsDir,
            "assets_index_name": gameInfo.assetIndex,
            "auth_uuid": "${auth_uuid}",
            "auth_access_token": "${auth_access_token}",
            "clientid": AppConstants.minecraftClientId,
            "auth_xuid": "${auth_xuid}",
            "user_type": "msa",
            "version_type": Bundle.main.appName,
            "natives_directory": paths.nativesDir,
            "launcher_name": Bundle.main.appName,
            "launcher_version": launcherVersion,
            "classpath": classpath,
        ]

        // Parse arguments field first
        var jvmArgs = manifest.arguments.jvm?
            .map { substituteVariables($0, with: variableMap) } ?? []
        var gameArgs = manifest.arguments.game?
            .map { substituteVariables($0, with: variableMap) } ?? []

        // Additional splicing of JVM memory parameters
        let xmsArg = "-Xms${xms}M"
        let xmxArg = "-Xmx${xmx}M"
        jvmArgs.insert(contentsOf: [xmsArg, xmxArg], at: 0)

        // Add macOS-specific JVM parameters
        jvmArgs.insert("-XstartOnFirstThread", at: 0)

        // splicing modJvm
        if !gameInfo.modJvm.isEmpty {
            jvmArgs.append(contentsOf: gameInfo.modJvm)
        }

        // Splicing gameInfo's gameArguments
        if !gameInfo.gameArguments.isEmpty {
            gameArgs.append(contentsOf: gameInfo.gameArguments)
        }

        // Splicing parameters
        let allArgs = jvmArgs + [gameInfo.mainClass] + gameArgs
        return allArgs
    }

    private static func validateAndGetPaths(
        gameInfo: GameVersionInfo,
        manifest: MinecraftVersionManifest
        // swiftlint:disable:next large_tuple
    ) throws -> (nativesDir: String, librariesDir: URL, assetsDir: String, gameDir: String, clientJarPath: String) {
        // Verify game directory

        // Verify client JAR file
        let clientJarPath = AppPaths.versionsDirectory.appendingPathComponent(manifest.id).appendingPathComponent("\(manifest.id).jar").path
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: clientJarPath) else {
            throw GlobalError.resource(
                i18nKey: "Client Jar Not Found",
                level: .popup
            )
        }

        return (nativesDir: AppPaths.nativesDirectory.path, librariesDir: AppPaths.librariesDirectory, assetsDir: AppPaths.assetsDirectory.path, gameDir: AppPaths.profileDirectory(gameName: gameInfo.gameName).path, clientJarPath: clientJarPath)
    }

    private static func substituteVariables(_ arg: String, with map: [String: String]) -> String {
        // Quick check: if the string does not contain any placeholders, just return
        guard arg.contains("${") else {
            return arg
        }

        // Use NSMutableString to avoid creating lots of temporary strings in loops
        let result = NSMutableString(string: arg)
        for (key, value) in map {
            let placeholder = "${\(key)}"
            // First check whether it contains placeholders to avoid unnecessary replacement operations
            if result.range(of: placeholder).location != NSNotFound {
                result.replaceOccurrences(
                    of: placeholder,
                    with: value,
                    options: [],
                    range: NSRange(location: 0, length: result.length)
                )
            }
        }
        return result as String
    }

    private static func buildClasspath(_ libraries: [Library], librariesDir: URL, clientJarPath: String, modClassPath: String, minecraftVersion: String) -> String {
        Logger.shared.debug("Start building classpath - library count: \(libraries.count), mod classpath: \(modClassPath.isEmpty ? "none" : "\(modClassPath.split(separator: ":").count) paths")")

        // Parse the mod classpath and extract existing library paths
        let modClassPaths = parseModClassPath(modClassPath, librariesDir: librariesDir)
        let existingModBasePaths = extractBasePaths(from: modClassPaths, librariesDir: librariesDir)
        Logger.shared.debug("Resolved to \(modClassPaths.count) mod classpaths, \(existingModBasePaths.count) base paths")

        // Filter and process the manifest library
        let manifestLibraryPaths = libraries
            .filter { shouldIncludeLibrary($0, minecraftVersion: minecraftVersion) }
            .compactMap { library in
                processLibrary(library, librariesDir: librariesDir, existingModBasePaths: existingModBasePaths, minecraftVersion: minecraftVersion)
            }
            .flatMap { $0 }

        Logger.shared.debug("Processing completed - manifest library path: \(manifestLibraryPaths.count)")

        // Build final classpath and deduplicate
        let allPaths = manifestLibraryPaths + [clientJarPath] + modClassPaths
        let uniquePaths = removeDuplicatePaths(allPaths)
        let classpath = uniquePaths.joined(separator: ":")

        Logger.shared.debug("Class path construction completed - original path number: \(allPaths.count), after deduplication: \(uniquePaths.count)")
        return classpath
    }

    /// Parse mod classpath string
    private static func parseModClassPath(_ modClassPath: String, librariesDir: URL) -> [String] {
        return modClassPath.split(separator: ":").map { String($0) }
    }

    /// Remove duplicate paths and keep original order
    private static func removeDuplicatePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { path in
            let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPath.isEmpty else { return false }

            if seen.contains(normalizedPath) {
                Logger.shared.debug("Duplicate path found, skipped: \(normalizedPath)")
                return false
            } else {
                seen.insert(normalizedPath)
                return true
            }
        }
    }

    /// Extract base path from path list (for deduplication)
    private static func extractBasePaths(from paths: [String], librariesDir: URL) -> Set<String> {
        let librariesDirPath = librariesDir.path.appending("/")

        return Set(paths.compactMap { path in
            guard path.hasPrefix(librariesDirPath) else { return nil }
            let relPath = String(path.dropFirst(librariesDirPath.count))
            return extractBasePath(from: relPath)
        })
    }

    /// Extract the base path from the relative path (remove the last two levels of directories)
    private static func extractBasePath(from relativePath: String) -> String? {
        let pathComponents = relativePath.split(separator: "/")
        guard pathComponents.count >= 2 else { return nil }
        return pathComponents.dropLast(2).joined(separator: "/")
    }

    /// Process a single library, returning all its related paths
    private static func processLibrary(_ library: Library, librariesDir: URL, existingModBasePaths: Set<String>, minecraftVersion: String) -> [String]? {
        let artifact = library.downloads.artifact

        // Get the main library path
        let libraryPath = getLibraryPath(artifact: artifact, libraryName: library.name, librariesDir: librariesDir)

        // Check if it is a duplicate of mod path
        let relativePath = String(libraryPath.dropFirst(librariesDir.path.appending("/").count))
        guard let basePath = extractBasePath(from: relativePath) else { return nil }

        if existingModBasePaths.contains(basePath) {
            return nil // mod path already exists, skip
        }

        // Returns only the artifact path, without classifiers
        // classifiers are native libraries and should not be added to the classpath
        return [libraryPath]
    }

    /// Get library file path
    private static func getLibraryPath(artifact: LibraryArtifact, libraryName: String, librariesDir: URL) -> String {
        if let existingPath = artifact.path {
            return librariesDir.appendingPathComponent(existingPath).path
        } else {
            let fullPath = CommonService.convertMavenCoordinateToPath(libraryName)
            Logger.shared.debug("Library file \(libraryName) is missing path information, use Maven coordinates to generate the path: \(fullPath)")
            return fullPath
        }
    }

    // DEPRECATED: The classifiers library is no longer added to the classpath
    private static func getClassifierPaths(library: Library, librariesDir: URL, minecraftVersion: String) -> [String] {
        // classifiers are no longer added to the classpath
        return []
    }

    /// Determine whether the library should be included in the classpath
    private static func shouldIncludeLibrary(_ library: Library, minecraftVersion: String? = nil) -> Bool {
        // Check basic conditions: downloadable and included in the classpath
        guard library.downloadable == true && library.includeInClasspath == true else {
            return false
        }

        // Use unified library filtering logic
        return LibraryFilter.isLibraryAllowed(library, minecraftVersion: minecraftVersion)
    }
}
