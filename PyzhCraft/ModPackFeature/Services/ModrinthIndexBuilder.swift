import Foundation

/// Modrinth index builder
/// Responsible for building the modrinth.index.json file
enum ModrinthIndexBuilder {
    /// Build index JSON string
    /// - Parameters:
    ///   - gameInfo: game information
    ///   - modPackName: integration package name
    ///   - modPackVersion: integration package version
    ///   - summary: integration package description
    ///   - files: index file list
    /// - Returns: JSON string
    static func build(
        gameInfo: GameVersionInfo,
        modPackName: String,
        modPackVersion: String,
        summary: String?,
        files: [ModrinthIndexFile]
    ) async throws -> String {
        let gameVersion = gameInfo.gameVersion
        let loaderType = gameInfo.modLoader.lowercased()

        // Get loader version
        let loaderVersion = await LoaderVersionResolver.resolve(
            loaderType: loaderType,
            gameVersion: gameVersion,
            gameInfo: gameInfo
        )

        Logger.shared.info("Export modpack - Loader type: \(loaderType), Version: \(loaderVersion ?? "not found")")

        // Build dependency dictionary
        let dependencies = buildDependencies(
            gameVersion: gameVersion,
            loaderType: loaderType,
            loaderVersion: loaderVersion
        )

        // Build JSON dictionary
        var jsonDict: [String: Any] = [
            "formatVersion": 1,
            "game": "minecraft",
            "versionId": modPackVersion,
            "name": modPackName,
        ]

        if let summary = summary {
            jsonDict["summary"] = summary
        }

        // Encode files, exclude non-standard fields
        var filesArray: [[String: Any]] = []
        for file in files {
            var fileDict: [String: Any] = [
                "path": file.path,
                "hashes": [
                    "sha1": file.hashes.sha1 ?? "",
                    "sha512": file.hashes.sha512 ?? "",
                ],
                "downloads": file.downloads,
                "fileSize": file.fileSize,
            ]

            // Add env field if present
            if let env = file.env {
                var envDict: [String: String] = [:]
                if let client = env.client {
                    envDict["client"] = client
                }
                if let server = env.server {
                    envDict["server"] = server
                }
                if !envDict.isEmpty {
                    fileDict["env"] = envDict
                }
            }

            filesArray.append(fileDict)
        }
        jsonDict["files"] = filesArray

        // coding dependencies
        var depsDict: [String: Any] = [:]
        if let minecraft = dependencies.minecraft {
            depsDict["minecraft"] = minecraft
        }
        if let forgeLoader = dependencies.forgeLoader {
            depsDict["forge-loader"] = forgeLoader
        }
        if let fabricLoader = dependencies.fabricLoader {
            depsDict["fabric-loader"] = fabricLoader
        }
        if let quiltLoader = dependencies.quiltLoader {
            depsDict["quilt-loader"] = quiltLoader
        }
        if let neoforgeLoader = dependencies.neoforgeLoader {
            depsDict["neoforge-loader"] = neoforgeLoader
        }
        jsonDict["dependencies"] = depsDict

        // Convert to JSON string
        let jsonData = try JSONSerialization.data(
            withJSONObject: jsonDict,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(data: jsonData, encoding: .utf8) ?? ""
    }

    /// Build dependency dictionary
    private static func buildDependencies(
        gameVersion: String,
        loaderType: String,
        loaderVersion: String?
    ) -> ModrinthIndexDependencies {
        switch loaderType {
        case "forge":
            return ModrinthIndexDependencies(
                minecraft: gameVersion,
                forgeLoader: loaderVersion,
                fabricLoader: nil,
                quiltLoader: nil,
                neoforgeLoader: nil,
                forge: nil,
                fabric: nil,
                quilt: nil,
                neoforge: nil,
                dependencies: nil
            )
        case "fabric":
            return ModrinthIndexDependencies(
                minecraft: gameVersion,
                forgeLoader: nil,
                fabricLoader: loaderVersion,
                quiltLoader: nil,
                neoforgeLoader: nil,
                forge: nil,
                fabric: nil,
                quilt: nil,
                neoforge: nil,
                dependencies: nil
            )
        case "quilt":
            return ModrinthIndexDependencies(
                minecraft: gameVersion,
                forgeLoader: nil,
                fabricLoader: nil,
                quiltLoader: loaderVersion,
                neoforgeLoader: nil,
                forge: nil,
                fabric: nil,
                quilt: nil,
                neoforge: nil,
                dependencies: nil
            )
        case "neoforge":
            return ModrinthIndexDependencies(
                minecraft: gameVersion,
                forgeLoader: nil,
                fabricLoader: nil,
                quiltLoader: nil,
                neoforgeLoader: loaderVersion,
                forge: nil,
                fabric: nil,
                quilt: nil,
                neoforge: nil,
                dependencies: nil
            )
        default:
            return ModrinthIndexDependencies(
                minecraft: gameVersion,
                forgeLoader: nil,
                fabricLoader: nil,
                quiltLoader: nil,
                neoforgeLoader: nil,
                forge: nil,
                fabric: nil,
                quilt: nil,
                neoforge: nil,
                dependencies: nil
            )
        }
    }
}

/// Loader version parser
enum LoaderVersionResolver {
    /// Parse loader version
    /// Preferably get from modVersion field, if not present try to infer from installed loader mod
    static func resolve(
        loaderType: String,
        gameVersion: String,
        gameInfo: GameVersionInfo
    ) async -> String? {
        // 1. Try to get from modVersion field
        if !gameInfo.modVersion.isEmpty {
            if isValidVersionFormat(gameInfo.modVersion) {
                return gameInfo.modVersion
            }
        }

        // 2. Try to infer version from installed loader mod
        let modsDir = AppPaths.modsDirectory(gameName: gameInfo.gameName)
        guard let modFiles = try? ResourceScanner.scanResourceDirectory(modsDir) else {
            return nil
        }

        // Find the corresponding loader mod based on the loader type
        let loaderModPatterns: [String]
        switch loaderType {
        case "fabric":
            loaderModPatterns = ["fabric-api"]
        case "forge":
            loaderModPatterns = ["forge", "minecraftforge"]
        case "quilt":
            loaderModPatterns = ["quilt-loader", "quilt-standard"]
        case "neoforge":
            loaderModPatterns = ["neoforge"]
        default:
            return nil
        }

        // Find loader mod files
        for modFile in modFiles where loaderModPatterns.contains(where: { modFile.lastPathComponent.lowercased().contains($0) }) {
            let fileName = modFile.lastPathComponent.lowercased()
            // Try to extract the version number from the file name
            if let version = extractVersionFromFileName(fileName) {
                return version
            }

            // If there is no version in the filename, try getting it from Modrinth
            if let modrinthInfo = await ModrinthResourceIdentifier.getModrinthInfo(for: modFile) {
                // The cache contains optional server_side and client_side information
                cacheModrinthSideInfo(modrinthInfo: modrinthInfo, modFile: modFile)

                let versionName = modrinthInfo.version.name
                if let version = extractVersionFromString(versionName) {
                    return version
                }
                if !modrinthInfo.version.versionNumber.isEmpty {
                    return modrinthInfo.version.versionNumber
                }
            }
        }

        // 3. For Fabric, try to extract the version from the startup parameters
        if loaderType == "fabric" {
            for arg in gameInfo.launchCommand where arg.contains("fabric-loader") {
                if let version = extractVersionFromString(arg) {
                    return version
                }
            }
        }

        return nil
    }

