import Foundation

/// Launcher instance resolver protocol
/// Every launcher needs to implement this protocol to resolve its instance information
protocol LauncherInstanceParser {
    /// Launcher type
    var launcherType: ImportLauncherType { get }
    
    /// Verify that the instance is valid
    /// - Parameter instancePath: instance folder path
    /// - Returns: Whether it is a valid instance
    func isValidInstance(at instancePath: URL) -> Bool
    
    /// Parse instance information
    /// - Parameters:
    ///   - instancePath: instance folder path
    ///   - basePath: launcher base path
    /// - Returns: parsed instance information, if parsing fails, nil is returned
    func parseInstance(at instancePath: URL, basePath: URL) throws -> ImportInstanceInfo?
}

/// Launcher instance resolver factory
enum LauncherInstanceParserFactory {
    /// Create a corresponding parser based on the launcher type
    static func createParser(for launcherType: ImportLauncherType) -> LauncherInstanceParser {
        switch launcherType {
        case .multiMC, .prismLauncher: MultiMCInstanceParser(launcherType: launcherType)
        case .gdLauncher: GDLauncherInstanceParser()
        case .xmcl: XMCLInstanceParser()
        case .hmcl, .sjmcLauncher: SJMCLInstanceParser(launcherType: launcherType)
        }
    }
}
