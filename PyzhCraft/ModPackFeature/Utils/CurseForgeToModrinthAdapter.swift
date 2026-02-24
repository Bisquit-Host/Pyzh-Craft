import Foundation

enum CurseForgeToModrinthAdapter {
    /// Convert CurseForge project details to Modrinth format
    /// - Parameters:
    ///   - cf: CurseForge project details
    ///   - description: HTML description content obtained from the description interface (optional, if provided, it will be used first)
    /// - Returns: Project details in Modrinth format
    static func convert(_ cf: CurseForgeModDetail, description: String = "") -> ModrinthProjectDetail? {
        // date parser
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // parse date
        var publishedDate = Date()
        var updatedDate = Date()
        if let dateCreated = cf.dateCreated {
            publishedDate = dateFormatter.date(from: dateCreated) ?? Date()
        }
        if let dateModified = cf.dateModified {
            updatedDate = dateFormatter.date(from: dateModified) ?? Date()
        }
        
        // Extract game version (from latestFilesIndexes)
        var gameVersions: [String] = []
        var allVersionsFromIndexes: [String] = []
        if let indexes = cf.latestFilesIndexes {
            allVersionsFromIndexes = Array(Set(indexes.map { $0.gameVersion }))
            gameVersions = CommonUtil.sortMinecraftVersions(allVersionsFromIndexes)
        }
        
        // Extract loader (from latestFilesIndexes)
        var loaders: [String] = []
        if let indexes = cf.latestFilesIndexes {
            let loaderTypes = Set(indexes.compactMap { $0.modLoader })
            for loaderType in loaderTypes {
                if let loader = CurseForgeModLoaderType(rawValue: loaderType) {
                    switch loader {
                    case .forge:
                        loaders.append("forge")
                    case .fabric:
                        loaders.append("fabric")
                    case .quilt:
                        loaders.append("quilt")
                    case .neoforge:
                        loaders.append("neoforge")
                    }
                }
            }
        }
        
        // Handle loaders based on project type
        let projectType = cf.projectType
        if loaders.isEmpty {
            if projectType == "resourcepack" {
                // Resource packs use the "minecraft" loader
                loaders = ["minecraft"]
            } else if projectType == "datapack" {
                // Datapacks use the "datapack" loader
                loaders = ["datapack"]
            }
        }
        
        // Extract a list of version IDs
        var versions: [String] = []
        if let files = cf.latestFiles {
            versions = files.map { String($0.id) }
        }
        
        // Extract classification
        let categories = cf.categories.map { $0.slug }
        
        // Extract icon URL
        let iconUrl = cf.logo?.url ?? cf.logo?.thumbnailUrl
        
        // Create a license (CurseForge usually does not have explicit license information)
        let license = License(id: "unknown", name: "Unknown", url: nil)
        
        // Use the "cf-" prefix to identify the CurseForge project to avoid confusion with the Modrinth project
        // Use the HTML content returned by the description interface as the body, and extract the plain text as the description
        // If description is empty, fall back to summary
        let bodyContent = description.isEmpty ? (cf.body ?? cf.summary) : description
        let descriptionText = description.isEmpty ? cf.summary : extractPlainText(from: description)
        
        return ModrinthProjectDetail(
            slug: cf.slug ?? "curseforge-\(cf.id)",
            title: cf.name,
            description: descriptionText,
            categories: categories,
            clientSide: "optional", // CurseForge has no clear client/server information
            serverSide: "optional",
            body: bodyContent,
            additionalCategories: nil,
            issuesUrl: cf.links?.issuesUrl,
            sourceUrl: cf.links?.sourceUrl,
            wikiUrl: cf.links?.wikiUrl ?? cf.links?.websiteUrl,
            discordUrl: nil, // CurseForge has no Discord URL
            projectType: cf.projectType,
            downloads: cf.downloadCount ?? 0,
            iconUrl: iconUrl,
            id: "cf-\(cf.id)", // Use "cf-" prefix identification
            team: "",
            published: publishedDate,
            updated: updatedDate,
            followers: 0, // CurseForge has no followers
            license: license,
            versions: versions,
            gameVersions: gameVersions,
            loaders: loaders,
            type: cf.projectType,
            fileName: nil
        )
    }
    
