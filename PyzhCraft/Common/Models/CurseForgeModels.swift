import Foundation

struct CurseForgeSearchResult: Codable {
    let data: [CurseForgeMod]
    let pagination: CurseForgePagination?
}

struct CurseForgePagination: Codable {
    let index: Int
    let pageSize: Int
    let resultCount: Int
    let totalCount: Int
}

struct CurseForgeMod: Codable {
    let id: Int
    let name: String
    let summary: String
    let slug: String?
    let authors: [CurseForgeAuthor]?
    let logo: CurseForgeLogo?
    let downloadCount: Int?
    let gamePopularityRank: Int?
    let links: CurseForgeLinks?
    let dateCreated: String?
    let dateModified: String?
    let dateReleased: String?
    let gameId: Int?
    let classId: Int?
    let categories: [CurseForgeCategory]?
    let latestFiles: [CurseForgeModFileDetail]?
    let latestFilesIndexes: [CurseForgeFileIndex]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, summary, slug, authors, logo
        case downloadCount, gamePopularityRank, links, dateCreated, dateModified, dateReleased, gameId, classId, categories, latestFiles, latestFilesIndexes
    }
}

struct CurseForgeLogo: Codable {
    let id: Int?
    let modId: Int?
    let title: String?
    let description: String?
    let thumbnailUrl: String?
    let url: String?
}

struct CurseForgeLinks: Codable {
    let websiteUrl: String?
    let wikiUrl: String?
    let issuesUrl: String?
    let sourceUrl: String?
}

struct CurseForgeModDetail: Codable {
    let id: Int
    let name: String
    let summary: String
    let classId: Int
    let categories: [CurseForgeCategory]
    let slug: String?
    let authors: [CurseForgeAuthor]?
    let logo: CurseForgeLogo?
    let downloadCount: Int?
    let gamePopularityRank: Int?
    let links: CurseForgeLinks?
    let dateCreated: String?
    let dateModified: String?
    let dateReleased: String?
    let gameId: Int?
    let latestFiles: [CurseForgeModFileDetail]?
    let latestFilesIndexes: [CurseForgeFileIndex]?
    let body: String?
    
    /// Get the corresponding content type enumeration
    var contentType: CurseForgeClassId? {
        CurseForgeClassId(rawValue: classId)
    }
    
    /// Get directory name
    var directoryName: String {
        contentType?.directoryName ?? AppConstants.DirectoryNames.mods
    }
    
    /// Convert to Modrinth item type string
    var projectType: String {
        switch contentType {
        case .mods:
            return "mod"
        case .resourcePacks:
            return "resourcepack"
        case .shaders:
            return "shader"
        case .datapacks:
            return "datapack"
        default:
            return "mod"
        }
    }
}

struct CurseForgeFileIndex: Codable {
    let gameVersion: String
    let fileId: Int
    let filename: String
    let releaseType: Int
    let gameVersionTypeId: Int?
    let modLoader: Int?
}

/// CurseForge content type enum
enum CurseForgeClassId: Int, CaseIterable {
    case mods = 6           // module
    case resourcePacks = 12 // Resource pack
    case shaders = 6552     // light and shadow
    case datapacks = 6945   // packet
    
    var directoryName: String {
        switch self {
        case .mods:
            return AppConstants.DirectoryNames.mods
        case .resourcePacks:
            return AppConstants.DirectoryNames.resourcepacks
        case .shaders:
            return AppConstants.DirectoryNames.shaderpacks
        case .datapacks:
            return AppConstants.DirectoryNames.datapacks
        }
    }
}

/// CurseForge ModLoaderType enumeration
enum CurseForgeModLoaderType: Int, CaseIterable {
    case forge = 1
    case fabric = 4
    case quilt = 5
    case neoforge = 6
    
    /// Get the corresponding enumeration value based on the string
    /// - Parameter loaderName: loader name string
    /// - Returns: corresponding enumeration value, if there is no match, return nil
    static func from(_ loaderName: String) -> Self? {
        switch loaderName.lowercased() {
        case "forge":
            return .forge
        case "fabric":
            return .fabric
        case "quilt":
            return .quilt
        case "neoforge":
            return .neoforge
        default:
            return nil
        }
    }
}

