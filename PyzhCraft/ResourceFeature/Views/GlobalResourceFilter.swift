import Foundation

// MARK: - Compatible game filtering (follow the complete process: filtering for compatibility -> query version information -> check whether hash is installed)
func filterCompatibleGames(
    detail: ModrinthProjectDetail,
    gameRepository: GameRepository,
    resourceType: String,
    projectId: String
) async -> [GameVersionInfo] {
    let supportedVersions = Set(detail.gameVersions)
    let supportedLoaders = Set(detail.loaders.map { $0.lowercased() })
    let resourceTypeLowercased = resourceType.lowercased()

    // Step 1: Filter out compatible game versions based on resource compatible versions and local game lists
    let compatibleGames = gameRepository.games.compactMap { game -> GameVersionInfo? in
        let localLoader = game.modLoader.lowercased()
        
        let match: Bool = {
            switch (resourceTypeLowercased, localLoader) {
            case ("datapack", "vanilla"):
                return supportedVersions.contains(game.gameVersion)
                    && supportedLoaders.contains("datapack")
            case ("shader", let loader) where loader != "vanilla":
                return supportedVersions.contains(game.gameVersion)
            case ("resourcepack", "vanilla"):
                return supportedVersions.contains(game.gameVersion)
                    && supportedLoaders.contains("minecraft")
            case ("resourcepack", _):
                return supportedVersions.contains(game.gameVersion)
            default:
                return supportedVersions.contains(game.gameVersion)
                    && supportedLoaders.contains(localLoader)
            }
        }()
        
        return match ? game : nil
    }

    // For mods, you need to check if hash is installed
    guard resourceTypeLowercased == "mod" else {
        // For other resource types, it does not check whether it is installed yet and returns all compatible games
        return compatibleGames
    }

    // Step 2 and Step 3: Use the version information and resource information of the compatible game list to query the version information of the resource and determine whether the hash of each version is installed
    return await withTaskGroup(of: GameVersionInfo?.self) { group in
        for game in compatibleGames {
            group.addTask {
                // Use the version information and resource information of the compatible game list to query the version information of the resource
                guard let versions = try? await ModrinthService.fetchProjectVersionsFilter(
                    id: projectId,
                    selectedVersions: [game.gameVersion],
                    selectedLoaders: [game.modLoader],
                    type: resourceType
                ), let firstVersion = versions.first else {
                    // If version information cannot be obtained, return to the game (think it is not installed)
                    return game
                }

                // Get the hash of the main file
                guard let primaryFile = ModrinthService.filterPrimaryFiles(from: firstVersion.files) else {
                    // If there is no main file, return to the game (assumed not installed)
                    return game
                }

                // Determine whether this version of hash is installed
                let modsDir = AppPaths.modsDirectory(gameName: game.gameName)
                let resourceHash = primaryFile.hashes.sha1
                if ModScanner.shared.isModInstalledSync(hash: resourceHash, in: modsDir) {
                    // Installed, do not return
                    return nil
                }

                // Not installed, return to this game
                return game
            }
        }

        var results: [GameVersionInfo] = []
        
        for await game in group {
            if let game = game {
                results.append(game)
            }
        }
        
        return results
    }
}
