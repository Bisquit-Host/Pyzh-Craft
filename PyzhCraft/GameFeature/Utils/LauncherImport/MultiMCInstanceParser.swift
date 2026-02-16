import Foundation

/// MultiMC/PrismLauncher instance parser
struct MultiMCInstanceParser: LauncherInstanceParser {
    let launcherType: ImportLauncherType

    func isValidInstance(at instancePath: URL) -> Bool {
        let instanceCfgPath = instancePath.appendingPathComponent("instance.cfg")
        let mmcPackPath = instancePath.appendingPathComponent("mmc-pack.json")

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: instanceCfgPath.path),
              fileManager.fileExists(atPath: mmcPackPath.path) else {
            return false
        }

        // Verify file can be parsed
        do {
            _ = try parseInstanceCfg(at: instanceCfgPath)
            _ = try parseMMCPack(at: mmcPackPath)
            return true
        } catch {
            return false
        }
    }

    func parseInstance(at instancePath: URL, basePath: URL) throws -> ImportInstanceInfo? {
        let instanceCfgPath = instancePath.appendingPathComponent("instance.cfg")
        let mmcPackPath = instancePath.appendingPathComponent("mmc-pack.json")

        // Parse configuration file
        let instanceCfg = try parseInstanceCfg(at: instanceCfgPath)
        let mmcPack = try parseMMCPack(at: mmcPackPath)

        // Extract game version
        let gameVersion = extractGameVersion(from: mmcPack)

        // Extract Mod Loader Information
        let (modLoader, modLoaderVersion) = extractModLoader(from: mmcPack)

        // Extract game name
        let gameName = instanceCfg["name"] ?? instancePath.lastPathComponent

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

    /// Parse instance.cfg file (INI format)
    private func parseInstanceCfg(at path: URL) throws -> [String: String] {
        let content = try String(contentsOf: path, encoding: .utf8)
        var config: [String: String] = [:]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if let equalIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                config[key] = value
            }
        }

        return config
    }

    /// Parse mmc-pack.json file
    private func parseMMCPack(at path: URL) throws -> MMCPack {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(MMCPack.self, from: data)
    }

    /// Extract game version from mmc-pack.json
    private func extractGameVersion(from pack: MMCPack) -> String {
        for component in pack.components where component.uid == "net.minecraft" {
            return component.version
        }
        return ""
    }

    /// Extract Mod Loader information from mmc-pack.json
    private func extractModLoader(from pack: MMCPack) -> (loader: String, version: String) {
        for component in pack.components {
            switch component.uid {
            case "net.fabricmc.fabric-loader":
                return ("fabric", component.version)
            case "net.minecraftforge":
                return ("forge", component.version)
            case "net.neoforged":
                return ("neoforge", component.version)
            case "org.quiltmc.quilt-loader":
                return ("quilt", component.version)
            default:
                continue
            }
        }
        return ("vanilla", "")
    }
}

// MARK: - MMCPack Models

private struct MMCPack: Codable {
    let components: [MMCPackComponent]
}

private struct MMCPackComponent: Codable {
    let uid: String
    let version: String
}

// MARK: - Import Error

enum ImportError: LocalizedError {
    case gameDirectoryNotFound(instancePath: String)
    case invalidConfiguration(message: String)
    case fileNotFound(path: String)

    var errorDescription: String? {
        switch self {
        case .gameDirectoryNotFound(let path):
            return String(
                format: String(localized: "Game directory not found: \(path)")
            )
        case .invalidConfiguration(let message):
            return String(
                format: String(localized: "Invalid configuration: \(message)")
            )
        case .fileNotFound(let path):
            return String(
                format: String(localized: "File not found: \(path)"),
            )
        }
    }
}
