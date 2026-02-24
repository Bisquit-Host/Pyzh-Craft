import Foundation

/// GDLauncher instance parser
struct GDLauncherInstanceParser: LauncherInstanceParser {
    let launcherType: ImportLauncherType = .gdLauncher
    
    func isValidInstance(at instancePath: URL) -> Bool {
        let instanceJsonPath = instancePath.appendingPathComponent("instance.json")
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: instanceJsonPath.path) else {
            return false
        }
        
        // Verify that the JSON file can be parsed
        do {
            _ = try parseInstanceJson(at: instanceJsonPath)
            return true
        } catch {
            return false
        }
    }
    
    func parseInstance(at instancePath: URL, basePath: URL) throws -> ImportInstanceInfo? {
        let instanceJsonPath = instancePath.appendingPathComponent("instance.json")
        let instanceConfig = try parseInstanceJson(at: instanceJsonPath)
        
        // Extract game version
        let gameVersion = instanceConfig.gameConfiguration.version.release
        
        // Extract Mod loader information (take the first modloader)
        var modLoader = "vanilla"
        var modLoaderVersion = ""
        
        if let firstModLoader = instanceConfig.gameConfiguration.version.modloaders.first {
            modLoader = firstModLoader.type.lowercased()
            modLoaderVersion = firstModLoader.version
        }
        
        // Extract game name
        let gameName = instanceConfig.name
        
        // Extract icon path
        var gameIconPath: URL?
        if let iconName = instanceConfig.icon {
            let iconPath = instancePath.appendingPathComponent(iconName)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: iconPath.path) {
                gameIconPath = iconPath
            }
        }
        
        return ImportInstanceInfo(
            gameName: gameName,
            gameVersion: gameVersion,
            modLoader: modLoader,
            modLoaderVersion: modLoaderVersion,
            gameIconPath: gameIconPath,
            iconDownloadUrl: nil,
            sourceGameDirectory: instancePath,
            launcherType: launcherType
        )
    }
    
    // MARK: - Private Methods
    
    /// Parse instance.json file
    private func parseInstanceJson(at path: URL) throws -> GDLauncherInstanceConfig {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(GDLauncherInstanceConfig.self, from: data)
    }
}

// MARK: - GDLauncher Models
private struct GDLauncherInstanceConfig: Codable {
    let name: String
    let icon: String?
    let gameConfiguration: GDLauncherGameConfiguration
    
    enum CodingKeys: String, CodingKey {
        case name, icon, gameConfiguration = "game_configuration"
    }
}

private struct GDLauncherGameConfiguration: Codable {
    let version: GDLauncherVersion
}

private struct GDLauncherVersion: Codable {
    let release: String
    let modloaders: [GDLauncherModLoader]
}

private struct GDLauncherModLoader: Codable {
    let type: String
    let version: String
}
