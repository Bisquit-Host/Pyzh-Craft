import Foundation

enum AppPaths {
    // MARK: - Path Cache
    /// Path caching to avoid repeatedly creating the same URL object
    private static let pathCache = NSCache<NSString, NSURL>()
    private static let cacheQueue = DispatchQueue(label: "com.pyzhcraft.apppaths.cache", attributes: .concurrent)

    // MARK: - Cached Path Helper
    /// Get the cached URL path, create and cache it if it does not exist
    private static func cachedURL(key: String, factory: () -> URL) -> URL {
        return cacheQueue.sync {
            if let cached = pathCache.object(forKey: key as NSString) {
                return cached as URL
            }
            let url = factory()
            pathCache.setObject(url as NSURL, forKey: key as NSString)
            return url
        }
    }

    static var launcherSupportDirectory: URL {
    // guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
    //     return nil
    // }
        return cachedURL(key: "launcherSupportDirectory") {
            .applicationSupportDirectory.appendingPathComponent(Bundle.main.appName)
        }
    }
    static var runtimeDirectory: URL {
        launcherSupportDirectory.appendingPathComponent(AppConstants.DirectoryNames.runtime)
    }

    /// Path to the Java executable file of the specified version (jre.bundle in the runtime directory)
    static func javaExecutablePath(version: String) -> String {
        runtimeDirectory.appendingPathComponent(version).appendingPathComponent("jre.bundle/Contents/Home/bin/java").path
    }

    static var metaDirectory: URL {
        launcherSupportDirectory.appendingPathComponent(AppConstants.DirectoryNames.meta)
    }
    static var librariesDirectory: URL {
        metaDirectory.appendingPathComponent(AppConstants.DirectoryNames.libraries)
    }
    static var nativesDirectory: URL {
        metaDirectory.appendingPathComponent(AppConstants.DirectoryNames.natives)
    }
    static var assetsDirectory: URL {
        metaDirectory.appendingPathComponent(AppConstants.DirectoryNames.assets)
    }
    static var versionsDirectory: URL {
        metaDirectory.appendingPathComponent(AppConstants.DirectoryNames.versions)
    }
    static var profileRootDirectory: URL {
        let customPath = GeneralSettingsManager.shared.launcherWorkingDirectory
        let workingDirectory = customPath.isEmpty ? launcherSupportDirectory.path : customPath

        let baseURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        return baseURL.appendingPathComponent(AppConstants.DirectoryNames.profiles, isDirectory: true)
    }

    static func profileDirectory(gameName: String) -> URL {
        cachedURL(key: "profileDirectory:\(gameName)") {
            profileRootDirectory.appendingPathComponent(gameName)
        }
    }

    static func modsDirectory(gameName: String) -> URL {
        cachedURL(key: "modsDirectory:\(gameName)") {
            profileDirectory(gameName: gameName).appendingPathComponent(AppConstants.DirectoryNames.mods)
        }
    }

    static func datapacksDirectory(gameName: String) -> URL {
        cachedURL(key: "datapacksDirectory:\(gameName)") {
            profileDirectory(gameName: gameName).appendingPathComponent(AppConstants.DirectoryNames.datapacks)
        }
    }

    static func shaderpacksDirectory(gameName: String) -> URL {
        cachedURL(key: "shaderpacksDirectory:\(gameName)") {
            profileDirectory(gameName: gameName).appendingPathComponent(AppConstants.DirectoryNames.shaderpacks)
        }
    }

    static func resourcepacksDirectory(gameName: String) -> URL {
        cachedURL(key: "resourcepacksDirectory:\(gameName)") {
            profileDirectory(gameName: gameName).appendingPathComponent(AppConstants.DirectoryNames.resourcepacks)
        }
    }

    static func schematicsDirectory(gameName: String) -> URL {
        cachedURL(key: "schematicsDirectory:\(gameName)") {
            profileDirectory(gameName: gameName).appendingPathComponent(AppConstants.DirectoryNames.schematics, isDirectory: true)
        }
    }

    /// Clear the path cache related to the specified game (called when deleting the game)
    /// - Parameter gameName: game name
    static func invalidatePaths(forGameName gameName: String) {
        let keys = [
            "profileDirectory:\(gameName)",
            "modsDirectory:\(gameName)",
            "datapacksDirectory:\(gameName)",
            "shaderpacksDirectory:\(gameName)",
            "resourcepacksDirectory:\(gameName)",
            "schematicsDirectory:\(gameName)",
        ] as [NSString]
        cacheQueue.sync(flags: .barrier) {
            for key in keys {
                pathCache.removeObject(forKey: key)
            }
        }
    }

    static let profileSubdirectories = [
        AppConstants.DirectoryNames.shaderpacks,
        AppConstants.DirectoryNames.resourcepacks,
        AppConstants.DirectoryNames.mods,
        AppConstants.DirectoryNames.datapacks,
        AppConstants.DirectoryNames.crashReports,
    ]

    /// Log file directory - use the system standard log directory and fall back to the application support directory in case of failure
    static var logsDirectory: URL {
        if let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            return libraryDirectory.appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent(Bundle.main.appName, isDirectory: true)
        }
        // Alternate solution: Use the logs subdirectory under your application's support directory
        return launcherSupportDirectory.appendingPathComponent(AppConstants.DirectoryNames.logs, isDirectory: true)
    }
}

extension AppPaths {
    static func resourceDirectory(for type: String, gameName: String) -> URL? {
        switch type.lowercased() {
        case "mod": modsDirectory(gameName: gameName)
        case "datapack": datapacksDirectory(gameName: gameName)
        case "shader": shaderpacksDirectory(gameName: gameName)
        case "resourcepack": resourcepacksDirectory(gameName: gameName)
        default: nil
        }
    }
    /// Global cache file path - use the system standard cache directory, fall back to the Cache in the application support directory in case of exceptions
    static var appCache: URL {
        if let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return cachesDirectory.appendingPathComponent(Bundle.main.identifier)
        }
        
        Logger.shared.error("Unable to obtain the system cache directory, use the Cache in the application support directory")
        return launcherSupportDirectory.appendingPathComponent("Cache", isDirectory: true)
    }

    /// Data directory path
    static var dataDirectory: URL {
        cachedURL(key: "dataDirectory") {
            launcherSupportDirectory.appendingPathComponent(AppConstants.DirectoryNames.data, isDirectory: true)
        }
    }

    /// Game version database path
    static var gameVersionDatabase: URL {
        dataDirectory.appendingPathComponent("data.db")
    }
}
