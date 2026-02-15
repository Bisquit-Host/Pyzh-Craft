import Foundation

/// Placeholder instance parser
/// For starters that have not yet implemented parsing logic
struct PlaceholderInstanceParser: LauncherInstanceParser {
    let launcherType: ImportLauncherType

    func isValidInstance(at instancePath: URL) -> Bool {
        // Not implemented yet, returns false
        return false
    }

    func parseInstance(at instancePath: URL, basePath: URL) throws -> ImportInstanceInfo? {
        // Not implemented yet, throws an error
        throw LauncherImportError.parserNotImplemented(launcherType: launcherType.rawValue)
    }
}

/// Launcher import error
enum LauncherImportError: LocalizedError {
    case parserNotImplemented(launcherType: String)

    var errorDescription: String? {
        switch self {
        case .parserNotImplemented(let launcherType):
            return String(
                format: "launcher.import.error.parser_not_implemented".localized(),
                launcherType
            )
        }
    }
}
