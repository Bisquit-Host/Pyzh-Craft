import Foundation

/// Mapper of Modrinth taxonomy to CurseForge taxonomy IDs
enum ModrinthToCurseForgeCategoryMapper {
    /// Map Modrinth category names to CurseForge category IDs
    /// - Parameter modrinthCategoryName: Modrinth category name
    /// - Parameter projectType: project type (mod, modpack, resourcepack, shader, datapack)
    /// - Returns: CurseForge classification ID, or nil if no mapping is found
    static func mapToCurseForgeCategoryId(
        modrinthCategoryName: String,
        projectType: String
    ) -> Int? {
        let key = modrinthCategoryName.lowercased()
        // Select mapping table based on project type
        switch projectType.lowercased() {
        case "mod", "modpack":
            return modCategoryMap[key]
        case "resourcepack":
            return resourcepackCategoryMap[key]
        case "shader":
            return shaderCategoryMap[key]
        case "datapack":
            // Data Pack: Use Modrinth’s mod classification key, mapped to CurseForge Data Packs (classId=6945)
            return datapackCategoryMap[key]
        default:
            return nil
        }
    }

    /// Map multiple Modrinth taxonomy names to a list of CurseForge taxonomy IDs
    /// - Parameters:
    ///   - modrinthCategoryNames: Modrinth category name list
    ///   - projectType: project type
    /// - Returns: CurseForge category ID list (up to 10, subject to API restrictions)
    static func mapToCurseForgeCategoryIds(
        modrinthCategoryNames: [String],
        projectType: String
    ) -> [Int] {
        let mappedIds = modrinthCategoryNames.compactMap { name in
            mapToCurseForgeCategoryId(modrinthCategoryName: name, projectType: projectType)
        }
        // API limit: Maximum 10 category IDs
        return Array(mappedIds.prefix(10))
    }

    // MARK: - Mod classification mapping table
    /// Mapping of Modrinth mod/modpack categories to CurseForge category IDs
    /// Mainly based on: automatic results of `gen_category_mapping.py` + approximate classification manually supplemented
    private static let modCategoryMap: [String: Int] = [
        // Adventure -> Adventure and RPG
        "adventure": 422,
        // Weird/Prank category, classified as Miscellaneous
        "cursed": 425,           // Miscellaneous
        // Decoration -> Cosmetic
        "decoration": 424,
        // Economic category, no direct Mod classification, temporarily classified as miscellaneous
        "economy": 425,          // Miscellaneous
        // Equipment -> Armor, Tools, and Weapons
        "equipment": 434,
        // Food -> Food
        "food": 436,
        // Game mechanics, classified as Miscellaneous
        "game-mechanics": 425,   // Miscellaneous
        // Library / API Class -> API and Library
        "library": 421,
        // Magic -> Magic
        "magic": 419,
        // Management -> Server Utility
        "management": 435,
        // Mini Games -> Miscellaneous
        "minigame": 425,         // Miscellaneous
        // Biology -> Mobs
        "mobs": 411,
        // Optimization class -> Performance
        "optimization": 6814,
        // Social -> Utility & QoL
        "social": 5191,          // Utility & QoL
        // Storage class -> Storage
        "storage": 420,
        // Technology -> Technology
        "technology": 412,
        // Transportation -> Player Transport
        "transportation": 414,
        // Tools/Server Utility -> Server Utility
        "utility": 435,
        // World Generation -> World Gen
        "worldgen": 406,
    ]

