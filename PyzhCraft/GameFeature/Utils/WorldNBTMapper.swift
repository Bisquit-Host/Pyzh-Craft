import Foundation

/// Generic NBT parsing tool related to Minecraft world saves (level.dat / world_gen_settings.dat etc.)
enum WorldNBTMapper {
    // MARK: - Basic numerical/boolean reading

    /// Try to uniformly convert any NBT numerical type to Int64, compatible with Int/Int8/Int16/Int32/UInt, etc
    static func readInt64(_ any: Any?) -> Int64? {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? Int32 { return Int64(v) }
        if let v = any as? Int16 { return Int64(v) }
        if let v = any as? Int8 { return Int64(v) }
        if let v = any as? UInt64 { return Int64(v) }
        if let v = any as? UInt32 { return Int64(v) }
        if let v = any as? UInt16 { return Int64(v) }
        if let v = any as? UInt8 { return Int64(v) }
        return nil
    }

    /// Convert the numeric value or Boolean in NBT to Bool (non-0 means true), and return false if it cannot be parsed
    static func readBoolFlag(_ any: Any?) -> Bool {
        guard let any else { return false }
        if let b = any as? Bool { return b }
        if let v = readInt64(any) { return v != 0 }
        return false
    }

    // MARK: - Game Mode / Difficulty

    static func mapGameMode(_ value: Int) -> String {
        switch value {
        case 0: String(localized: "Survival")
        case 1: String(localized: "Creative")
        case 2: String(localized: "Adventure")
        case 3: String(localized: "Spectator")
        default: String(localized: "Unknown")
        }
    }

    static func mapDifficulty(_ value: Int) -> String {
        switch value {
        case 0: String(localized: "Peaceful")
        case 1: String(localized: "Easy")
        case 2: String(localized: "Normal")
        case 3: String(localized: "Hard")
        default: String(localized: "Unknown")
        }
    }

    /// Map new difficulty_settings.difficulty (string) to localized text
    static func mapDifficultyString(_ value: String) -> String {
        switch value.lowercased() {
        case "peaceful": String(localized: "Peaceful")
        case "easy": String(localized: "Easy")
        case "normal": String(localized: "Normal")
        case "hard": String(localized: "Hard")
        default: String(localized: "Unknown")
        }
    }

    // MARK: - seed reading

    /// Parse the seed from the Data tag of level.dat and the optional world path
    /// - Prioritize RandomSeed
    /// - Then WorldGenSettings/worldGenSettings.seed
    /// - Finally (if there is a worldPath) try data/minecraft/world_gen_settings.dat -> data.seed
    static func readSeed(from dataTag: [String: Any], worldPath: URL?) -> Int64? {
        // Old version: read from RandomSeed first
        if let seed = readInt64(dataTag["RandomSeed"]) {
            return seed
        }

        // Then: WorldGenSettings / worldGenSettings.seed in level.dat
        if let worldGenSettings = dataTag["WorldGenSettings"] as? [String: Any],
           let seed = readInt64(worldGenSettings["seed"]) {
            return seed
        }
        if let worldGenSettings = dataTag["worldGenSettings"] as? [String: Any],
           let seed = readInt64(worldGenSettings["seed"]) {
            return seed
        }

        // New version: world_gen_settings.dat
        guard let worldPath else { return nil }
        return readSeedFromWorldGenSettings(worldPath: worldPath)
    }

    /// Read the seed from world_gen_settings.dat in the 26+ new version archive (path: data/minecraft/world_gen_settings.dat)
    private static func readSeedFromWorldGenSettings(worldPath: URL) -> Int64? {
        let fm = FileManager.default
        let wgsPath = worldPath
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("minecraft", isDirectory: true)
            .appendingPathComponent("world_gen_settings.dat")
        guard fm.fileExists(atPath: wgsPath.path) else { return nil }
        do {
            let raw = try Data(contentsOf: wgsPath)
            let parser = NBTParser(data: raw)
            let nbt = try parser.parse()
            // New version file structure: root = { DataVersion: ..., data: { seed: ... } }
            if let dataTag = nbt["data"] as? [String: Any],
               let seed = readInt64(dataTag["seed"]) {
                return seed
            }
            return nil
        } catch {
            Logger.shared.error("读取 world_gen_settings.dat 失败: \(error.localizedDescription)")
            return nil
        }
    }
}
