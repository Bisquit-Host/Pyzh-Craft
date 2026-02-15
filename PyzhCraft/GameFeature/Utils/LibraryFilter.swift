import Foundation

/// Unified library filtering tool class
/// Unify download and classpath built library filtering logic
enum LibraryFilter {

    /// Determine whether the library is allowed (based on platform rules)
    /// - Parameters:
    ///   - library: library to check
    ///   - minecraftVersion: Minecraft version number (optional)
    /// - Returns: Is it allowed?
    static func isLibraryAllowed(_ library: Library, minecraftVersion: String? = nil) -> Bool {
        // Check system rules (no rules or empty rules are allowed by default)
        guard let rules = library.rules, !rules.isEmpty else { return true }
        return MacRuleEvaluator.isAllowed(rules, minecraftVersion: minecraftVersion)
    }

    /// Determine whether the library should be downloaded
    /// - Parameters:
    ///   - library: library to check
    ///   - minecraftVersion: Minecraft version number (optional)
    /// - Returns: Should it be downloaded?
    static func shouldDownloadLibrary(_ library: Library, minecraftVersion: String? = nil) -> Bool {
        guard library.downloadable else { return false }
        return isLibraryAllowed(library, minecraftVersion: minecraftVersion)
    }

    /// Determine whether the library should be included in the classpath
    /// - Parameters:
    ///   - library: library to check
    ///   - minecraftVersion: Minecraft version number (optional)
    /// - Returns: whether it should be included in the classpath
    static func shouldIncludeInClasspath(_ library: Library, minecraftVersion: String? = nil) -> Bool {
        guard library.downloadable == true && library.includeInClasspath == true else {
            return false
        }
        return isLibraryAllowed(library, minecraftVersion: minecraftVersion)
    }
}
