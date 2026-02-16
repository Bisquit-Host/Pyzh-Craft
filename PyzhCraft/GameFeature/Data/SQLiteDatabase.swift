import Foundation
import SQLite3

/// SQLite database manager
/// Optimize performance using WAL mode and mmap
class SQLiteDatabase {
    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbPath: String
    private let queue: DispatchQueue
    private static let queueKey = DispatchSpecificKey<Bool>()

    // MARK: - Initialization

    /// Initialize database connection
    /// - Parameters:
    ///   - path: database file path
    ///   -queue: database operation queue, the default is serial queue
    init(path: String, queue: DispatchQueue? = nil) {
        self.dbPath = path
        self.queue = queue ?? DispatchQueue(label: "com.pyzhcraft.sqlite", qos: .utility)
        self.queue.setSpecific(key: Self.queueKey, value: true)
    }

    deinit {
        close()
    }

    // MARK: - Connection Management

    private var isOnQueue: Bool {
        DispatchQueue.getSpecific(key: Self.queueKey) != nil
    }

    /// Execute the operation in the queue (execute it directly if it is already in the queue)
    private func sync<T>(_ block: () throws -> T) rethrows -> T {
        if isOnQueue {
            try block()
        } else {
            try queue.sync(execute: block)
        }
    }

    /// Open database connection
    /// - Throws: GlobalError when connection fails
    func open() throws {
        try sync {
            guard db == nil else { return }

            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            var tempDb: OpaquePointer?
            let result = sqlite3_open_v2(dbPath, &tempDb, flags, nil)

            guard result == SQLITE_OK, let openedDb = tempDb else {
                let errorMessage = tempDb.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
                if let dbToClose = tempDb {
                    sqlite3_close(dbToClose)
                }
                throw GlobalError.validation(i18nKey: "Failed to open database: %@",
                    level: .notification
                )
            }

            self.db = openedDb

            // Enable WAL mode
            try enableWALMode()

            // enable mmap
            try enableMmap()

            // Enable JSON1 extension (built-in in SQLite 3.9.0+)
            // The JSON1 extension is enabled by default, no additional action is required

            Logger.shared.debug("SQLite 数据库已打开: \(dbPath)")
        }
    }

    /// Close database connection
    func close() {
        sync {
            guard let db = db else { return }
            sqlite3_close(db)
            self.db = nil
            Logger.shared.debug("SQLite 数据库已关闭")
        }
    }

    /// Enable WAL mode (Write-Ahead Logging)
    /// Provide better concurrency performance and crash recovery capabilities
    private func enableWALMode() throws {
        guard let db = db else { return }

        let result = sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        guard result == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw GlobalError.validation(i18nKey: "Failed to enable WAL mode: %@",
                level: .notification
            )
        }

        sqlite3_exec(db, "PRAGMA wal_autocheckpoint=1000;", nil, nil, nil)

        Logger.shared.debug("WAL 模式已启用")
    }

    /// Enable mmap (memory mapping)
    /// Allow SQLite to use the operating system virtual memory system to access database files
    private func enableMmap() throws {
        guard let db = db else { return }

        // Set mmap size to 64MB (can be adjusted as needed)
        let mmapSize = 64 * 1024 * 1024
        let sql = "PRAGMA mmap_size=\(mmapSize);"

        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw GlobalError.validation(i18nKey: "Failed to enable mmap: %@",
                level: .notification
            )
        }

        Logger.shared.debug("mmap 已启用 (64MB)")
    }

    // MARK: - Transaction Management

    /// Perform transaction operations
    /// - Parameter block: transaction block
    /// - Throws: GlobalError when the operation fails
    func transaction<T>(_ block: () throws -> T) throws -> T {
        try sync {
            guard let db = db else {
                throw GlobalError.validation(i18nKey: "Database is not open",
                    level: .notification
                )
            }

            // start transaction
            var result = sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            guard result == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw GlobalError.validation(i18nKey: "Failed to begin transaction: %@",
                    level: .notification
                )
            }

            do {
                let value = try block()

                // commit transaction
                result = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
                guard result == SQLITE_OK else {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    throw GlobalError.validation(i18nKey: "Failed to commit transaction: %@",
                        level: .notification
                    )
                }

                return value
            } catch {
                // Rollback transaction
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw error
            }
        }
    }

    // MARK: - Query Execution

    /// Execute SQL statement (does not return results)
    /// - Parameter sql: SQL statement
    /// - Throws: GlobalError when execution fails
    func execute(_ sql: String) throws {
        try sync {
            guard let db = db else {
                throw GlobalError.validation(i18nKey: "Database is not open",
                    level: .notification
                )
            }

            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

            if result != SQLITE_OK {
                let message = errorMessage.map { String(cString: $0) } ?? "未知错误"
                sqlite3_free(errorMessage)
                throw GlobalError.validation(i18nKey: "SQL execution failed: %@",
                    level: .notification
                )
            }
        }
    }

    /// Prepare SQL statement
    /// - Parameter sql: SQL statement
    /// - Returns: prepared statement pointer
    /// - Throws: GlobalError when preparation fails
    /// - Warning: The returned statement must be used in the queue, and sqlite3_finalize is called after use
    func prepare(_ sql: String) throws -> OpaquePointer {
        return try sync {
            guard let db = db else {
                throw GlobalError.validation(i18nKey: "Database is not open",
                    level: .notification
                )
            }

            var statement: OpaquePointer?
            let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)

            guard result == SQLITE_OK, let stmt = statement else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw GlobalError.validation(i18nKey: "Failed to prepare SQL statement: %@",
                    level: .notification
                )
            }

            return stmt
        }
    }

    /// Get a database instance (for direct operations)
    /// - Returns: SQLite database pointer
    /// - Warning: only used within the queue
    var database: OpaquePointer? {
        return sync { db }
    }

    /// Perform operations in a queue
    /// - Parameter block: Operation block
    func perform<T>(_ block: @escaping (OpaquePointer?) throws -> T) throws -> T {
        return try sync {
            try block(db)
        }
    }
}

// MARK: - Statement Helpers

extension SQLiteDatabase {
    // Alternative to SQLITE_TRANSIENT: Use nil to have SQLite copy data
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Bind string parameters
    static func bind(_ statement: OpaquePointer, index: Int32, value: String?) {
        if let value = value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    /// Bind integer parameters
    static func bind(_ statement: OpaquePointer, index: Int32, value: Int) {
        sqlite3_bind_int64(statement, index, Int64(value))
    }

    /// Bind date parameter (stored as timestamp)
    static func bind(_ statement: OpaquePointer, index: Int32, value: Date) {
        sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
    }

    /// Bind BLOB parameters
    static func bind(_ statement: OpaquePointer, index: Int32, data: Data) {
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
    }

    /// Read string column
    static func stringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    /// Read integer column
    static func intColumn(_ statement: OpaquePointer, index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    /// Read date column
    static func dateColumn(_ statement: OpaquePointer, index: Int32) -> Date {
        let timestamp = sqlite3_column_double(statement, index)
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Read BLOB column
    static func dataColumn(_ statement: OpaquePointer, index: Int32) -> Data? {
        guard let blob = sqlite3_column_blob(statement, index) else { return nil }
        let length = sqlite3_column_bytes(statement, index)
        return Data(bytes: blob, count: Int(length))
    }
}
