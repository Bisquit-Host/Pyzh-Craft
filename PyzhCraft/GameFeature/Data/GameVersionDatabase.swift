import Foundation
import SQLite3

/// Game version database storage layer
/// Use SQLite (WAL + mmap + JSON1) to store game version information
class GameVersionDatabase {
    // MARK: - Properties

    private let db: SQLiteDatabase
    private let tableName = AppConstants.DatabaseTables.gameVersions

    // MARK: - Initialization

    /// Initialize game version database
    /// - Parameter dbPath: database file path
    init(dbPath: String) {
        self.db = SQLiteDatabase(path: dbPath)
    }

    // MARK: - Database Setup

    /// Open the database and initialize the table structure
    /// - Throws: GlobalError when the operation fails
    func initialize() throws {
        try db.open()
        try createTable()
    }

    /// Create game version table
    /// Use JSON1 extension to store complete game version information
    private func createTable() throws {
        // Create table
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS \(tableName) (
            id TEXT PRIMARY KEY,
            working_path TEXT NOT NULL,
            game_name TEXT NOT NULL,
            data_json TEXT NOT NULL,
            last_played REAL NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """

        try db.execute(createTableSQL)

        // Create index if it does not exist
        let indexes = [
            ("idx_working_path", "working_path"),
            ("idx_last_played", "last_played"),
            ("idx_game_name", "game_name"),
        ]

        for (indexName, column) in indexes {
            let createIndexSQL = """
            CREATE INDEX IF NOT EXISTS \(indexName) ON \(tableName)(\(column));
            """
            try? db.execute(createIndexSQL) // Use try? because the index may already exist
        }

        Logger.shared.debug("游戏版本表已创建或已存在")
    }

    // MARK: - CRUD Operations

    /// Save game version information
    /// - Parameters:
    ///   - game: game version information
    ///   - workingPath: working path
    /// - Throws: GlobalError when the operation fails
    func saveGame(_ game: GameVersionInfo, workingPath: String) throws {
        try db.transaction {
            let encoder = JSONEncoder()
            // Encode dates using second-level timestamps (compatible with UserDefaults storage)
            encoder.dateEncodingStrategy = .secondsSince1970
            let jsonData = try encoder.encode(game)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw GlobalError.validation(
                    i18nKey: "Failed to encode game data as JSON",
                    level: .notification
                )
            }

            let now = Date()
            let sql = """
            INSERT OR REPLACE INTO \(tableName)
            (id, working_path, game_name, data_json, last_played, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?,
                COALESCE((SELECT created_at FROM \(tableName) WHERE id = ?), ?),
                ?)
            """

            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            SQLiteDatabase.bind(statement, index: 1, value: game.id)
            SQLiteDatabase.bind(statement, index: 2, value: workingPath)
            SQLiteDatabase.bind(statement, index: 3, value: game.gameName)
            SQLiteDatabase.bind(statement, index: 4, value: jsonString)
            SQLiteDatabase.bind(statement, index: 5, value: game.lastPlayed)
            SQLiteDatabase.bind(statement, index: 6, value: game.id)
            SQLiteDatabase.bind(statement, index: 7, value: now)
            SQLiteDatabase.bind(statement, index: 8, value: now)

            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(db.database))
                throw GlobalError.validation(
                    i18nKey: "Failed to save game: \(errorMessage)",
                    level: .notification
                )
            }
        }
    }

    /// Save game version information in batches
    /// - Parameters:
    ///   - games: Array of game version information
    ///   - workingPath: working path
    /// - Throws: GlobalError when the operation fails
    func saveGames(_ games: [GameVersionInfo], workingPath: String) throws {
        try db.transaction {
            let encoder = JSONEncoder()
            // Encode dates using second-level timestamps (compatible with UserDefaults storage)
            encoder.dateEncodingStrategy = .secondsSince1970
            let now = Date()

            let sql = """
            INSERT OR REPLACE INTO \(tableName)
            (id, working_path, game_name, data_json, last_played, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?,
                COALESCE((SELECT created_at FROM \(tableName) WHERE id = ?), ?),
                ?)
            """

            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            for game in games {
                let jsonData = try encoder.encode(game)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continue
                }

                sqlite3_reset(statement)
                SQLiteDatabase.bind(statement, index: 1, value: game.id)
                SQLiteDatabase.bind(statement, index: 2, value: workingPath)
                SQLiteDatabase.bind(statement, index: 3, value: game.gameName)
                SQLiteDatabase.bind(statement, index: 4, value: jsonString)
                SQLiteDatabase.bind(statement, index: 5, value: game.lastPlayed)
                SQLiteDatabase.bind(statement, index: 6, value: game.id)
                SQLiteDatabase.bind(statement, index: 7, value: now)
                SQLiteDatabase.bind(statement, index: 8, value: now)

                let result = sqlite3_step(statement)
                guard result == SQLITE_DONE else {
                    let errorMessage = String(cString: sqlite3_errmsg(db.database))
                    throw GlobalError.validation(
                        i18nKey: "Failed to batch save games: \(errorMessage)",
                        level: .notification
                    )
                }
            }
        }
    }

    /// Load all games in the specified working path
    /// - Parameter workingPath: working path
    /// - Returns: Array of game version information
    /// - Throws: GlobalError when the operation fails
    func loadGames(workingPath: String) throws -> [GameVersionInfo] {
        let sql = """
        SELECT data_json FROM \(tableName)
        WHERE working_path = ?
        ORDER BY last_played DESC
        """

        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        SQLiteDatabase.bind(statement, index: 1, value: workingPath)

        var games: [GameVersionInfo] = []
        let decoder = JSONDecoder()
        // Decode dates using second-level timestamps (compatible with UserDefaults storage)
        decoder.dateDecodingStrategy = .secondsSince1970

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let jsonString = SQLiteDatabase.stringColumn(statement, index: 0),
                  let jsonData = jsonString.data(using: .utf8) else {
                continue
            }

            do {
                let game = try decoder.decode(GameVersionInfo.self, from: jsonData)
                games.append(game)
            } catch {
                Logger.shared.warning("解码游戏数据失败: \(error.localizedDescription)")
                continue
            }
        }

        return games
    }

    /// Load games for all working paths (grouped by working path)
    /// - Returns: Game dictionary grouped by working path
    /// - Throws: GlobalError when the operation fails
    func loadAllGames() throws -> [String: [GameVersionInfo]] {
        let sql = """
        SELECT working_path, data_json FROM \(tableName)
        ORDER BY working_path, last_played DESC
        """

        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        var gamesByPath: [String: [GameVersionInfo]] = [:]
        let decoder = JSONDecoder()
        // Decode dates using second-level timestamps (compatible with UserDefaults storage)
        decoder.dateDecodingStrategy = .secondsSince1970

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let workingPath = SQLiteDatabase.stringColumn(statement, index: 0),
                  let jsonString = SQLiteDatabase.stringColumn(statement, index: 1),
                  let jsonData = jsonString.data(using: .utf8) else {
                continue
            }

            do {
                let game = try decoder.decode(GameVersionInfo.self, from: jsonData)
                if gamesByPath[workingPath] == nil {
                    gamesByPath[workingPath] = []
                }
                gamesByPath[workingPath]?.append(game)
            } catch {
                Logger.shared.warning("解码游戏数据失败: \(error.localizedDescription)")
                continue
            }
        }

        return gamesByPath
    }

    /// Get game by ID
    /// - Parameter id: Game ID
    /// - Returns: game version information, if it does not exist, return nil
    /// - Throws: GlobalError when the operation fails
    func getGame(by id: String) throws -> GameVersionInfo? {
        let sql = "SELECT data_json FROM \(tableName) WHERE id = ? LIMIT 1"

        let statement = try db.prepare(sql)
        defer { sqlite3_finalize(statement) }

        SQLiteDatabase.bind(statement, index: 1, value: id)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let jsonString = SQLiteDatabase.stringColumn(statement, index: 0),
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        // Decode dates using second-level timestamps (compatible with UserDefaults storage)
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(GameVersionInfo.self, from: jsonData)
    }

    /// Delete game
    /// - Parameter id: Game ID
    /// - Throws: GlobalError when the operation fails
    func deleteGame(id: String) throws {
        try db.transaction {
            let sql = "DELETE FROM \(tableName) WHERE id = ?"
            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            SQLiteDatabase.bind(statement, index: 1, value: id)

            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(db.database))
                throw GlobalError.validation(
                    i18nKey: "Failed to delete game: \(errorMessage)",
                    level: .notification
                )
            }
        }
    }

    /// Delete all games from the specified working path
    /// - Parameter workingPath: working path
    /// - Throws: GlobalError when the operation fails
    func deleteGames(workingPath: String) throws {
        try db.transaction {
            let sql = "DELETE FROM \(tableName) WHERE working_path = ?"
            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            SQLiteDatabase.bind(statement, index: 1, value: workingPath)

            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(db.database))
                throw GlobalError.validation(
                    i18nKey: "Failed to delete games in working path: \(errorMessage)",
                    level: .notification
                )
            }
        }
    }

    /// Update the last play time of the game
    /// - Parameters:
    ///   - id: game ID
    ///   - lastPlayed: last played time
    /// - Throws: GlobalError when the operation fails
    func updateLastPlayed(id: String, lastPlayed: Date) throws {
        try db.transaction {
            let timestamp = lastPlayed.timeIntervalSince1970
            let sql = """
            UPDATE \(tableName)
            SET data_json = json_set(data_json, '$.lastPlayed', ?),
                last_played = ?,
                updated_at = ?
            WHERE id = ?
            """

            let statement = try db.prepare(sql)
            defer { sqlite3_finalize(statement) }

            SQLiteDatabase.bind(statement, index: 1, value: String(timestamp))
            SQLiteDatabase.bind(statement, index: 2, value: lastPlayed)
            SQLiteDatabase.bind(statement, index: 3, value: Date())
            SQLiteDatabase.bind(statement, index: 4, value: id)

            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(db.database))
                throw GlobalError.validation(
                    i18nKey: "Failed to update last played time: \(errorMessage)",
                    level: .notification
                )
            }
        }
    }

    /// Close database connection
    func close() {
        db.close()
    }
}
