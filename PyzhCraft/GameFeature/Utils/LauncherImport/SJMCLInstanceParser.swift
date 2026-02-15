import Foundation

/// HMCL and SJMCL use different JSON formats
struct SJMCLInstanceParser: LauncherInstanceParser {
    let launcherType: ImportLauncherType

    func isValidInstance(at instancePath: URL) -> Bool {
        let fileManager = FileManager.default

        // Use different validation logic based on launcher type
        if launcherType == .sjmcLauncher {
            // SJMCL: Check if sjmclcfg.json file exists
            let sjmclcfgPath = instancePath.appendingPathComponent("sjmclcfg.json")
            if fileManager.fileExists(atPath: sjmclcfgPath.path) {
                // Verify that the JSON file can be parsed
                do {
                    _ = try parseSJMCLInstanceJson(at: sjmclcfgPath)
                    return true
                } catch {
                    return false
                }
            }
            return false
        } else {
            // HMCL: Check if the instance folder contains foldername.json
            let fileManager = FileManager.default

            // The user selects the instance folder, check whether it contains folder name.json
            let folderName = instancePath.lastPathComponent
            let folderNameJsonPath = instancePath.appendingPathComponent("\(folderName).json")

            // Check if foldername.json file exists
            if fileManager.fileExists(atPath: folderNameJsonPath.path) {
                // Try to parse the JSON file to verify whether it is a valid version configuration file
                do {
                    let data = try Data(contentsOf: folderNameJsonPath)
                    // Try to parse to JSON, check if necessary fields are included (like id)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       json["id"] != nil {
                        return true
                    }
                } catch {
                    return false
                }
            }

            return false
        }
    }

    func parseInstance(at instancePath: URL, basePath: URL) throws -> ImportInstanceInfo? {
        // Use different parsing logic based on launcher type
        if launcherType == .sjmcLauncher {
            try parseSJMCLInstance(at: instancePath, basePath: basePath)
        } else {
            try parseHMCLInstance(at: instancePath, basePath: basePath)
        }
    }

    // MARK: - SJMCL Parsing

    /// Parse SJMCL instances
    private func parseSJMCLInstance(at instancePath: URL, basePath: URL) throws -> ImportInstanceInfo? {
        let fileManager = FileManager.default

        // Read the sjmclcfg.json file
        let sjmclcfgPath = instancePath.appendingPathComponent("sjmclcfg.json")
        guard fileManager.fileExists(atPath: sjmclcfgPath.path) else {
            return nil
        }

        let sjmclInstance = try parseSJMCLInstanceJson(at: sjmclcfgPath)

        // Extract information
        let gameName = sjmclInstance.name.isEmpty ? instancePath.lastPathComponent : sjmclInstance.name
        let gameVersion = sjmclInstance.version
        var modLoader = "vanilla"
        var modLoaderVersion = ""

        // Extract Mod Loader information
        if let modLoaderInfo = sjmclInstance.modLoader {
            let loaderType = modLoaderInfo.loaderType.lowercased()
            // Standardized loader type names
            switch loaderType {
            case "fabric":
                modLoader = "fabric"
            case "forge":
                modLoader = "forge"
            case "neoforge", "neoforged":
                modLoader = "neoforge"
            case "quilt":
                modLoader = "quilt"
            default:
                modLoader = "vanilla"
            }
            modLoaderVersion = modLoaderInfo.version
        }

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

    /// Parse SJMCL instance JSON file
    private func parseSJMCLInstanceJson(at path: URL) throws -> SJMCLInstance {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(SJMCLInstance.self, from: data)
    }

    // MARK: - HMCL Parsing

    /// Parse HMCL instances
    private func parseHMCLInstance(at instancePath: URL, basePath: URL) throws -> ImportInstanceInfo? {
        let fileManager = FileManager.default

        // Read information from foldername.json file
        let folderName = instancePath.lastPathComponent
        let folderNameJsonPath = instancePath.appendingPathComponent("\(folderName).json")

        guard fileManager.fileExists(atPath: folderNameJsonPath.path),
              let versionInfo = try? parseHMCLVersionJson(at: folderNameJsonPath) else {
            return nil
        }

        // Get information from version JSON file
        let gameName = versionInfo.id ?? instancePath.lastPathComponent
        let gameVersion = versionInfo.mcVersion ?? ""
        let modLoader = versionInfo.modLoader ?? "vanilla"
        let modLoaderVersion = versionInfo.modLoaderVersion ?? ""

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

    /// Parse HMCL version JSON file (folder name.json)
    private func parseHMCLVersionJson(at path: URL) throws -> HMCLVersionInfo? {
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let id = json["id"] as? String

        // Extract Mod Loader information from arguments.game
        var modLoader = "vanilla"
        var modLoaderVersion = ""
        var mcVersion = ""

        if let arguments = json["arguments"] as? [String: Any],
           let gameArgs = arguments["game"] as? [Any] {
            // Traverse the parameter array to find Mod Loader related information
            for (index, arg) in gameArgs.enumerated() {
                if let argString = arg as? String {
                    // Check Mod Loader Type
                    if argString == "--launchTarget" {
                        // The next parameter is the launch target
                        if index + 1 < gameArgs.count,
                           let launchTarget = gameArgs[index + 1] as? String {
                            switch launchTarget.lowercased() {
                            case "forgeclient", "forge":
                                modLoader = "forge"
                            case "fabricclient", "fabric":
                                modLoader = "fabric"
                            case "quiltclient", "quilt":
                                modLoader = "quilt"
                            case "neoforgeclient", "neoforge":
                                modLoader = "neoforge"
                            default:
                                break
                            }
                        }
                    }

                    // Check Forge version
                    if argString == "--fml.forgeVersion" {
                        if index + 1 < gameArgs.count,
                           let version = gameArgs[index + 1] as? String {
                            modLoaderVersion = version
                            if modLoader == "vanilla" {
                                modLoader = "forge"
                            }
                        }
                    }

                    // Check Minecraft version
                    if argString == "--fml.mcVersion" {
                        if index + 1 < gameArgs.count,
                           let version = gameArgs[index + 1] as? String {
                            mcVersion = version
                        }
                    }

                    // Check NeoForge version
                    if argString == "--fml.neoforgeVersion" {
                        if index + 1 < gameArgs.count,
                           let version = gameArgs[index + 1] as? String {
                            modLoaderVersion = version
                            modLoader = "neoforge"
                        }
                    }

                    // Check Fabric/Quilt version (usually in the --version parameter)
                    if argString == "--version" {
                        if index + 1 < gameArgs.count,
                           let version = gameArgs[index + 1] as? String {
                            // The Fabric/Quilt version format is usually "fabric-loader-0.14.0-1.20.1"
                            if version.contains("fabric") {
                                modLoader = "fabric"
                                let components = version.components(separatedBy: "-")
                                if components.count >= 3 {
                                    modLoaderVersion = components[2] // Extract loader version
                                    if mcVersion.isEmpty && components.count >= 4 {
                                        mcVersion = components[3] // Extract MC version
                                    }
                                }
                            } else if version.contains("quilt") {
                                modLoader = "quilt"
                                let components = version.components(separatedBy: "-")
                                if components.count >= 3 {
                                    modLoaderVersion = components[2]
                                    if mcVersion.isEmpty && components.count >= 4 {
                                        mcVersion = components[3]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return HMCLVersionInfo(
            id: id,
            mcVersion: mcVersion.isEmpty ? nil : mcVersion,
            modLoader: modLoader == "vanilla" ? nil : modLoader,
            modLoaderVersion: modLoaderVersion.isEmpty ? nil : modLoaderVersion
        )
    }

    /// Parse HMCL config.json file
    private func parseHMCLConfigJson(at path: URL) throws -> HMCLConfig? {
        let data = try Data(contentsOf: path)
        return try? JSONDecoder().decode(HMCLConfig.self, from: data)
    }

    // MARK: - Common Methods

    /// Extract version information from game directory
    private func extractVersionFromGameDirectory(_ gameDirectory: URL) throws -> String? {
        // Try reading from version file
        let versionFile = gameDirectory.appendingPathComponent("version.json")
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: versionFile.path) {
            if let data = try? Data(contentsOf: versionFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["id"] as? String {
                return version
            }
        }

        return nil
    }
}

// MARK: - SJMCL Models
// swiftlint:disable discouraged_optional_boolean

private struct SJMCLInstance: Codable {
    let id: String
    let name: String
    let description: String?
    let iconSrc: String
    let starred: Bool?
    let playTime: Int64?
    let version: String
    let versionPath: String?
    let modLoader: SJMCLModLoader?
    let useSpecGameConfig: Bool?
    let specGameConfig: SJMCLSpecGameConfig?
}

// swiftlint:enable discouraged_optional_boolean

private struct SJMCLModLoader: Codable {
    let status: String
    let loaderType: String
    let version: String
    let branch: String?
}

private struct SJMCLSpecGameConfig: Codable {
    // Fields can be added
}

// MARK: - HMCL Models

private struct HMCLConfig: Codable {
    let name: String?
    let gameVersion: String?
    let modLoader: String?
    let modLoaderVersion: String?
}

private struct HMCLVersionInfo {
    let id: String?
    let mcVersion: String?
    let modLoader: String?
    let modLoaderVersion: String?
}
