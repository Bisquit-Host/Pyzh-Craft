import Foundation

/// Mod update detector
/// Detect local mod updates
enum ModUpdateChecker {
    
    /// Test results
    struct UpdateCheckResult {
        /// Is there a new version
        let hasUpdate: Bool
        /// Currently installed version hash
        let currentHash: String?
        /// The latest version of hash
        let latestHash: String?
        /// Latest version information
        let latestVersion: ModrinthProjectDetailVersion?
    }
    
    /// Check if a local mod has a new version
    /// - Parameters:
    ///   - project: Modrinth project information
    ///   - gameInfo: game information
    ///   - resourceType: resource type (mod, datapack, shader, resourcepack)
    /// - Returns: Update detection results
    static func checkForUpdate(
        project: ModrinthProject,
        gameInfo: GameVersionInfo,
        resourceType: String
    ) async -> UpdateCheckResult {
        // If it is a local file (projectId starts with "local_" or "file_"), updates are not detected
        if project.projectId.hasPrefix("local_") || project.projectId.hasPrefix("file_") {
            return UpdateCheckResult(
                hasUpdate: false,
                currentHash: nil,
                latestHash: nil,
                latestVersion: nil
            )
        }
        
        // 1. Get the hash of local file
        guard let resourceDir = AppPaths.resourceDirectory(
            for: resourceType,
            gameName: gameInfo.gameName
        ) else {
            return UpdateCheckResult(
                hasUpdate: false,
                currentHash: nil,
                latestHash: nil,
                latestVersion: nil
            )
        }
        
        // Get the currently installed file hash
        let currentHash = await getCurrentInstalledHash(
            project: project,
            resourceDir: resourceDir
        )
        
        guard let currentHash = currentHash else {
            // If the current hash cannot be obtained, it is considered that there is no update
            return UpdateCheckResult(
                hasUpdate: false,
                currentHash: nil,
                latestHash: nil,
                latestVersion: nil
            )
        }
        
        // 2. Get the latest compatible version
        let loaderFilters = [gameInfo.modLoader.lowercased()]
        let versionFilters = [gameInfo.gameVersion]
        
        do {
            let versions = try await ModrinthService.fetchProjectVersionsFilter(
                id: project.projectId,
                selectedVersions: versionFilters,
                selectedLoaders: loaderFilters,
                type: resourceType
            )
            
            // Get the latest version (the first version is usually the latest)
            guard let latestVersion = versions.first,
                  let primaryFile = ModrinthService.filterPrimaryFiles(
                    from: latestVersion.files
                  ) else {
                return UpdateCheckResult(
                    hasUpdate: false,
                    currentHash: currentHash,
                    latestHash: nil,
                    latestVersion: nil
                )
            }
            
            let latestHash = primaryFile.hashes.sha1
            
            // 3. Compare hashes
            let hasUpdate = currentHash != latestHash
            
            return UpdateCheckResult(
                hasUpdate: hasUpdate,
                currentHash: currentHash,
                latestHash: latestHash,
                latestVersion: latestVersion
            )
        } catch {
            Logger.shared.error("Failed to detect mod updates: \(error.localizedDescription)")
            return UpdateCheckResult(
                hasUpdate: false,
                currentHash: currentHash,
                latestHash: nil,
                latestVersion: nil
            )
        }
    }
    
    /// Get the currently installed file hash
    /// - Parameters:
    ///   - project: Modrinth project information
    ///   - resourceDir: resource directory
    /// - Returns: currently installed file hash, returns nil if not found
    private static func getCurrentInstalledHash(
        project: ModrinthProject,
        resourceDir: URL
    ) async -> String? {
        // Method 1: Search by file name (if the project has fileName)
        if let fileName = project.fileName {
            let fileURL = resourceDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return ModScanner.sha1Hash(of: fileURL)
            }
            
            // Also check the .disabled version
            let disabledFileName = fileName + ".disabled"
            let disabledFileURL = resourceDir.appendingPathComponent(disabledFileName)
            if FileManager.default.fileExists(atPath: disabledFileURL.path) {
                return ModScanner.sha1Hash(of: disabledFileURL)
            }
        }
        
        // Method 2: Find by project ID (scan directory)
        // If the project has a projectId, try to find matching files by scanning
        if !project.projectId.isEmpty {
            let localDetails = ModScanner.shared.localModDetails(in: resourceDir)
            if let matchingDetail = localDetails.first(where: { $0.detail?.id == project.projectId }) {
                return matchingDetail.hash
            }
        }
        
        return nil
    }
}
