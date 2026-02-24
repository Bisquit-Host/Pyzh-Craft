import Foundation

/// Resource installation status checker
/// Responsible for checking whether the resource has been installed in the specified game
enum ResourceInstallationChecker {
    /// Check if the resource is installed in server mode
    /// - Parameters:
    ///   - project: Modrinth project
    ///   - resourceType: resource type
    ///   - installedHashes: a collection of hashes of installed resources
    ///   - selectedVersions: List of selected game versions
    ///   - selectedLoaders: selected loader list
    ///   - gameInfo: game information (optional, used for details)
    /// - Returns: Whether it is installed
    static func checkInstalledStateForServerMode(
        project: ModrinthProject,
        resourceType: String,
        installedHashes: Set<String>,
        selectedVersions: [String],
        selectedLoaders: [String],
        gameInfo: GameVersionInfo?
    ) async -> Bool {
        guard !installedHashes.isEmpty else { return false }
        
        // Construct version/loader filter conditions (user selection is used first, and current game information is used secondly)
        let versionFilters: [String] = {
            if !selectedVersions.isEmpty {
                return selectedVersions
            }
            if let gameInfo = gameInfo {
                return [gameInfo.gameVersion]
            }
            return []
        }()
        
        let loaderFilters: [String] = {
            if !selectedLoaders.isEmpty {
                return selectedLoaders.map { $0.lowercased() }
            }
            if let gameInfo = gameInfo {
                return [gameInfo.modLoader.lowercased()]
            }
            return []
        }()
        
        do {
            let versions = try await ModrinthService.fetchProjectVersionsFilter(
                id: project.projectId,
                selectedVersions: versionFilters,
                selectedLoaders: loaderFilters,
                type: resourceType
            )
            
            for version in versions {
                guard
                    let primaryFile = ModrinthService.filterPrimaryFiles(
                        from: version.files
                    )
                else { continue }
                
                if installedHashes.contains(primaryFile.hashes.sha1) {
                    return true
                }
            }
        } catch {
            Logger.shared.error(
                "Failed to get project version to check installation status: \(error.localizedDescription)"
            )
        }
        
        return false
    }
}
