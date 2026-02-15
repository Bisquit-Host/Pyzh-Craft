protocol ModLoaderHandler {
    /// Set the specified version of the loader (throws exception version)
    /// - Parameters:
    ///   - gameVersion: game version
    ///   - loaderVersion: specified loader version
    ///   - gameInfo: game information
    ///   - onProgressUpdate: progress update callback
    /// - Returns: Set results
    /// - Throws: GlobalError when the operation fails
    static func setupWithSpecificVersionThrowing(
        for gameVersion: String,
        loaderVersion: String,
        gameInfo: GameVersionInfo,
        onProgressUpdate: @escaping (String, Int, Int) -> Void
    ) async throws -> (loaderVersion: String, classpath: String, mainClass: String)

    /// Set the specified version of the loader (silent version)
    /// - Parameters:
    ///   - gameVersion: game version
    ///   - loaderVersion: specified loader version
    ///   - gameInfo: game information
    ///   - onProgressUpdate: progress update callback
    /// - Returns: Set the result, return nil on failure
    static func setupWithSpecificVersion(
        for gameVersion: String,
        loaderVersion: String,
        gameInfo: GameVersionInfo,
        onProgressUpdate: @escaping (String, Int, Int) -> Void
    ) async -> (loaderVersion: String, classpath: String, mainClass: String)?
}
