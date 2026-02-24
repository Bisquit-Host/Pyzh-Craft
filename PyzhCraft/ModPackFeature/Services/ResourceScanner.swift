import Foundation

/// Resource Scanner
/// Responsible for scanning all resource files (mods, datapacks, resourcepacks, shaderpacks) in the game instance
enum ResourceScanner {
    /// Resource type
    enum ResourceType: String, CaseIterable {
        case mods, datapacks, resourcepacks, shaderpacks
    }
    
    /// Scan results
    struct ScanResult {
        let type: ResourceType
        let files: [URL]
    }
    
    /// Scan all resource files
    /// - Parameter gameInfo: game information
    /// - Returns: Scan results grouped by type
    static func scanAllResources(gameInfo: GameVersionInfo) throws -> [ResourceType: [URL]] {
        var results: [ResourceType: [URL]] = [:]
        
        for resourceType in ResourceType.allCases {
            let directory = getDirectory(for: resourceType, gameName: gameInfo.gameName)
            let files = try scanResourceDirectory(directory)
            results[resourceType] = files
        }
        
        return results
    }
    
    /// Get the directory path corresponding to the resource type
    private static func getDirectory(for type: ResourceType, gameName: String) -> URL {
        switch type {
        case .mods:
            return AppPaths.modsDirectory(gameName: gameName)
        case .datapacks:
            return AppPaths.datapacksDirectory(gameName: gameName)
        case .resourcepacks:
            return AppPaths.resourcepacksDirectory(gameName: gameName)
        case .shaderpacks:
            return AppPaths.shaderpacksDirectory(gameName: gameName)
        }
    }
    
    /// Scan a single resource directory
    /// - Parameter directory: directory path
    /// - Returns: List of found resource files
    static func scanResourceDirectory(_ directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        return files.filter { file in
            // Includes .jar and .zip files, excludes .disabled files
            let ext = file.pathExtension.lowercased()
            return (ext == "jar" || ext == "zip") && !file.lastPathComponent.hasSuffix(".disabled")
        }
    }
    
    /// Calculate the total number of resource files
    /// - Parameter results: scan results
    /// - Returns: total number of files
    static func totalFileCount(_ results: [ResourceType: [URL]]) -> Int {
        results.values.reduce(0) { $0 + $1.count }
    }
}
