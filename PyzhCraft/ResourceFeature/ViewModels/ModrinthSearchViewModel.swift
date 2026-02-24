import SwiftUI

// MARK: - Constants
/// Define Modrinth related constants
enum ModrinthConstants {
    // MARK: - UI Constants
    /// UI related constants
    enum UIConstants {
        static let pageSize = 20
        static let iconSize: CGFloat = 48
        static let cornerRadius: CGFloat = 8
        static let tagCornerRadius: CGFloat = 6
        static let verticalPadding: CGFloat = 3
        static let tagHorizontalPadding: CGFloat = 3
        static let tagVerticalPadding: CGFloat = 1
        static let spacing: CGFloat = 3
        static let descriptionLineLimit = 1
        static let maxTags = 3
        static let contentSpacing: CGFloat = 8
    }
    
    // MARK: - API Constants
    /// API related constants
    enum API {
        enum FacetType {
            static let projectType = "project_type"
            static let versions = "versions"
            static let categories = "categories"
            static let clientSide = "client_side"
            static let serverSide = "server_side"
            static let resolutions = "resolutions"
            static let performanceImpact = "performance_impact"
        }
        
        enum FacetValue {
            static let required = "required"
            static let optional = "optional"
            static let unsupported = "unsupported"
        }
    }
}

// MARK: - Filter Options
/// Filter option structure, used to reduce the number of function parameters
struct FilterOptions {
    let resolutions: [String]
    let performanceImpact: [String]
    let loaders: [String]
}

// MARK: - ViewModel
/// Modrinth search view model
@MainActor
final class ModrinthSearchViewModel: ObservableObject {
    private struct SearchCachePayload: Codable {
        let hits: [ModrinthProject]
        let totalHits: Int
        let updatedAt: Date
    }

    private struct SearchCacheContext {
        let query: String
        let projectType: String
        let versions: [String]
        let categories: [String]
        let features: [String]
        let resolutions: [String]
        let performanceImpact: [String]
        let loaders: [String]
        let dataSource: DataSource
    }

    // MARK: - Published Properties
    @Published private(set) var results: [ModrinthProject] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: GlobalError?
    @Published private(set) var totalHits: Int = 0
    
    // MARK: - Private Properties
    private var searchTask: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>?
    private let pageSize: Int = 20
    private let cacheManager = ResourceSearchCacheManager.shared
    
    // MARK: - Initialization
    init() {}
    
    deinit {
        searchTask?.cancel()
        cacheTask?.cancel()
    }
    
