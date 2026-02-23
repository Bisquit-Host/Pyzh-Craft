import Foundation

enum CommonService {

    /// Get the adapted version list (silent version) according to the mod loader
    /// - Parameter loader: loader type
    /// - Returns: List of compatible versions
    static func compatibleVersions(
        for loader: String,
        includeSnapshots: Bool = false
    ) async -> [String] {
        do {
            return try await compatibleVersionsThrowing(
                for: loader,
                includeSnapshots: includeSnapshots
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error(
                "Failed to get version \(loader): \(globalError.chineseMessage)"
            )
            GlobalErrorHandler.shared.handle(globalError)
            return []
        }
    }

    /// Get the adapted version list according to mod loader (throws exception version)
    /// - Parameter loader: loader type
    /// - Returns: List of compatible versions
    /// - Throws: GlobalError when the operation fails
    static func compatibleVersionsThrowing(
        for loader: String,
        includeSnapshots: Bool = false
    ) async throws -> [String] {
        var result: [String] = []
        switch loader.lowercased() {
        case "fabric", "forge", "quilt", "neoforge":
            let loaderType =
                loader.lowercased() == "neoforge" ? "neo" : loader.lowercased()
            let loaderVersions = try await fetchAllVersionThrowing(
                type: loaderType
            )
            let filteredVersions = loaderVersions.map { $0.id }
                .filter { version in
                    // Filter out purely numeric versions (such as 1.21.1, 1.20.4, etc.)
                    let components = version.components(separatedBy: ".")
                    return components.allSatisfy {
                        $0.rangeOfCharacter(
                            from: CharacterSet.decimalDigits.inverted
                        ) == nil
                    }
                }
            result = CommonUtil.sortMinecraftVersions(filteredVersions)
        default:
            let gameVersions = await ModrinthService.fetchGameVersions(
                includeSnapshots: includeSnapshots
            )
            let allVersions = gameVersions
                .map { version in
                    // Cache time information for each version
                    let cacheKey = "version_time_\(version.version)"
                    let formattedTime = CommonUtil.formatRelativeTime(
                        version.date
                    )
                    AppCacheManager.shared.setSilently(
                        namespace: "version_time",
                        key: cacheKey,
                        value: formattedTime
                    )
                    return version.version
                }
            result = CommonUtil.sortMinecraftVersions(allVersions)
        }
        return result
    }

    // Common classpath generation for forge and neoforge
    static func generateClasspath(
        from loader: ModrinthLoader,
        librariesDir: URL
    ) -> String {
        let jarPaths: [String] = loader.libraries.compactMap { lib in
            guard lib.includeInClasspath else { return nil }
            if lib.includeInClasspath {
                guard let downloads = lib.downloads else { return nil }
                let artifact = downloads.artifact
                guard let artifactPath = artifact.path else { return nil }
                return librariesDir.appendingPathComponent(artifactPath).path
            } else {
                return ""
            }
        }
        return jarPaths.joined(separator: ":")
    }

    /// Get all loader versions (silent versions) for the specified loader type and Minecraft version
    /// - Parameters:
    ///   - type: loader type
    ///   - minecraftVersion: Minecraft version
    /// - Returns: loader version information, returns nil on failure
    static func fetchAllLoaderVersions(
        type: String,
        minecraftVersion: String
    ) async -> LoaderVersion? {
        do {
            return try await fetchAllLoaderVersionsThrowing(
                type: type,
                minecraftVersion: minecraftVersion
            )
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to get loader version: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            return nil
        }
    }

    /// Get all loader versions for the specified loader type and Minecraft version (throws exception version)
    /// - Parameters:
    ///   - type: loader type
    ///   - minecraftVersion: Minecraft version
    /// - Returns: loader version information
    /// - Throws: GlobalError when the operation fails
    static func fetchAllLoaderVersionsThrowing(
        type: String,
        minecraftVersion: String
    ) async throws -> LoaderVersion {
        let manifest = try await fetchAllVersionThrowing(type: type)

        // Filter out results with id equal to current minecraftVersion
        let filteredVersions = manifest.filter { $0.id == minecraftVersion }

        // Returns the first matching version, or throws an error if there is none
        guard let firstVersion = filteredVersions.first else {
            throw GlobalError.resource(
                i18nKey: "Loader version not found",
                level: .notification
            )
        }

        return firstVersion
    }

    /// Get all versions of the specified loader type (throws exception version)
    /// - Parameter type: loader type
    /// - Returns: version list
    /// - Throws: GlobalError when the operation fails
    static func fetchAllVersionThrowing(
        type: String
    ) async throws -> [LoaderVersion] {
        // Get version list
        let manifestURL = URLConfig.API.Modrinth.loaderManifest(loader: type)
        // Use a unified API client
        let manifestData = try await APIClient.get(url: manifestURL)

        // parse version list
        do {
            let result = try JSONDecoder().decode(
                ModrinthLoaderVersion.self,
                from: manifestData
            )

            // For NeoForge, there is no stable filtering as all versions are beta
            if type == "neo" {
                return result.gameVersions
            } else {
                // Filter out stable versions
                return result.gameVersions.filter { $0.stable }
            }
        } catch {
            throw GlobalError.validation(
                i18nKey: "Version Manifest Parse Failed",
                level: .notification
            )
        }
    }

    /// Convert Maven coordinates to file paths (classifier and @ symbols are supported)
    /// - Parameter coordinate: Maven coordinates
    /// - Returns: file path
    static func convertMavenCoordinateToPath(_ coordinate: String) -> String {
        // Check whether it contains the @ symbol, which requires special handling
        if coordinate.contains("@") {
            return convertMavenCoordinateWithAtSymbol(coordinate)
        }

        // For standard Maven coordinates, use the CommonService method
        if let relativePath = mavenCoordinateToRelativePath(coordinate) {

            return AppPaths.librariesDirectory.appendingPathComponent(
                relativePath
            ).path
        }

        // If the CommonService method fails, possibly in a non-standard format, the original value is returned
        return coordinate
    }

    /// Common logic for parsing Maven coordinates containing @ symbols
    /// - Parameter coordinate: Maven coordinates
    /// - Returns: relative path
    static func parseMavenCoordinateWithAtSymbol(
        _ coordinate: String
    ) -> String {
        let parts = coordinate.components(separatedBy: ":")
        guard parts.count >= 3 else { return coordinate }

        let groupId = parts[0]
        let artifactId = parts[1]

        // Process version part, may contain @ symbol
        var version = parts[2]
        var classifier = ""
        var classifierName = ""

        // Check if version part contains @ symbol
        if version.contains("@") {
            let versionParts = version.components(separatedBy: "@")
            if versionParts.count >= 2 {
                version = versionParts[0]
                classifier = versionParts[1]
            }
        } else if parts.count > 3 {
            // If there is no @ symbol in the version but there is an extra part, it is treated as a classifier
            let classifierPart = parts[3]
            // Check whether the classifier part contains the @ symbol (such as client@lzma)
            if classifierPart.contains("@") {
                let classifierParts = classifierPart.components(
                    separatedBy: "@"
                )
                if classifierParts.count >= 2 {
                    classifierName = classifierParts[0]  // Take the part before @ as the classifier name
                    classifier = classifierParts[1]  // Take the part after @ as the extension
                }
            } else {
                classifier = classifierPart
            }
        }

        // Build file name
        // Use string interpolation to construct file names to avoid multiple string concatenations
        let classifierSuffix = classifierName.isEmpty ? "" : "-\(classifierName)"
        let extensionSuffix = classifier.isEmpty ? ".\(AppConstants.FileExtensions.jar)" : ".\(classifier)"
        let fileName = "\(artifactId)-\(version)\(classifierSuffix)\(extensionSuffix)"

        // Build relative path
        let groupPath = groupId.replacingOccurrences(of: ".", with: "/")
        return "\(groupPath)/\(artifactId)/\(version)/\(fileName)"
    }

    /// Handle Maven coordinates containing @ symbol
    /// - Parameter coordinate: Maven coordinates
    /// - Returns: file path
    static func convertMavenCoordinateWithAtSymbol(
        _ coordinate: String
    ) -> String {
        let relativePath = parseMavenCoordinateWithAtSymbol(coordinate)

        return AppPaths.librariesDirectory.appendingPathComponent(relativePath)
            .path
    }
    /// Maven coordinates to relative path
    /// - Parameter coordinate: Maven coordinate
    /// - Returns: relative path
    static func mavenCoordinateToRelativePath(_ coordinate: String) -> String? {
        let parts = coordinate.split(separator: ":")
        guard parts.count >= 3 else { return nil }

        let group = parts[0].replacingOccurrences(of: ".", with: "/")
        let artifact = parts[1]

        var version = ""
        var classifier: String?

        if parts.count == 3 {
            // group:artifact:version
            version = String(parts[2])
        } else if parts.count == 4 {
            // group:artifact:version:classifier (MC in this case)
            version = String(parts[2])
            classifier = String(parts[3])
        } else if parts.count == 5 {
            // group:artifact:packaging:classifier:version
            version = String(parts[4])
            classifier = String(parts[3])
        }

        if let classifier = classifier {
            return
                "\(group)/\(artifact)/\(version)/\(artifact)-\(version)-\(classifier).jar"
        } else {
            return "\(group)/\(artifact)/\(version)/\(artifact)-\(version).jar"
        }
    }

    /// Maven coordinates to relative path (supports special formats)
    /// - Parameter coordinate: Maven coordinate
    /// - Returns: relative path
    static func mavenCoordinateToRelativePathForURL(_ coordinate: String) -> String {
        // Check whether it contains the @ symbol, which requires special handling
        if coordinate.contains("@") {
            return convertMavenCoordinateWithAtSymbolForURL(coordinate)
        }

        // For standard Maven coordinates, use the standard method
        if let relativePath = mavenCoordinateToRelativePath(coordinate) {
            return relativePath
        }

        // If the standard method fails, possibly in a non-standard format, the original value is returned
        return coordinate
    }

    /// Handling Maven coordinates containing @ symbols (for URL building)
    /// - Parameter coordinate: Maven coordinates
    /// - Returns: relative path
    static func convertMavenCoordinateWithAtSymbolForURL(
        _ coordinate: String
    ) -> String {
        parseMavenCoordinateWithAtSymbol(coordinate)
    }

    /// Maven coordinates to FabricMC Maven warehouse URL
    /// - Parameter coordinate: Maven coordinate
    /// - Returns: Maven repository URL
    static func mavenCoordinateToURL(lib: ModrinthLoaderLibrary) -> URL? {
        // Use relative paths instead of full paths to build URLs
        let relativePath = mavenCoordinateToRelativePathForURL(lib.name)
        return lib.url?.appendingPathComponent(relativePath)
    }

    /// Maven coordinates to default Minecraft library URL
    /// - Parameter coordinate: Maven coordinate
    /// - Returns: Minecraft library URL
    static func mavenCoordinateToDefaultURL(_ coordinate: String, url: URL) -> URL {
        // Use relative paths instead of full paths to build URLs
        let relativePath = mavenCoordinateToRelativePathForURL(coordinate)
        return url.appendingPathComponent(relativePath)
    }

    /// Maven coordinates to default path (for local file paths)
    /// - Parameter coordinate: Maven coordinate
    /// - Returns: local file path
    static func mavenCoordinateToDefaultPath(_ coordinate: String) -> String {
        // Use relative paths instead of full paths to build URLs
        return mavenCoordinateToRelativePathForURL(coordinate)
    }
    /// Generate classpath string based on FabricLoader
    /// - Parameters:
    ///   - loader: Fabric loader
    ///   - librariesDir: library directory
    /// - Returns: classpath string
    static func generateFabricClasspath(
        from loader: ModrinthLoader,
        librariesDir: URL
    ) -> String {
        let jarPaths = loader.libraries.compactMap { coordinate -> String? in
            guard let relPath = mavenCoordinateToRelativePath(coordinate.name)
            else { return nil }
            return librariesDir.appendingPathComponent(relPath).path
        }
        return jarPaths.joined(separator: ":")
    }

    /// Handling game version placeholders in ModrinthLoader
    /// - Parameters:
    ///   - loader: raw loader data
    ///   - gameVersion: game version
    /// - Returns: processed loader data
    static func processGameVersionPlaceholders(
        loader: ModrinthLoader,
        gameVersion: String
    ) -> ModrinthLoader {
        var processedLoader = loader

        // Handling URL placeholders in libraries
        processedLoader.libraries = loader.libraries.map { library in
            var processedLibrary = library

            // Handle placeholders in name field
            processedLibrary.name = library.name.replacingOccurrences(
                of: "${modrinth.gameVersion}",
                with: gameVersion
            )

            return processedLibrary
        }
        return processedLoader
    }
}
