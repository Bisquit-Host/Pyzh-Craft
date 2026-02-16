import Foundation

// MARK: - Cache Entry
/// Search results cache entries
struct SearchCacheEntry {
    let results: [ModrinthProject]
    let totalHits: Int
    let timestamp: Date
    let page: Int
}

// MARK: - Cache Key
/// Search cache key, used to uniquely identify a search
struct SearchCacheKey: Hashable {
    let query: String
    let projectType: String
    let versions: [String]
    let categories: [String]
    let features: [String]
    let resolutions: [String]
    let performanceImpact: [String]
    let loaders: [String]
    let page: Int
    let dataSource: DataSource
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(query)
        hasher.combine(projectType)
        hasher.combine(versions)
        hasher.combine(categories)
        hasher.combine(features)
        hasher.combine(resolutions)
        hasher.combine(performanceImpact)
        hasher.combine(loaders)
        hasher.combine(page)
        hasher.combine(dataSource.rawValue)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query &&
        lhs.projectType == rhs.projectType &&
        lhs.versions == rhs.versions &&
        lhs.categories == rhs.categories &&
        lhs.features == rhs.features &&
        lhs.resolutions == rhs.resolutions &&
        lhs.performanceImpact == rhs.performanceImpact &&
        lhs.loaders == rhs.loaders &&
        lhs.page == rhs.page &&
        lhs.dataSource == rhs.dataSource
    }
}

// MARK: - Cache Manager
/// Resource Search Cache Manager
@MainActor
final class ResourceSearchCacheManager {
    // MARK: - Singleton
    static let shared = ResourceSearchCacheManager()
    // MARK: - Properties
    private var cache: [SearchCacheKey: SearchCacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    private let maxCacheSize: Int = 50 // Cache up to 50 search results
    // MARK: - Initialization
    private init() {}
    // MARK: - Public Methods
    /// Get cached search results
    /// - Parameter key: Search cache key
    /// - Returns: If the cache exists and is valid, return the cached search results, otherwise return nil
    func getCachedResult(for key: SearchCacheKey) -> SearchCacheEntry? {
        guard let entry = cache[key] else {
            return nil
        }
        // Check if cache is expired
        let timeElapsed = Date().timeIntervalSince(entry.timestamp)
        if timeElapsed > cacheTimeout {
            // Cache has expired, remove and return nil
            cache.removeValue(forKey: key)
            return nil
        }
        return entry
    }
    /// Caching search results
    /// - Parameters:
    ///   - key: search cache key
    ///   - results: search result list
    ///   - totalHits: number of results
    ///   - page: current page number
    func cacheResult(for key: SearchCacheKey, results: [ModrinthProject], totalHits: Int, page: Int) {
        let entry = SearchCacheEntry(
            results: results,
            totalHits: totalHits,
            timestamp: Date(),
            page: page
        )
        cache[key] = entry
        // Check the cache size and clear the oldest entries if it exceeds the limit
        cleanupIfNeeded()
    }
    /// clear all cache
    func clearAll() {
        cache.removeAll()
    }
    /// Clear cache for specific project types
    /// - Parameter projectType: project type
    func clear(for projectType: String) {
        cache = cache.filter { key, _ in
            key.projectType != projectType
        }
    }
    /// Clear the cache for a specific data source
    /// - Parameter dataSource: data source
    func clear(for dataSource: DataSource) {
        cache = cache.filter { key, _ in
            key.dataSource != dataSource
        }
    }
    // MARK: - Private Methods
    /// Clean cache if maximum cache size is exceeded
    private func cleanupIfNeeded() {
        guard cache.count > maxCacheSize else { return }
        // Find the oldest entry
        let sortedEntries = cache.sorted { $0.value.timestamp < $1.value.timestamp }
        // Remove oldest entries until cache size is within limit
        let entriesToRemove = sortedEntries.prefix(cache.count - maxCacheSize)
        for (key, _) in entriesToRemove {
            cache.removeValue(forKey: key)
        }
    }
}