struct CurseForgeCategory: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let url: String?
    let avatarUrl: String?
    let parentCategoryId: Int?
    let rootCategoryId: Int?
    let gameId: Int?
    let gameName: String?
    let classId: Int?
    let dateModified: String?
}

/// CurseForge category list response
struct CurseForgeCategoriesResponse: Codable {
    let data: [CurseForgeCategory]
}

/// CurseForge game version
struct CurseForgeGameVersion: Codable, Identifiable, Hashable {
    let id: Int
    let gameVersionId: Int?
    let versionString: String
    let jarDownloadUrl: String?
    let jsonDownloadUrl: String?
    let approved: Bool
    let dateModified: String?
    let gameVersionTypeId: Int?
    let gameVersionStatus: Int?
    let gameVersionTypeStatus: Int?
    
    var identifier: String { versionString }
    
    var version_type: String {
        // CurseForge does not have a clear version type, it is inferred based on the version number
        if versionString.contains("snapshot") || versionString.contains("pre") || versionString.contains("rc") {
            return "snapshot"
        }
        return "release"
    }
}

/// CurseForge game version list response
struct CurseForgeGameVersionsResponse: Codable {
    let data: [CurseForgeGameVersion]
}

struct CurseForgeModDetailResponse: Codable {
    let data: CurseForgeModDetail
}

struct CurseForgeModDescriptionResponse: Codable {
    let data: String
}

struct CurseForgeFilesResult: Codable {
    let data: [CurseForgeModFileDetail]
}

struct CurseForgeModFileDetail: Codable {
    let id: Int
    let displayName: String
    let fileName: String
    let downloadUrl: String?
    let fileDate: String
    let releaseType: Int
    let gameVersions: [String]
    let dependencies: [CurseForgeDependency]?
    let changelog: String?
    let fileLength: Int?
    let hash: CurseForgeHash?
    let hashes: [CurseForgeHash]?
    let modules: [CurseForgeModule]?
    let projectId: Int?
    let projectName: String?
    let authors: [CurseForgeAuthor]?
    
    /// Extract hash (SHA1) with algo = 1 from hashes array
    var sha1Hash: CurseForgeHash? {
        if let hashes = hashes {
            return hashes.first { $0.algo == 1 }
        }
        return hash
    }
}

struct CurseForgeDependency: Codable {
    let modId: Int
    let relationType: Int
}

struct CurseForgeHash: Codable {
    let value: String
    let algo: Int
}

struct CurseForgeModule: Codable {
    let name: String
    let fingerprint: Int
}

struct CurseForgeAuthor: Codable {
    let name: String
    let url: String?
}

// MARK: - CurseForge Manifest Models

/// Manifest.json format of CurseForge integration package
struct CurseForgeManifest: Codable {
    let minecraft: CurseForgeMinecraft
    let manifestType: String
    let manifestVersion: Int
    let name: String
    let version: String?  // Modified to optional as some modpacks may lack this field
    let author: String?
    let files: [CurseForgeManifestFile]
    let overrides: String?
    
    enum CodingKeys: String, CodingKey {
        case minecraft, manifestType, manifestVersion, name, version, author, files, overrides
    }
}

/// Minecraft configuration in CurseForge manifest
struct CurseForgeMinecraft: Codable {
    let version: String
    let modLoaders: [CurseForgeModLoader]
}

/// Mod loader configuration in CurseForge manifest
struct CurseForgeModLoader: Codable {
    let id: String
    let primary: Bool
}

/// File information in CurseForge manifest
struct CurseForgeManifestFile: Codable {
    let projectID: Int
    let fileID: Int
    let required: Bool
    
    enum CodingKeys: String, CodingKey {
        case projectID, fileID, required
    }
}

/// CurseForge integrated package index information (converted format)
struct CurseForgeIndexInfo {
    let gameVersion: String
    let loaderType: String
    let loaderVersion: String
    let modPackName: String
    let modPackVersion: String
    let author: String?
    let files: [CurseForgeManifestFile]
    let overridesPath: String?
}