    // MARK: - Public Methods
    // swiftlint:disable:next function_parameter_count
    func search(
        query: String,
        projectType: String,
        versions: [String],
        categories: [String],
        features: [String],
        resolutions: [String],
        performanceImpact: [String],
        loaders: [String],
        page: Int = 1,
        append: Bool = false,
        dataSource: DataSource = .modrinth
    ) async {
        // Cancel any existing search task
        searchTask?.cancel()
        
        searchTask = Task {
            do {
                // Create cache key
                let cacheKey = SearchCacheKey(
                    query: query,
                    projectType: projectType,
                    versions: versions,
                    categories: categories,
                    features: features,
                    resolutions: resolutions,
                    performanceImpact: performanceImpact,
                    loaders: loaders,
                    page: page,
                    dataSource: dataSource
                )
                // Try to get results from cache
                if let cachedEntry = cacheManager.getCachedResult(for: cacheKey) {
                    // Use cached results
                    if !Task.isCancelled {
                        if append {
                            results.append(contentsOf: cachedEntry.results)
                        } else {
                            results = cachedEntry.results
                        }
                        totalHits = cachedEntry.totalHits
                        // After the cache is hit, the loading status must also be set to false
                        if append {
                            isLoadingMore = false
                        } else {
                            isLoading = false
                        }
                    }
                    return
                }
                if append {
                    isLoadingMore = true
                } else {
                    isLoading = results.isEmpty
                }
                error = nil
                
                // Check if the task has been canceled
                try Task.checkCancellation()
                
                let offset = (page - 1) * pageSize
                let filterOptions = FilterOptions(
                    resolutions: resolutions,
                    performanceImpact: performanceImpact,
                    loaders: loaders
                )
                let facets = buildFacets(
                    projectType: projectType,
                    versions: versions,
                    categories: categories,
                    features: features,
                    filterOptions: filterOptions
                )
                
                try Task.checkCancellation()
                
                let result: ModrinthResult
                if dataSource == .modrinth {
                    // Using the Modrinth service
                    result = await ModrinthService.searchProjects(
                        facets: facets,
                        offset: offset,
                        limit: pageSize,
                        query: query
                    )
                } else {
                    // Use CurseForge service and convert to Modrinth format
                    // Convert Modrinth search parameters to CurseForge search parameters
                    // The resource package needs to map resolutions together to the CurseForge category ID
                    let cfParams = convertToCurseForgeParams(
                        projectType: projectType,
                        versions: versions,
                        categories: categories,
                        resolutions: resolutions,
                        loaders: loaders,
                        query: query
                    )
                    
                    let cfResult = await CurseForgeService.searchProjects(
                        gameId: 432, // Minecraft
                        classId: cfParams.classId,
                        categoryId: nil,
                        categoryIds: cfParams.categoryIds,
                        gameVersion: nil,
                        gameVersions: cfParams.gameVersions,
                        searchFilter: cfParams.searchFilter,
                        modLoaderType: nil,
                        modLoaderTypes: cfParams.modLoaderTypes,
                        index: offset,
                        pageSize: pageSize
                    )
                    result = CurseForgeToModrinthAdapter.convertSearchResult(cfResult)
                }
                
                try Task.checkCancellation()
                
                if !Task.isCancelled {
                    // Caching search results
                    cacheManager.cacheResult(
                        for: cacheKey,
                        results: result.hits,
                        totalHits: result.totalHits,
                        page: page
                    )
                    if append {
                        results.append(contentsOf: result.hits)
                        trimResultsIfNeeded()
                    } else {
                        results = Array(result.hits.prefix(maxRetainedResults))
                        if settings.enableResourcePageCache {
                            saveFirstPageCache(
                                cacheKey: searchCacheKey,
                                hits: result.hits,
                                totalHits: result.totalHits
                            )
                        }
                    }
                    totalHits = result.totalHits
                }
                
                try Task.checkCancellation()
                
                if !Task.isCancelled {
                    if append {
                        isLoadingMore = false
                    } else {
                        isLoading = false
                    }
                }
            } catch is CancellationError {
                // The task was canceled and does not need to be processed
                return
            } catch {
                let globalError = GlobalError.from(error)
                if !Task.isCancelled {
                    self.error = globalError
                    self.isLoading = false
                    self.isLoadingMore = false
                }
                Logger.shared.error("Search failed: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
            }
        }
    }
    
    func clearResults() {
        searchTask?.cancel()
        cacheTask?.cancel()
        results.removeAll()
        totalHits = 0
        error = nil
        isLoading = false
        isLoadingMore = false
    }
    
    @MainActor
    func beginNewSearch() {
        isLoading = true
        results.removeAll()
    }

    private func trimResultsIfNeeded() {
        if results.count > maxRetainedResults {
            results.removeFirst(results.count - maxRetainedResults)
        }
    }

    private func cacheKey(context: SearchCacheContext) -> String {
        let keyParts = [
            "q:\(context.query)",
            "type:\(context.projectType)",
            "v:\(context.versions.sorted().joined(separator: ","))",
            "c:\(context.categories.sorted().joined(separator: ","))",
            "f:\(context.features.sorted().joined(separator: ","))",
            "r:\(context.resolutions.sorted().joined(separator: ","))",
            "p:\(context.performanceImpact.sorted().joined(separator: ","))",
            "l:\(context.loaders.sorted().joined(separator: ","))",
            "ds:\(context.dataSource.rawValue)",
        ]
        return keyParts.joined(separator: "|")
    }

    private func loadCachedFirstPageAsync(cacheKey: String) async -> SearchCachePayload? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let cached: SearchCachePayload? = AppCacheManager.shared.get(
                    namespace: self.cacheNamespace,
                    key: cacheKey,
                    as: SearchCachePayload.self
                )
                continuation.resume(returning: cached)
            }
        }
    }

    private func saveFirstPageCache(cacheKey: String, hits: [ModrinthProject], totalHits: Int) {
        let payload = SearchCachePayload(
            hits: Array(hits.prefix(maxRetainedResults)),
            totalHits: totalHits,
            updatedAt: Date()
        )
        AppCacheManager.shared.setSilently(
            namespace: cacheNamespace,
            key: cacheKey,
            value: payload
        )
    }
    // MARK: - Private Methods
    private func buildFacets(
        projectType: String,
        versions: [String],
        categories: [String],
        features: [String],
        filterOptions: FilterOptions
    ) -> [[String]] {
        var facets: [[String]] = []
        
        // Project type is always required
        facets.append([
            "\(ModrinthConstants.API.FacetType.projectType):\(projectType)"
        ])
        
        // Add versions if any
        if !versions.isEmpty {
            facets.append(
                versions.map {
                    "\(ModrinthConstants.API.FacetType.versions):\($0)"
                }
            )
        }
        
        // Add categories if any
        if !categories.isEmpty {
            facets.append(
                categories.map {
                    "\(ModrinthConstants.API.FacetType.categories):\($0)"
                }
            )
        }
        
        // Handle client_side and server_side based on features selection
        let (clientFacets, serverFacets) = buildEnvironmentFacets(
            features: features
        )
        if !clientFacets.isEmpty {
            facets.append(clientFacets)
        }
        if !serverFacets.isEmpty {
            facets.append(serverFacets)
        }
        
        // Add resolutions if any (as categories)
        if !filterOptions.resolutions.isEmpty {
            facets.append(filterOptions.resolutions.map { "categories:\($0)" })
        }
        
        // Add performance impact if any (as categories)
        if !filterOptions.performanceImpact.isEmpty {
            facets.append(filterOptions.performanceImpact.map { "categories:\($0)" })
        }
        
        // Add loaders if any (as categories)
        if !filterOptions.loaders.isEmpty && projectType != "resourcepack"
            && projectType != "datapack" {
            var loadersToUse = filterOptions.loaders
            if let first = filterOptions.loaders.first, first.lowercased() == "vanilla" {
                loadersToUse = ["minecraft"]
            }
            facets.append(loadersToUse.map { "categories:\($0)" })
        }
        
        return facets
    }
    
    private func buildEnvironmentFacets(features: [String]) -> (
        clientFacets: [String], serverFacets: [String]
    ) {
        let hasClient = features.contains(AppConstants.EnvironmentTypes.client)
        let hasServer = features.contains(AppConstants.EnvironmentTypes.server)
        
        var clientFacets: [String] = []
        var serverFacets: [String] = []
        
        if hasClient {
            clientFacets.append("client_side:required")
        } else if hasServer {
            clientFacets.append("client_side:optional")
        }
        
        if hasServer {
            serverFacets.append("server_side:required")
        } else if hasClient {
            serverFacets.append("server_side:optional")
        }
        
        return (clientFacets, serverFacets)
    }
    
    /// Get the classId of CurseForge based on the project type
    private func classIdForProjectType(_ projectType: String) -> Int? {
        switch projectType.lowercased() {
        case "mod":
            return 6
        case "modpack":
            // classId for CurseForge Minecraft modpacks
            return 4471
        case "resourcepack":
            return 12
        case "shader":
            return 6552
        case "datapack":
            return 6945
        default:
            return nil
        }
    }
    
    /// CurseForge search parameter structure
    private struct CurseForgeSearchParams {
        let classId: Int?
        let categoryIds: [Int]?
        let gameVersions: [String]?
        let searchFilter: String?
        let modLoaderTypes: [Int]?
    }
    
    /// Convert Modrinth search parameters to CurseForge search parameters
    /// - Parameters:
    ///   - projectType: project type
    ///   - versions: game version list
    ///   - categories: Category list (behavioral/functional categories)
    ///   - resolutions: resource pack resolution list (only takes effect when resourcepack is used)
    ///   - loaders: loader list
    ///   - query: search keywords
    /// - Returns: CurseForge search parameters
    /// - Note: API limitations: gameVersions at most 4, modLoaderTypes at most 5, categoryIds at most 10
    private func convertToCurseForgeParams(
        projectType: String,
        versions: [String],
        categories: [String],
        resolutions: [String],
        loaders: [String],
        query: String
    ) -> CurseForgeSearchParams {
        // Convert item type to classId
        let classId = classIdForProjectType(projectType)
        
        // Convert a list of game versions (CurseForge API limit: up to 4 versions)
        let gameVersions: [String]?
        if !versions.isEmpty {
            gameVersions = Array(versions.prefix(4))
        } else {
            gameVersions = nil
        }
        
        // Convert categories (CurseForge uses categoryIds, mapped from Modrinth category names)
        // For resourcepack, the behavior classification + resolution classification need to be mapped together
        // API limit: Maximum 10 category IDs
        let categoryIds: [Int]?
        let allCategoryNames: [String]
        if projectType.lowercased() == "resourcepack" {
            // Behavior tag + resolution tag participate in mapping together
            allCategoryNames = categories + resolutions
        } else {
            allCategoryNames = categories
        }
        
        if !allCategoryNames.isEmpty {
            let mappedIds = ModrinthToCurseForgeCategoryMapper.mapToCurseForgeCategoryIds(
                modrinthCategoryNames: allCategoryNames,
                projectType: projectType
            )
            categoryIds = mappedIds.isEmpty ? nil : mappedIds
        } else {
            categoryIds = nil
        }
        
        // Convert loader list to modLoaderTypes
        // ModLoaderType: 1=Forge, 4=Fabric, 5=Quilt, 6=NeoForge
        // API limit: maximum 5 loader types
        
        let modLoaderTypes: [Int]?
        
        if projectType == "resourcepack" || projectType == "shaderpack" || projectType == "datapack" {
            modLoaderTypes = nil
        } else {
            if !loaders.isEmpty {
                let loaderTypes = loaders.compactMap { loader -> Int? in
                    if let loaderType = CurseForgeModLoaderType.from(loader) {
                        return loaderType.rawValue
                    }
                    return nil
                }
                // Limit to 5 loader types
                modLoaderTypes = loaderTypes.isEmpty ? nil : Array(loaderTypes.prefix(5))
            } else {
                modLoaderTypes = nil
            }
        }
        
        // Search keywords (pass the original query directly, CurseForgeService is responsible for normalizing the spaces into "+")
        let searchFilter = query.isEmpty ? nil : query
        
        return CurseForgeSearchParams(
            classId: classId,
            categoryIds: categoryIds,
            gameVersions: gameVersions,
            searchFilter: searchFilter,
            modLoaderTypes: modLoaderTypes
        )
    }
}
