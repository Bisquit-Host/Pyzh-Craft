import Foundation

/// Configuration file duplicator
/// Responsible for copying game configuration files to the overrides directory (excludes archive directories and resource directories)
enum ConfigFileCopier {

    /// Directories that need to be excluded (these are already processed elsewhere or should not be copied)
    private static let excludedDirectories: Set<String> = [
        AppConstants.DirectoryNames.mods,
        AppConstants.DirectoryNames.datapacks,
        AppConstants.DirectoryNames.resourcepacks,
        AppConstants.DirectoryNames.shaderpacks,
        AppConstants.DirectoryNames.saves,
        AppConstants.DirectoryNames.crashReports,
        AppConstants.DirectoryNames.logs,
    ]

    /// Count the number of configuration files that need to be copied
    /// - Parameter gameInfo: game information
    /// - Returns: total number of files
    static func countFiles(gameInfo: GameVersionInfo) throws -> Int {
        let profileDir = AppPaths.profileDirectory(gameName: gameInfo.gameName)
        var count = 0

        // Get all directories and files
        let contents = try FileManager.default.contentsOfDirectory(
            at: profileDir,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let isRegularFile = resourceValues?.isRegularFile ?? false

            if isDirectory {
                let dirName = item.lastPathComponent
                // Exclude unnecessary directories
                if excludedDirectories.contains(dirName) {
                    continue
                }
                // Files in the recursive statistics directory
                let enumerator = FileManager.default.enumerator(
                    at: item,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                while let fileURL = enumerator?.nextObject() as? URL {
                    if let isRegularFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                       isRegularFile {
                        count += 1
                    }
                }
            } else if isRegularFile {
                // Statistics of configuration files in the root directory
                count += 1
            }
        }

        return count
    }

    /// Copy the configuration file to the overrides directory
    /// - Parameters:
    ///   - gameInfo: game information
    ///   - overridesDir: overrides directory
    ///   - progressCallback: progress callback (number of copied files, current file name)
    static func copyFiles(
        gameInfo: GameVersionInfo,
        to overridesDir: URL,
        progressCallback: ((Int, String) -> Void)? = nil
    ) async throws {
        let profileDir = AppPaths.profileDirectory(gameName: gameInfo.gameName)
        var filesCopied = 0

        // Get all directories and files
        let contents = try FileManager.default.contentsOfDirectory(
            at: profileDir,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let isRegularFile = resourceValues?.isRegularFile ?? false

            if isDirectory {
                let dirName = item.lastPathComponent
                // Exclude unnecessary directories
                if excludedDirectories.contains(dirName) {
                    continue
                }

                // copy entire directory
                let destDir = overridesDir.appendingPathComponent(dirName)
                try? FileManager.default.removeItem(at: destDir)

                // Recursively copy all files in a directory
                let enumerator = FileManager.default.enumerator(
                    at: item,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                while let fileURL = enumerator?.nextObject() as? URL {
                    if let isRegularFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                       isRegularFile {
                        let relativePath = fileURL.path.replacingOccurrences(of: item.path + "/", with: "")
                        let destFile = destDir.appendingPathComponent(relativePath)
                        let destParent = destFile.deletingLastPathComponent()
                        try FileManager.default.createDirectory(at: destParent, withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: fileURL, to: destFile)
                        filesCopied += 1
                        progressCallback?(filesCopied, fileURL.lastPathComponent)
                    }
                }
            } else if isRegularFile {
                // Copy the configuration file in the root directory
                let destFile = overridesDir.appendingPathComponent(item.lastPathComponent)
                try? FileManager.default.removeItem(at: destFile)
                try FileManager.default.copyItem(at: item, to: destFile)
                filesCopied += 1
                progressCallback?(filesCopied, item.lastPathComponent)
            }
        }
    }
}
