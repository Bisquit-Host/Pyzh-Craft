import Foundation

/// Mod Cache Manager
/// Use SQLite database to store mod.json data (hash -> JSON BLOB)
class ModCacheManager {
    static let shared = ModCacheManager()

    private let modCacheDB: ModCacheDatabase
    private let queue = DispatchQueue(label: "ModCacheManager.queue")
    private var isInitialized = false

    private init() {
        let dbPath = AppPaths.gameVersionDatabase.path
        self.modCacheDB = ModCacheDatabase(dbPath: dbPath)
    }

    // MARK: - Initialization

    /// Initialize database connection
    /// - Throws: GlobalError when the operation fails
    private func ensureInitialized() throws {
        if !isInitialized {
            // Make sure the database directory exists
            let dataDir = AppPaths.dataDirectory
            try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

            try modCacheDB.open()
            isInitialized = true
        }
    }

    // MARK: - Public API

    /// - Parameters:
    ///   - hash: the hash value of the mod file
    ///   - jsonData: Data of JSON data (original JSON bytes)
    /// - Throws: GlobalError when the operation fails
    func set(hash: String, jsonData: Data) throws {
        try queue.sync {
            try ensureInitialized()
            try modCacheDB.saveModCache(hash: hash, jsonData: jsonData)
        }
    }

    /// - Parameters:
    ///   - hash: the hash value of the mod file
    ///   - jsonData: Data of JSON data (original JSON bytes)
    func setSilently(hash: String, jsonData: Data) {
        do {
            try set(hash: hash, jsonData: jsonData)
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    /// Get mod cache value
    /// - Parameter hash: the hash value of the mod file
    /// - Returns: Data of JSON data (original JSON bytes), or nil if it does not exist
    func get(hash: String) -> Data? {
        return queue.sync {
            do {
                try ensureInitialized()
                return try modCacheDB.getModCache(hash: hash)
            } catch {
                GlobalErrorHandler.shared.handle(error)
                return nil
            }
        }
    }

    /// Get all mod cache data
    /// - Returns: hash -> dictionary of JSON Data
    func getAll() -> [String: Data] {
        return queue.sync {
            do {
                try ensureInitialized()
                return try modCacheDB.getAllModCaches()
            } catch {
                GlobalErrorHandler.shared.handle(error)
                return [:]
            }
        }
    }

    /// Remove mod cache items
    /// - Parameter hash: the hash value of the mod file
    /// - Throws: GlobalError when the operation fails
    func remove(hash: String) throws {
        try queue.sync {
            try ensureInitialized()
            try modCacheDB.deleteModCache(hash: hash)
        }
    }

    /// Remove mod cache items (silent version)
    /// - Parameter hash: the hash value of the mod file
    func removeSilently(hash: String) {
        do {
            try remove(hash: hash)
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    /// Remove mod cache items in batches
    /// - Parameter hashes: array of hashes to be deleted
    /// - Throws: GlobalError when the operation fails
    func remove(hashes: [String]) throws {
        try queue.sync {
            try ensureInitialized()
            try modCacheDB.deleteModCaches(hashes: hashes)
        }
    }

    /// Remove mod cache items in batches (silent version)
    /// - Parameter hashes: array of hashes to be deleted
    func removeSilently(hashes: [String]) {
        do {
            try remove(hashes: hashes)
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    /// Clear all mod caches
    /// - Throws: GlobalError when the operation fails
    func clear() throws {
        try queue.sync {
            try ensureInitialized()
            try modCacheDB.clearAllModCaches()
        }
    }

    /// Clear all mod caches (silent version)
    func clearSilently() {
        do {
            try clear()
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    /// - Parameter hash: the hash value of the mod file
    /// - Returns: Does it exist?
    func has(hash: String) -> Bool {
        return queue.sync {
            do {
                try ensureInitialized()
                return try modCacheDB.hasModCache(hash: hash)
            } catch {
                GlobalErrorHandler.shared.handle(error)
                return false
            }
        }
    }

    /// - Parameter data: hash -> dictionary of JSON Data
    /// - Throws: GlobalError when the operation fails
    func setAll(_ data: [String: Data]) throws {
        try queue.sync {
            try ensureInitialized()
            try modCacheDB.saveModCaches(data)
        }
    }

    /// - Parameter data: hash -> dictionary of JSON Data
    func setAllSilently(_ data: [String: Data]) {
        do {
            try setAll(data)
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }
}