    /// Convert CurseForge file details to Modrinth version format
    /// - Parameters:
    ///   - cfFile: CurseForge file details
    ///   - projectId: project ID
    /// - Returns: version details in Modrinth format
    static func convertVersion(_ cfFile: CurseForgeModFileDetail, projectId: String) -> ModrinthProjectDetailVersion? {
        // date parser
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Parse release date
        var publishedDate = Date()
        if !cfFile.fileDate.isEmpty {
            publishedDate = dateFormatter.date(from: cfFile.fileDate) ?? Date()
        }
        
        // Version types are uniformly regarded as release to avoid unnecessary distinctions
        let versionType = "release"
        
        // File level does not infer loader, keep empty array
        let loaders: [String] = []
        
        // Conversion dependencies
        var dependencies: [ModrinthVersionDependency] = []
        if let cfDeps = cfFile.dependencies {
            dependencies = cfDeps.compactMap { dep in
                // relationType: 1 = EmbeddedLibrary, 2 = OptionalDependency, 3 = RequiredDependency, 4 = Tool, 5 = Incompatible
                let dependencyType: String
                switch dep.relationType {
                case 3: // RequiredDependency
                    dependencyType = "required"
                case 2: // OptionalDependency
                    dependencyType = "optional"
                case 5: // Incompatible
                    dependencyType = "incompatible"
                default:
                    dependencyType = "optional"
                }
                
                return ModrinthVersionDependency(
                    projectId: String(dep.modId),
                    versionId: nil,
                    dependencyType: dependencyType
                )
            }
        }
        
        // Convert files
        let downloadUrl = cfFile.downloadUrl ?? URLConfig.API.CurseForge.fallbackDownloadUrl(
            fileId: cfFile.id,
            fileName: cfFile.fileName
        ).absoluteString
        
        var files: [ModrinthVersionFile] = []
        // Extract hash value: use hashes array first, if not, use hash field
        let hashes: ModrinthVersionFileHashes
        if let hashesArray = cfFile.hashes, !hashesArray.isEmpty {
            // Extract from hashes array first
            let sha1Hash = hashesArray.first { $0.algo == 1 }
            let sha512Hash = hashesArray.first { $0.algo == 2 }
            hashes = ModrinthVersionFileHashes(
                sha512: sha512Hash?.value ?? "",
                sha1: sha1Hash?.value ?? ""
            )
        } else if let hash = cfFile.hash {
            // If there is no hashes array, use the hash field
            switch hash.algo {
            case 1:
                hashes = ModrinthVersionFileHashes(sha512: "", sha1: hash.value)
            case 2:
                hashes = ModrinthVersionFileHashes(sha512: hash.value, sha1: "")
            default:
                hashes = ModrinthVersionFileHashes(sha512: "", sha1: "")
            }
        } else {
            // If neither, use empty hash
            hashes = ModrinthVersionFileHashes(sha512: "", sha1: "")
        }
        
        files.append(
            ModrinthVersionFile(
                hashes: hashes,
                url: downloadUrl,
                filename: cfFile.fileName,
                primary: true, // CurseForge usually has only one main file
                size: cfFile.fileLength ?? 0,
                fileType: nil
            )
        )
        
        // Make sure the projectId is prefixed with "cf-" if it isn't already
        let normalizedProjectId = projectId.hasPrefix("cf-") ? projectId : "cf-\(projectId.replacingOccurrences(of: "cf-", with: ""))"
        
        return ModrinthProjectDetailVersion(
            gameVersions: cfFile.gameVersions,
            loaders: loaders,
            id: "cf-\(cfFile.id)", // Use "cf-" prefix identification
            projectId: normalizedProjectId,
            authorId: cfFile.authors?.first?.name ?? "unknown",
            featured: false,
            name: cfFile.displayName,
            versionNumber: cfFile.displayName,
            changelog: cfFile.changelog,
            changelogUrl: nil,
            datePublished: publishedDate,
            downloads: 0, // CurseForge files do not have separate download numbers
            versionType: versionType,
            status: "listed",
            requestedStatus: nil,
            files: files,
            dependencies: dependencies
        )
    }
    
    /// Convert CurseForge search results to Modrinth format
    /// - Parameter cfResult: CurseForge search results
    /// - Returns: Search results in Modrinth format
    static func convertSearchResult(_ cfResult: CurseForgeSearchResult) -> ModrinthResult {
        let hits = cfResult.data.compactMap { cfMod -> ModrinthProject? in
            // Determine project type
            let projectType: String
            if let classId = cfMod.classId {
                switch classId {
                case 6: projectType = "mod"
                case 12: projectType = "resourcepack"
                case 6552: projectType = "shader"
                case 6945: projectType = "datapack"
                case 4471: projectType = "modpack"   // CurseForge integration package
                default: projectType = "mod"
                }
            } else {
                projectType = "mod"
            }
            
            // Extract a list of version IDs
            var versions: [String] = []
            if let files = cfMod.latestFiles {
                versions = files.map { String($0.id) }
            }
            
            // Use the "cf-" prefix to identify the CurseForge project to avoid confusion with the Modrinth project
            return ModrinthProject(
                projectId: "cf-\(cfMod.id)",
                projectType: projectType,
                slug: cfMod.slug ?? "curseforge-\(cfMod.id)",
                author: cfMod.authors?.first?.name ?? "Unknown",
                title: cfMod.name,
                description: cfMod.summary,
                categories: cfMod.categories?.map { $0.slug } ?? [],
                displayCategories: [],
                versions: versions,
                downloads: cfMod.downloadCount ?? 0,
                follows: 0,
                iconUrl: cfMod.logo?.url ?? cfMod.logo?.thumbnailUrl,
                license: "",
                clientSide: "optional",
                serverSide: "optional",
                fileName: nil
            )
        }
        
        let pagination = cfResult.pagination
        let offset = pagination?.index ?? 0
        let limit = pagination?.pageSize ?? 20
        let totalHits = pagination?.totalCount ?? hits.count
        
        return ModrinthResult(
            hits: hits,
            offset: offset,
            limit: limit,
            totalHits: totalHits
        )
    }
    
    /// Extract plain text from HTML content as a short description
    /// - Parameter html: HTML string
    /// - Returns: Extracted plain text (limited length)
    private static func extractPlainText(from html: String) -> String {
        // Simple HTML tag removal, extract first 200 characters as description
        let text = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Limit the length to avoid overly long descriptions
        if text.count > 200 {
            return String(text.prefix(200)) + "..."
        }
        return text.isEmpty ? "" : text
    }
}
