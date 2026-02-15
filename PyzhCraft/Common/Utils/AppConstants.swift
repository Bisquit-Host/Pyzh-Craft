import Foundation

enum AppConstants {
    static let defaultGameIcon = "default_game_icon.png"
    static let modLoaders = ["vanilla", "fabric", "forge", "neoforge", "quilt"]
    static let modrinthIndex = "relevance"
    static let modrinthIndexFileName = "modrinth.index.json"

    // Minecraft client ID - will be replaced when building
    // Minecraft/Xbox certification
    static let minecraftClientId: String = {
        let encrypted = "$(CLIENTID)"
        return Obfuscator.decryptClientID(encrypted)
    }()
    static let minecraftScope = "XboxLive.signin offline_access"
    static let callbackURLScheme = "swift-craft-launcher"

    // CurseForge API Key - will be replaced when building
    static let curseForgeAPIKey: String? = {
        let encrypted = "$(CURSEFORGE_API_KEY)"
        return Obfuscator.decryptAPIKey(encrypted)
    }()
    // Cache resource type
    static let cacheResourceTypes = [DirectoryNames.libraries, DirectoryNames.natives, DirectoryNames.assets, DirectoryNames.versions]

    static let logTag = Bundle.main.identifier + ".logger"

    // MARK: - Directory Names
    /// Minecraft directory name constants
    enum DirectoryNames {
        static let mods = "mods"
        static let libraries = "libraries"
        static let natives = "natives"
        static let assets = "assets"
        static let versions = "versions"
        static let shaderpacks = "shaderpacks"
        static let resourcepacks = "resourcepacks"
        static let datapacks = "datapacks"
        static let saves = "saves"
        static let screenshots = "screenshots"
        static let schematics = "schematics"
        static let crashReports = "crash-reports"
        static let logs = "logs"
        static let profiles = "profiles"
        static let runtime = "runtime"
        static let meta = "meta"
        static let cache = "cache"
        static let data = "data"
    }

    // MARK: - File Extensions
    /// File extension constants (without dot)
    enum FileExtensions {
        static let jar = "jar"
        static let png = "png"
        static let zip = "zip"
        static let json = "json"
        static let log = "log"
    }

    // MARK: - Environment Types
    /// environment type constant
    enum EnvironmentTypes {
        static let client = "client"
        static let server = "server"
    }

    // MARK: - Processor Placeholders
    /// Processor placeholder constant
    enum ProcessorPlaceholders {
        static let side = "{SIDE}"
        static let version = "{VERSION}"
        static let versionName = "{VERSION_NAME}"
        static let libraryDir = "{LIBRARY_DIR}"
        static let workingDir = "{WORKING_DIR}"
    }

    // MARK: - UserDefaults Keys
    /// UserDefaults storage key constants
    enum UserDefaultsKeys {
        static let savedGames = "savedGames"
    }

    // MARK: - Database Tables
    /// Database table name constants
    enum DatabaseTables {
        static let gameVersions = "game_versions"
        static let modCache = "mod_cache"
    }
}

// MARK: - Bundle Extension
extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "beta"
    }

    var fullVersion: String {
        "\(appVersion)-\(buildNumber)"
    }
    var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Swift Craft Launcher"
    }
    var copyright: String {
        infoDictionary?["NSHumanReadableCopyright"] as? String ?? "Copyright © 2025 \(appName)"
    }

    var identifier: String {
        infoDictionary?["CFBundleIdentifier"] as? String ?? "com.su.code.PyzhCraft"
    }

    var appCategory: String {
        infoDictionary?["LSApplicationCategoryType"] as? String ?? "public.app-category.games"
    }
}