    // MARK: - Resourcepack classification mapping table
    /// Mapping of Modrinth resourcepack categories to CurseForge category IDs
    /// Mainly based on: automatic results of `gen_category_mapping.py` + approximate classification manually supplemented
    private static let resourcepackCategoryMap: [String: Int] = [
        // Resolution (Resolution) maps to the corresponding resolution classification of Texture Packs
        "128x": 396,             // 128x -> 128x
        "16x": 393,              // 16x  -> 16x
        "256x": 397,             // 256x -> 256x
        "32x": 394,              // 32x  -> 32x
        "64x": 395,              // 64x  -> 64x
        // Other resolutions, approximate classification
        "48x": 395,              // Close to 64x
        "512x+": 398,            // -> 512x and Higher
        "8x-": 393,              // Low resolution, down to 16x
        // style class
        "realistic": 400,        // Realistic -> Photo Realistic
        "simplistic": 403,       // -> Traditional
        "themed": 399,           // -> Steampunk (Theme Pack)
        "vanilla-like": 403,     // -> Traditional (close to the original style)
        // Function/content related, unified into Miscellaneous or closer type
        "audio": 405,            // Sound effects, temporarily returned to Miscellaneous
        "blocks": 405,
        "combat": 405,
        "core-shaders": 404,     // Related to rendering, belongs to Animated
        "cursed": 405,
        "decoration": 405,
        "entities": 405,
        "environment": 405,
        "equipment": 405,
        "gui": 401,              // Interface related, similar to Modern
        "items": 405,
        "locale": 405,
        "models": 405,
        "tweaks": 405,
        "utility": 405,
        // special:
        "fonts": 5244,           // -> Font Packs
        "modded": 4465,          // -> Mod Support
    ]

    // MARK: - Shader classification mapping table
    /// Mapping of Modrinth shader categories to CurseForge category IDs
    /// Main basis: automatic results of `gen_category_mapping.py` + approximate classification manually supplemented (CF side only has three categories: Fantasy / Realistic / Vanilla)
    private static let shaderCategoryMap: [String: Int] = [
        // Style/Quality (auto-mapping)
        "fantasy": 6554,         // Fantasy
        "realistic": 6553,       // Realistic
        "semi-realistic": 6553,  // Semi-realistic -> Realistic
        "vanilla-like": 6555,    // Vanilla-like -> Vanilla
        // The remaining tags are roughly classified according to style/performance
        "atmosphere": 6553,
        "bloom": 6553,
        "cartoon": 6554,
        "colored-lighting": 6553,
        "cursed": 6554,
        "foliage": 6553,
        "high": 6553,
        "low": 6555,
        "medium": 6555,
        "path-tracing": 6553,
        "pbr": 6553,
        "potato": 6555,
        "reflections": 6553,
        "screenshot": 6553,
        "shadows": 6553,
    ]

    // MARK: - Datapack classification mapping table
    /// Modrinth datapack uses the same set of classification keys as mod (adventure/magic/technology/...),
    /// Map key to CurseForge Data Packs (classId=6945) classification ID
    /// Refer to the classification under classId=6945 in `cf.json`:
    /// - 6948 Adventure
    /// - 6949 Fantasy
    /// - 6950 Library
    /// - 6952 Magic
    /// - 6947 Miscellaneous
    /// - 6946 Mod Support
    /// - 6951 Tech
    /// - 6953 Utility
    private static let datapackCategoryMap: [String: Int] = [
        // Directly corresponding categories (one-to-one correspondence with the official categories of Data Packs)
        "adventure": 6948,        // Adventure
        "library": 6950,          // Library
        "magic": 6952,            // Magic
        "technology": 6951,       // Tech
        "utility": 6953,          // Utility

        // Mappings with similar semantics (try to avoid all being classified as miscellaneous)
        "worldgen": 6948,         // World generation, mostly adventure/exploration oriented -> Adventure
        "mobs": 6948,             // Creature related events/spawns -> Adventure
        "optimization": 6953,     // Performance rules -> Utility
        "storage": 6951,          // Storage/Tech System Rules -> Tech
        "management": 6953,       // Management/Automation -> Utility
        "economy": 6953,          // Economic/Currency Rules -> Utility
        "transportation": 6951,   // Traffic/Conveyance Rules -> Tech

        // The rest are temporarily classified as Miscellaneous (can be subdivided as needed in the future)
        "cursed": 6947,
        "decoration": 6947,
        "equipment": 6947,
        "food": 6947,
        "game-mechanics": 6947,
        "minigame": 6947,
        "social": 6947,
    ]

    /// Get categories from CurseForge API and update mapping table (optional)
    /// This method can dynamically obtain classifications at runtime to improve mapping
    static func updateCategoryMapFromAPI() async {
        // NOTE: Reserved for implementation, get classification from CurseForge API and update mapping table
        // The current version uses static mapping tables to avoid adding additional dependencies at runtime
    }
}
