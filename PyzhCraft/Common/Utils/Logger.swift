import Foundation
import OSLog
import AppKit

class Logger: AppLogging {
    static let shared = Logger()
    private let logger = OSLog(
        subsystem: Bundle.main.identifier,
        category: Bundle.main.appCategory
    )

    // File log related attributes
    private var logFileHandle: FileHandle?
    private let logQueue = DispatchQueue(label: AppConstants.logTag, qos: .utility)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    // Log file path
    private var logFileURL: URL? {
        // Use logsDirectory defined in AppPaths (now always returns a valid path)
        let logsDirectory = AppPaths.logsDirectory

        // Get the app name, remove spaces and convert to lowercase
        let appName = Bundle.main.appName.replacingOccurrences(of: " ", with: "-").lowercased()

        // Create logs directory
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        // Use app name-date format as file name
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        return logsDirectory.appendingPathComponent("\(appName)-\(today).log")
    }

    private init() {
        // Clean old log files on startup
        cleanupOldLogs()
        setupLogFile()
    }

    deinit {
        closeLogFile()
    }

    // MARK: - File log settings

    private func setupLogFile() {
        guard let logURL = logFileURL else { return }

        // If the file does not exist, create the file
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        // open file handle
        do {
            logFileHandle = try FileHandle(forWritingTo: logURL)
            // Move to end of file
            logFileHandle?.seekToEndOfFile()

            // Write startup log
            let startupMessage = "=== Launcher Started at \(dateFormatter.string(from: Date())) ===\n"
            if let data = startupMessage.data(using: .utf8) {
                logFileHandle?.write(data)
            }
        } catch {
            Self.shared.error("Failed to setup log file: \(error)")
        }
    }

    private func closeLogFile() {
        logFileHandle?.closeFile()
        logFileHandle = nil
    }

    // MARK: - Write to log file

    private func writeToLogFile(_ message: String) {
        logQueue.async {
            // Check if you need to switch to a new log file (date changes)
            self.checkAndSwitchLogFile()

            let timestamp = self.dateFormatter.string(from: Date())
            let logEntry = "[\(timestamp)] \(message)\n"

            if let data = logEntry.data(using: .utf8) {
                self.logFileHandle?.write(data)
                // Force sync to disk
                self.logFileHandle?.synchronizeFile()
            }
        }
    }

    // MARK: - Log file switching

    private func checkAndSwitchLogFile() {
        guard let currentLogURL = logFileURL else { return }

        // Check if the current file handle points to the correct file
        if let currentHandle = logFileHandle {
            // If the file handle exists but the file path pointed to does not match, you need to switch
            if currentHandle.fileDescriptor != -1 {
                // Check if file path matches current date
                let expectedFileName = currentLogURL.lastPathComponent
                let currentFileName = currentLogURL.lastPathComponent

                if expectedFileName != currentFileName {
                    // Date changes, switch to new file
                    switchToNewLogFile()
                }
            }
        } else {
            // File handle does not exist, reset it
            setupLogFile()
        }
    }

    private func switchToNewLogFile() {
        // Close current file handle
        closeLogFile()

        // Set up new log file
        setupLogFile()

        // Record file switching log
        let switchMessage = "=== Log file switched at \(dateFormatter.string(from: Date())) ===\n"
        if let data = switchMessage.data(using: .utf8) {
            logFileHandle?.write(data)
        }
    }

    // MARK: - Public Logging Methods

    func debug(
        _ items: Any...,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(
            items,
            type: .debug,
            prefix: "🔍",
            file: file,
            function: function,
            line: line
        )
    }

    func info(
        _ items: Any...,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(
            items,
            type: .info,
            prefix: "ℹ️",
            file: file,
            function: function,
            line: line
        )
    }

    func warning(
        _ items: Any...,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(
            items,
            type: .default,
            prefix: "⚠️",
            file: file,
            function: function,
            line: line
        )
    }

    func error(
        _ items: Any...,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(
            items,
            type: .error,
            prefix: "❌",
            file: file,
            function: function,
            line: line
        )
    }

    // MARK: - AppLogging

    func logInfo(_ items: Any..., file: String = #file, function: String = #function, line: Int = #line) {
        log(items, type: .info, prefix: "ℹ️", file: file, function: function, line: line)
    }
    func logWarning(_ items: Any..., file: String = #file, function: String = #function, line: Int = #line) {
        log(items, type: .default, prefix: "⚠️", file: file, function: function, line: line)
    }
    func logError(_ items: Any..., file: String = #file, function: String = #function, line: Int = #line) {
        log(items, type: .error, prefix: "❌", file: file, function: function, line: line)
    }

    // MARK: - Core Logging

