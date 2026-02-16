import Foundation
import SQLite3

/// Mod cache database storage layer
/// Use SQLite to store mod.json data (hash -> JSON BLOB)
class ModCacheDatabase {
    // MARK: - Properties

    private let db: SQLiteDatabase
    private let tableName = AppConstants.DatabaseTables.modCache

    // MARK: - Initialization

    /// - Parameter dbPath: database file path
    init(dbPath: String) {
        self.db = SQLiteDatabase(path: dbPath)
    }

    // MARK: - Database Setup

    /// Open a database connection and create the table if it does not exist
    /// - Throws: GlobalError when the operation fails
    func open() throws {
        try db.open()
        try createTable()
    }

    /// Create mod cache table
    /// Used to store mod.json data (hash -> JSON BLOB)
    private func createTable() throws {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS \(tableName) (
            hash TEXT PRIMARY KEY,
            json_data BLOB NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """

        try db.execute(createTableSQL)

        // Create index if it does not exist
        let createIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_mod_cache_updated_at ON \(tableName)(updated_at);
        """
        try? db.execute(createIndexSQL)

        Logger.shared.debug("mod 缓存表已创建或已存在")
    }

    /// Close database connection
    func close() {
        db.close()
    }

    // MARK: - CRUD Operations

    /// Save mod cache data
    /// - Parameters:
    ///   - hash: the hash value of the mod file
    ///   - jsonData: Data of JSON data (original JSON bytes)
    /// - Throws: GlobalError when the operation fails
    func saveModCache(hash: String, jsonData: Data) throws {
        try db.transaction {
            let now = Date()
            let sql = """
            INSERT OR REPLACE INTO \(tableName)
            (hash, json_data, created_at, updated_at)
            VALUES (?, ?,
                COALESCE((SELECT created_at FROM \(tableName) WHERE hash = ?), ?),
                ?)
            """

            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            SQLiteDatabase.bind(statement, index: 1, value: hash)
            SQLiteDatabase.bind(statement, index: 2, data: jsonData)
            SQLiteDatabase.bind(statement, index: 3, value: hash)
            SQLiteDatabase.bind(statement, index: 4, value: now)
            SQLiteDatabase.bind(statement, index: 5, value: now)

            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(db.database))
                throw GlobalError.validation(
                    i18nKey: "Failed to save mod cache: %@",
                    level: .notification
                )
            }
        }
    }

    /// Save mod cache data in batches
    /// - Parameter data: hash -> dictionary of JSON Data
    /// - Throws: GlobalError when the operation fails
    func saveModCaches(_ data: [String: Data]) throws {
        try db.transaction {
            let now = Date()
            let sql = """
            INSERT OR REPLACE INTO \(tableName)
            (hash, json_data, created_at, updated_at)
            VALUES (?, ?,
                COALESCE((SELECT created_at FROM \(tableName) WHERE hash = ?), ?),
                ?)
            """

            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            for (hash, jsonData) in data {
                sqlite3_reset(statement)
                SQLiteDatabase.bind(statement, index: 1, value: hash)
                SQLiteDatabase.bind(statement, index: 2, data: jsonData)
                SQLiteDatabase.bind(statement, index: 3, value: hash)
                SQLiteDatabase.bind(statement, index: 4, value: now)
                SQLiteDatabase.bind(statement, index: 5, value: now)

                let result = sqlite3_step(statement)
                guard result == SQLITE_DONE else {
                    let errorMessage = String(cString: sqlite3_errmsg(db.database))
                    throw GlobalError.validation(
                        i18nKey: "Failed to batch save mod cache: %@",
                        level: .notification
                    )
                }
            }
        }
    }

    /// Get mod cache data
    /// - Parameter hash: the hash value of the mod file
    /// - Returns: Data of JSON data (original JSON bytes), or nil if it does not exist
    /// - Throws: GlobalError when the operation fails
    func getModCache(hash: String) throws -> Data? {
        let sql = "SELECT json_data FROM \(tableName) WHERE hash = ? LIMIT 1"

        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        SQLiteDatabase.bind(statement, index: 1, value: hash)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let jsonData = SQLiteDatabase.dataColumn(statement, index: 0) else {
            return nil
        }

        return jsonData
    }

    /// Get all mod cache data
    /// - Returns: hash -> dictionary of JSON Data
    /// - Throws: GlobalError when the operation fails
    func getAllModCaches() throws -> [String: Data] {
        let sql = "SELECT hash, json_data FROM \(tableName)"

        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        var result: [String: Data] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let hash = SQLiteDatabase.stringColumn(statement, index: 0),
                  let jsonData = SQLiteDatabase.dataColumn(statement, index: 1) else {
                continue
            }
            result[hash] = jsonData
        }

        return result
    }

    /// Delete mod cache data
    /// - Parameter hash: the hash value of the mod file
    /// - Throws: GlobalError when the operation fails
    func deleteModCache(hash: String) throws {
        try db.transaction {
            let sql = "DELETE FROM \(tableName) WHERE hash = ?"
            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            SQLiteDatabase.bind(statement, index: 1, value: hash)

            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(db.database))
                throw GlobalError.validation(
                    i18nKey: "Failed to delete mod cache: %@",
                    level: .notification
                )
            }
        }
    }

    /// Delete mod cache data in batches
    /// - Parameter hashes: array of hashes to be deleted
    /// - Throws: GlobalError when the operation fails
    func deleteModCaches(hashes: [String]) throws {
        try db.transaction {
            let sql = "DELETE FROM \(tableName) WHERE hash = ?"
            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            for hash in hashes {
                sqlite3_reset(statement)
                SQLiteDatabase.bind(statement, index: 1, value: hash)

                let result = sqlite3_step(statement)
                guard result == SQLITE_DONE else {
                    let errorMessage = String(cString: sqlite3_errmsg(db.database))
                    throw GlobalError.validation(
                        i18nKey: "Failed to batch delete mod cache: %@",
                        level: .notification
                    )
                }
            }
        }
    }

    /// Clear all mod cache data
    /// - Throws: GlobalError when the operation fails
    func clearAllModCaches() throws {
        try db.transaction {
            let sql = "DELETE FROM \(tableName)"
            try db.execute(sql)
        }
    }

    /// - Parameter hash: the hash value of the mod file
    /// - Returns: Does it exist?
    /// - Throws: GlobalError when the operation fails
    func hasModCache(hash: String) throws -> Bool {
        let sql = "SELECT 1 FROM \(tableName) WHERE hash = ? LIMIT 1"

        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        SQLiteDatabase.bind(statement, index: 1, value: hash)

        return sqlite3_step(statement) == SQLITE_ROW
    }
}
