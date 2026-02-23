import Foundation

/// Launcher file filter
/// Define file name rules that need to be filtered for each launcher (supports regular expressions)
enum LauncherFileFilter {

    /// Get the file filtering rules of the specified launcher
    /// - Parameter launcherType: launcher type
    /// - Returns: array of file name filtering rules (regular expression)
    static func getFilterPatterns(for launcherType: ImportLauncherType) -> [String] {
        switch launcherType {
        case .multiMC, .prismLauncher:
            return [
                // MultiMC/PrismLauncher specific files
                ".*\\.mmc-pack\\.json$",
                ".*instance\\.cfg$",
                ".*\\.log$",
                "^pack\\.meta$",
            ]

        case .gdLauncher:
            return [
                // GDLauncher specific files
                ".*config\\.json$",
                ".*\\.log$",
                "^metadata\\.json$",
            ]

        case .hmcl:
            return [
                // HMCL specific files
                ".*config\\.json$",
                ".*\\.log$",
                "^hmclversion\\.json$",
                "^hmclversion\\.cfg$",
                "^usercache\\.json$",
            ]

        case .sjmcLauncher:
            return [
                // SJMCL specific files
                ".*sjmclcfg\\.json$",
                ".*\\.log$",
                "^\\d+.*-.*\\.json$",
                "^\\d+.*-.*\\.jar$",
            ]

        case .xmcl:
            return [
                // XMCL specific files
                ".*instance\\.json$",
                ".*\\.log$",
                "^metadata\\.json$",
            ]
        }
    }

    /// Check if the file should be filtered
    /// - Parameters:
    ///   - fileName: file name (including relative path)
    ///   - launcherType: launcher type
    /// - Returns: true if the file should be filtered (not copied)
    static func shouldFilter(fileName: String, launcherType: ImportLauncherType) -> Bool {
        let patterns = getFilterPatterns(for: launcherType)

        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)

                if regex.firstMatch(in: fileName, options: [], range: range) != nil {
                    Logger.shared.debug("Filter file: \(fileName) (matching rule: \(pattern))")
                    return true
                }
            } catch {
                Logger.shared.warning("Invalid regular expression pattern: \(pattern), error: \(error.localizedDescription)")
            }
        }

        return false
    }

    /// Filter file list
    /// - Parameters:
    ///   - files: array of file URLs
    ///   - sourceDirectory: source directory (used to calculate relative paths)
    ///   - launcherType: launcher type
    /// - Returns: filtered file URL array
    static func filterFiles(
        _ files: [URL],
        sourceDirectory: URL,
        launcherType: ImportLauncherType
    ) -> [URL] {
        return files.filter { fileURL in
            // Calculate relative paths
            let relativePath = fileURL.path.replacingOccurrences(
                of: sourceDirectory.path + "/",
                with: ""
            )

            // Check if it should be filtered
            return !shouldFilter(fileName: relativePath, launcherType: launcherType)
        }
    }
}