    /// Verify that the version number format is valid
    private static func isValidVersionFormat(_ version: String) -> Bool {
        let pattern = #"^\d+\.\d+(\.\d+)?(-.*)?$"#
        return version.range(of: pattern, options: .regularExpression) != nil
    }

    /// Extract version number from file name
    private static func extractVersionFromFileName(_ fileName: String) -> String? {
        let patterns = [
            #"(\d+\.\d+\.\d+)"#,      // 1.2.3
            #"(\d+\.\d+)"#,            // 1.2
            #"v?(\d+\.\d+\.\d+)"#,     // v1.2.3
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)),
               let range = Range(match.range(at: 1), in: fileName) {
                return String(fileName[range])
            }
        }

        return nil
    }

    /// Extract version number from string
    private static func extractVersionFromString(_ string: String) -> String? {
        extractVersionFromFileName(string.lowercased())
    }

    /// Caching server_side and client_side information for Modrinth projects
    /// Only cache data containing "optional" values
    private static func cacheModrinthSideInfo(
        modrinthInfo: ModrinthResourceIdentifier.ModrinthModInfo,
        modFile: URL
    ) {
        let projectDetail = modrinthInfo.projectDetail

        // Check if caching is required (at least one is optional)
        let shouldCache = projectDetail.clientSide == "optional" || projectDetail.serverSide == "optional"

        guard shouldCache else {
            return
        }

        // Use file hash as cache key
        guard let hash = try? SHA1Calculator.sha1(ofFileAt: modFile) else {
            return
        }

        // Build cache data structure
        let sideInfo = ModrinthSideInfo(
            clientSide: projectDetail.clientSide,
            serverSide: projectDetail.serverSide,
            projectId: projectDetail.id
        )

        // Cache to AppCacheManager
        let cacheKey = "modrinth_side_\(hash)"
        AppCacheManager.shared.setSilently(
            namespace: "modrinth_side_info",
            key: cacheKey,
            value: sideInfo
        )
    }
}

/// Modrinth project's server_side and client_side information cache structures
private struct ModrinthSideInfo: Codable {
    let clientSide: String
    let serverSide: String
    let projectId: String

    enum CodingKeys: String, CodingKey {
        case clientSide = "client_side"
        case serverSide = "server_side"
        case projectId = "project_id"
    }
}
