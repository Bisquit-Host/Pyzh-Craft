import Foundation

/// Import instance information
/// Contains all necessary information parsed from other launchers
struct ImportInstanceInfo {
    /// Game name
    let gameName: String
    
    /// game version
    let gameVersion: String
    
    /// Mod loader types (vanilla, fabric, forge, neoforge, quilt)
    let modLoader: String
    
    /// Mod loader version
    let modLoaderVersion: String
    
    /// Game icon path (if any)
    let gameIconPath: URL?
    
    /// Icon download URL (if you need to download from the Internet)
    let iconDownloadUrl: String?
    
    /// Source game directory path (where the .minecraft folder is located)
    let sourceGameDirectory: URL
    
    /// Launcher type
    let launcherType: ImportLauncherType
}
