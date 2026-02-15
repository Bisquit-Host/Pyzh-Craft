import Foundation

/// XMCL instance parser
struct XMCLInstanceParser: LauncherInstanceParser {
    let launcherType: ImportLauncherType = .xmcl

    func isValidInstance(at instancePath: URL) -> Bool {
        let instanceJsonPath = instancePath.appendingPathComponent("instance.json")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: instanceJsonPath.path) else {
            return false
        }

        // Verify that the JSON file can be parsed
        do {
            _ = try parseInstanceJson(at: instanceJsonPath)
            return true
        } catch {
            return false
        }
    }

    func parseInstance(at instancePath: URL, basePath: URL) throws -> ImportInstanceInfo? {
        let instanceJsonPath = instancePath.appendingPathComponent("instance.json")
        let instance = try parseInstanceJson(at: instanceJsonPath)

        // Extract game version
        let gameVersion = instance.runtime.minecraft

        // Extract Mod Loader Information
        let (modLoader, modLoaderVersion) = extractModLoader(from: instance)

        // Extract game name
        let gameName = instance.name.isEmpty ? "XMCL-\(instancePath.lastPathComponent)" : instance.name

        return ImportInstanceInfo(
            gameName: gameName,
            gameVersion: gameVersion,
            modLoader: modLoader,
            modLoaderVersion: modLoaderVersion,
            gameIconPath: nil,
            iconDownloadUrl: nil,
            sourceGameDirectory: instancePath,
            launcherType: launcherType
        )
    }

    // MARK: - Private Methods

    /// Parse instance.json file
    private func parseInstanceJson(at path: URL) throws -> XMCLInstance {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(XMCLInstance.self, from: data)
    }

    /// Extract Mod Loader information
    private func extractModLoader(from instance: XMCLInstance) -> (loader: String, version: String) {
        let runtime = instance.runtime

        // Check by priority: Forge -> NeoForged -> Fabric -> Quilt -> Vanilla
        if !runtime.forge.isEmpty {
            return ("forge", runtime.forge)
        } else if !runtime.neoForged.isEmpty {
            return ("neoforge", runtime.neoForged)
        } else if !runtime.fabricLoader.isEmpty {
            return ("fabric", runtime.fabricLoader)
        } else if !runtime.quiltLoader.isEmpty {
            return ("quilt", runtime.quiltLoader)
        } else {
            return ("vanilla", "")
        }
    }
}

// MARK: - XMCL Models

private struct XMCLInstance: Codable {
    let name: String
    let url: String
    let icon: String
    let runtime: XMCLRuntime
    let java: String
    let version: String
    let server: XMCLServer?
    let author: String
    let description: String
    let lastAccessDate: Int64
    let creationDate: Int64
    let modpackVersion: String
    let fileApi: String
    let tags: [String]
    let lastPlayedDate: Int64
    let playtime: Int64
}

private struct XMCLRuntime: Codable {
    let minecraft: String
    let forge: String
    let liteloader: String
    let fabricLoader: String
    let yarn: String
    let optifine: String
    let quiltLoader: String
    let neoForged: String
    let labyMod: String
}

private struct XMCLServer: Codable {
    // Server information, add fields if needed
}