    fileprivate func log(
        _ items: [Any],
        type: OSLogType,
        prefix: String,
        file: String,
        function: String,
        line: Int
    ) {
        let fileName = (file as NSString).lastPathComponent
        // Optimization: Use NSMutableString to reduce temporary object creation
        let message = NSMutableString()
        for (index, item) in items.enumerated() {
            if index > 0 {
                message.append(" ")
            }
            message.append(Self.stringify(item))
        }
        let logMessage = "\(prefix) [\(fileName):\(line)] \(function): \(message)"

        // Output to the console. Local debugging can be enabled
        os_log("%{public}@", log: logger, type: type, logMessage)

        // write to file
        writeToLogFile(logMessage)
    }

    // MARK: - Log file management

    /// Get log file path
    func getLogFilePath() -> String? {
        logFileURL?.path
    }

    /// Get current log file information
    func getCurrentLogInfo() -> (path: String, fileName: String, date: String)? {
        guard let logURL = logFileURL else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        return (
            path: logURL.path,
            fileName: logURL.lastPathComponent,
            date: today
        )
    }

    /// Manually trigger log cleanup
    func manualCleanup() {
        cleanupOldLogs()
    }

    /// Open current log file
    func openLogFile() {
        guard let logURL = logFileURL else {
            Self.shared.error("Unable to get log file path")
            return
        }

        // Check if the file exists
        if FileManager.default.fileExists(atPath: logURL.path) {
            // Open the log file using the system default application
            NSWorkspace.shared.open(logURL)
        } else {
            // If the log file does not exist, create and open it
            do {
                // Make sure the directory exists
                try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                // Create log file
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let dateString = dateFormatter.string(from: Date())

                try "Log file created - \(dateString)".write(to: logURL, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(logURL)
            } catch {
                Self.shared.error("Unable to create or open log file: \(error)")
            }
        }
    }

    /// Clean old log files (keep the last 7 days of logs)
    func cleanupOldLogs() {
        logQueue.async {
            let calendar = Calendar.current
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

            // Clean using logsDirectory defined in AppPaths (valid paths are now always returned)
            let logsDirectory = AppPaths.logsDirectory
            self.cleanupLogsInDirectory(logsDirectory, sevenDaysAgo: sevenDaysAgo)
        }
    }

    private func cleanupLogsInDirectory(_ directory: URL, sevenDaysAgo: Date) {
        // Check if directory exists, skip cleaning if not
        guard FileManager.default.fileExists(atPath: directory.path) else {
            // It is normal (first run) that the directory does not exist and there is no need to log errors
            return
        }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )

            for fileURL in fileURLs where fileURL.pathExtension == "log" {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let creationDate = attributes[.creationDate] as? Date,
                   creationDate < sevenDaysAgo {
                    try FileManager.default.removeItem(at: fileURL)
                }
            }
        } catch {
            Self.shared.error("Failed to cleanup old logs in \(directory.path): \(error)")
        }
    }

    // MARK: - Stringify Helper

    static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(double)
        case let bool as Bool:
            return String(bool)
        case let error as Error:
            return "Error: \(error.localizedDescription)"
        case let data as Data:
            return String(data: data, encoding: .utf8) ?? "<Data>"
        case let array as [Any]:
            // Optimization: Use NSMutableString to reduce temporary object creation
            // Limit the array length to avoid creating too many objects when dealing with very large arrays
            let maxElements = 100
            let result = NSMutableString()
            result.append("[")

            for (index, element) in array.prefix(maxElements).enumerated() {
                if index > 0 {
                    result.append(", ")
                }
                result.append(stringify(element))
            }

            if array.count > maxElements {
                result.append(", ... (\(array.count - maxElements) more)]")
            } else {
                result.append("]")
            }
            return result as String
        case let dict as [String: Any]:
            // Optimization: Use NSMutableString to reduce temporary object creation
            // Limit dictionary size to avoid creating too many objects when dealing with very large dictionaries
            let maxEntries = 50
            let result = NSMutableString()
            result.append("{")
            var count = 0

            for (key, value) in dict {
                if count >= maxEntries {
                    result.append(", ... (\(dict.count - maxEntries) more)")
                    break
                }
                if count > 0 {
                    result.append(", ")
                }
                result.append("\(key): ")
                result.append(stringify(value))
                count += 1
            }
            result.append("}")
            return result as String
        case let codable as Encodable:
            // Optimization: Limit JSON encoding size to avoid creating overly large strings
            let encoder = JSONEncoder()
            encoder.outputFormatting = [] // Not using prettyPrinted to reduce string size
            if let data = try? encoder.encode(AnyEncodable(codable)),
               let json = String(data: data, encoding: .utf8) {
                // Limit JSON string length
                let maxLength = 1000
                if json.count > maxLength {
                    return String(json.prefix(maxLength)) + "... (truncated)"
                }
                return json
            }
            return "\(codable)"
        default:
            return String(describing: value)
        }
    }
}

// Helper for encoding any Encodable
private struct AnyEncodable: Encodable {

    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
