import Foundation
import ZIPFoundation

/// CurseForge integration package manifest.json parser
enum CurseForgeManifestParser {

    // MARK: - Public Methods

    /// Parse the manifest.json file of the CurseForge integration package
    /// - Parameter extractedPath: decompressed integration package path
    /// - Returns: parsed Modrinth index information
    static func parseManifest(extractedPath: URL) async -> ModrinthIndexInfo? {
        do {
            // Find the manifest.json file
            let manifestPath = extractedPath.appendingPathComponent("manifest.json")

            Logger.shared.info("Try parsing CurseForge manifest.json: \(manifestPath.path)")

            guard FileManager.default.fileExists(atPath: manifestPath.path) else {
                // List the files in the unzipped directory to help debugging
                do {
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: extractedPath,
                        includingPropertiesForKeys: nil
                    )
                    Logger.shared.info("Unzip directory contents: \(contents.map { $0.lastPathComponent })")
                } catch {
                    Logger.shared.error("Unable to list unzipped directory contents: \(error.localizedDescription)")
                }

                Logger.shared.warning("Manifest.json file not found in CurseForge integration package")
                return nil
            }

            // Get file size
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: manifestPath.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0
            Logger.shared.info("manifest.json file size: \(fileSize) bytes")

            guard fileSize > 0 else {
                Logger.shared.error("manifest.json file is empty")
                return nil
            }

            // Read and parse files
            let manifestData = try Data(contentsOf: manifestPath)
            Logger.shared.info("Successfully read manifest.json data, size: \(manifestData.count) bytes")

            // Try to parse JSON
            let manifest = try JSONDecoder().decode(CurseForgeManifest.self, from: manifestData)

            // Extract loader information
            let loaderInfo = determineLoaderInfo(from: manifest.minecraft.modLoaders)

            // Generate version information (if version field is missing)
            let modPackVersion = manifest.version ?? generateAutoVersion(
                modPackName: manifest.name,
                gameVersion: manifest.minecraft.version,
                loaderInfo: loaderInfo
            )

            // Convert to Modrinth format
            let modrinthInfo = await convertToModrinthFormat(
                manifest: manifest,
                loaderInfo: loaderInfo,
                generatedVersion: modPackVersion
            )

            Logger.shared.info("Parsing CurseForge manifest.json successfully: \(manifest.name) v\(modPackVersion)")
            if manifest.version == nil {
                Logger.shared.info("⚠️ The integration package lacks the version field and the version has been automatically generated: \(modPackVersion)")
            }
            Logger.shared.info("Game version: \(manifest.minecraft.version), loader: \(loaderInfo.type) \(loaderInfo.version)")
            Logger.shared.info("Number of files: \(manifest.files.count)")

            return modrinthInfo
        } catch {
            Logger.shared.error("Detailed error in parsing CurseForge manifest.json: \(error)")

            // If it is a JSON parsing error, try to display part of the content
            if let jsonError = error as? DecodingError {
                Logger.shared.error("JSON parsing error: \(jsonError)")
            }

            return nil
        }
    }

    // MARK: - Helper Methods

    /// Determine the loader type and version from the list of mod loaders
    /// - Parameter modLoaders: Mod loader list
    /// - Returns: loader type and version
    private static func determineLoaderInfo(from modLoaders: [CurseForgeModLoader]) -> (type: String, version: String) {
        // Find the major mod loaders
        guard let primaryLoader = modLoaders.first(where: { $0.primary }) ?? modLoaders.first else {
            return ("vanilla", "unknown")
        }

        let loaderId = primaryLoader.id.lowercased()

        // Resolves the loader ID, usually in the format "forge-40.2.0" or "fabric-0.14.21"
        let components = loaderId.split(separator: "-")

        if components.count >= 2 {
            let loaderType = String(components[0])
            let loaderVersion = components.dropFirst().joined(separator: "-")

            // Standardized loader type name
            let normalizedType = normalizeLoaderType(loaderType)

            return (normalizedType, loaderVersion)
        } else {
            // If the format is not standard, try to extract the type from the ID
            if loaderId.contains("forge") {
                return ("forge", "unknown")
            } else if loaderId.contains("fabric") {
                return ("fabric", "unknown")
            } else if loaderId.contains("quilt") {
                return ("quilt", "unknown")
            } else if loaderId.contains("neoforge") {
                return ("neoforge", "unknown")
            } else {
                return ("vanilla", "unknown")
            }
        }
    }

    /// Standardized loader type name
    /// - Parameter loaderType: original loader type
    /// - Returns: standardized loader type
    private static func normalizeLoaderType(_ loaderType: String) -> String {
        switch loaderType.lowercased() {
        case "forge":
            return "forge"
        case "fabric":
            return "fabric"
        case "quilt":
            return "quilt"
        case "neoforge":
            return "neoforge"
        default:
            return loaderType.lowercased()
        }
    }

    /// Automatically generate integration package version number
    /// - Parameters:
    ///   - modPackName: integration package name
    ///   - gameVersion: game version
    ///   - loaderInfo: loader information
    /// - Returns: automatically generated version number
    private static func generateAutoVersion(
        modPackName: String,
        gameVersion: String,
        loaderInfo: (type: String, version: String)
    ) -> String {
        // Create current timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())

        // Generate version format: game version-loader type-date
        // For example: 1.20.1-forge-20241212
        let autoVersion = "\(gameVersion)-\(loaderInfo.type)-\(dateString)"

        Logger.shared.info("Automatically generate integration package version: \(autoVersion)")
        return autoVersion
    }

    /// Convert CurseForge manifest to Modrinth format
    /// - Parameters:
    ///   - manifest: CurseForge manifest
    ///   - loaderInfo: loader information
    ///   - generatedVersion: generated version number (used when the version field is missing)
    /// - Returns: Modrinth index information
    private static func convertToModrinthFormat(
        manifest: CurseForgeManifest,
        loaderInfo: (type: String, version: String),
        generatedVersion: String
    ) async -> ModrinthIndexInfo {
        Logger.shared.info("Convert CurseForge format to Modrinth format, number of modules: \(manifest.files.count)")

        // Optimization: Instead of getting file details here, create a file object with lazy parsing
        // Delay the acquisition of real file details until the download stage to improve import speed
        var modrinthFiles: [ModrinthIndexFile] = []

        for file in manifest.files {
            // Create a placeholder file object containing basic information
            // The real file name, path and download URL will be obtained when downloading
            let placeholderPath = "mods/curseforge_\(file.projectID)_\(file.fileID).jar" // temporary path

            modrinthFiles.append(ModrinthIndexFile(
                path: placeholderPath,
                hashes: ModrinthIndexFileHashes(from: [:]), // CurseForge does not provide hashes
                downloads: [], // The download URL will be obtained while downloading
                fileSize: 0, // File size will be obtained when downloading
                env: nil, // default environment
                source: .curseforge, // Tag source is CurseForge
                // Save the original CurseForge file information for subsequent processing
                curseForgeProjectId: file.projectID,
                curseForgeFileId: file.fileID
            ))
        }

        Logger.shared.info("Quick conversion completed, details will be fetched during download stage")

        return ModrinthIndexInfo(
            gameVersion: manifest.minecraft.version,
            loaderType: loaderInfo.type,
            loaderVersion: loaderInfo.version,
            modPackName: manifest.name,
            modPackVersion: generatedVersion,
            summary: "",
            files: modrinthFiles, // CurseForge files converted to Modrinth files (placeholder)
            dependencies: [], // CurseForge format has no additional dependencies
            source: .curseforge
        )
    }
}
