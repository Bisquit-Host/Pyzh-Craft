import Foundation

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

// MARK: - GameNameGenerator
enum GameNameGenerator {
    /// Generate default game name for ModPack downloads
    /// - Parameters:
    ///   - projectTitle: project title
    ///   - gameVersion: game version
    ///   - includeTimestamp: whether to include timestamp (default true)
    /// - Returns: generated game name
    static func generateModPackName(
        projectTitle: String?,
        gameVersion: String,
        includeTimestamp: Bool = true
    ) -> String {
        let baseName = "\(projectTitle ?? "ModPack")-\(gameVersion)"
        
        if includeTimestamp {
            let timestamp = DateFormatter.timestampFormatter.string(from: Date())
            return "\(baseName)-\(timestamp)"
        }
        
        return baseName
    }
    
    /// Generate default game name for ModPack import
    /// - Parameters:
    ///   - modPackName: integration package name
    ///   - modPackVersion: integration package version
    ///   - includeTimestamp: whether to include timestamp (default true)
    /// - Returns: generated game name
    static func generateImportName(
        modPackName: String,
        modPackVersion: String,
        includeTimestamp: Bool = true
    ) -> String {
        let baseName = "\(modPackName)-\(modPackVersion)"
        
        if includeTimestamp {
            let timestamp = DateFormatter.timestampFormatter.string(from: Date())
            return "\(baseName)-\(timestamp)"
        }
        
        return baseName
    }
    
    /// Generate default game name for normal game creation
    /// - Parameters:
    ///   - gameVersion: game version
    ///   - modLoader: Mod loader
    /// - Returns: generated game name
    static func generateGameName(
        gameVersion: String,
        modLoader: String
    ) -> String {
        let loaderName = modLoader.lowercased() == "vanilla" ? "" : "-\(modLoader)"
        return "\(gameVersion)\(loaderName)"
    }
}
