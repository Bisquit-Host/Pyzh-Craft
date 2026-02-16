import SwiftUI

// MARK: - Error Level Enum

/// error level enum
enum ErrorLevel: String, CaseIterable {
    case popup,           // Pop-up window display
         notification, // Notification display
         silent,         // Silent processing, only logging
         disabled     // Do nothing, record nothing

    var displayName: String {
        switch self {
        case .popup: "弹窗"
        case .notification: "通知"
        case .silent: "静默"
        case .disabled: "无操作"
        }
    }
}

// MARK: - Global Error Types

/// Global error type enum
enum GlobalError: Error, LocalizedError, Identifiable {
    case network(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case fileSystem(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case authentication(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .popup
    )
    case validation(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case download(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case installation(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case gameLaunch(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .popup
    )
    case resource(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case player(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case configuration(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case unknown(
        chineseMessage: String,
        i18nKey: String,
        level: ErrorLevel = .silent
    )

    var id: String {
        switch self {
        case let .network(message, key, _):
            "network_\(key)_\(message.hashValue)"
        case let .fileSystem(message, key, _):
            "filesystem_\(key)_\(message.hashValue)"
        case let .authentication(message, key, _):
            "auth_\(key)_\(message.hashValue)"
        case let .validation(message, key, _):
            "validation_\(key)_\(message.hashValue)"
        case let .download(message, key, _):
            "download_\(key)_\(message.hashValue)"
        case let .installation(message, key, _):
            "installation_\(key)_\(message.hashValue)"
        case let .gameLaunch(message, key, _):
            "gameLaunch_\(key)_\(message.hashValue)"
        case let .resource(message, key, _):
            "resource_\(key)_\(message.hashValue)"
        case let .player(message, key, _):
            "player_\(key)_\(message.hashValue)"
        case let .configuration(message, key, _):
            "config_\(key)_\(message.hashValue)"
        case let .unknown(message, key, _):
            "unknown_\(key)_\(message.hashValue)"
        }
    }

    /// Chinese error description
    var chineseMessage: String {
        switch self {
        case let .network(message, _, _):
            message
        case let .fileSystem(message, _, _):
            message
        case let .authentication(message, _, _):
            message
        case let .validation(message, _, _):
            message
        case let .download(message, _, _):
            message
        case let .installation(message, _, _):
            message
        case let .gameLaunch(message, _, _):
            message
        case let .resource(message, _, _):
            message
        case let .player(message, _, _):
            message
        case let .configuration(message, _, _):
            message
        case let .unknown(message, _, _):
            message
        }
    }

    /// International key
    var i18nKey: String {
        switch self {
        case let .network(_, key, _):
            key
        case let .fileSystem(_, key, _):
            key
        case let .authentication(_, key, _):
            key
        case let .validation(_, key, _):
            key
        case let .download(_, key, _):
            key
        case let .installation(_, key, _):
            key
        case let .gameLaunch(_, key, _):
            key
        case let .resource(_, key, _):
            key
        case let .player(_, key, _):
            key
        case let .configuration(_, key, _):
            key
        case let .unknown(_, key, _):
            key
        }
    }

    /// error level
    var level: ErrorLevel {
        switch self {
        case let .network(_, _, level):
            level
        case let .fileSystem(_, _, level):
            level
        case let .authentication(_, _, level):
            level
        case let .validation(_, _, level):
            level
        case let .download(_, _, level):
            level
        case let .installation(_, _, level):
            level
        case let .gameLaunch(_, _, level):
            level
        case let .resource(_, _, level):
            level
        case let .player(_, _, level):
            level
        case let .configuration(_, _, level):
            level
        case let .unknown(_, _, level):
            level
        }
    }

    /// Localized error description (using internationalization key)
    var errorDescription: String? {
        LanguageManager.shared.bundle.localizedString(
            forKey: i18nKey,
            value: i18nKey,
            table: nil
        )
    }

    /// Localized description: Use i18nKey first, fall back to chineseMessage if not found
    var localizedDescription: String {
        let localizedText = LanguageManager.shared.bundle.localizedString(
            forKey: i18nKey,
            value: i18nKey,
            table: nil
        )

        // Always use localized content when there is a valid localized entry
        if localizedText != i18nKey {
            return localizedText
        }

        // When there is no corresponding localized entry, fallback to Chinese message
        return chineseMessage
    }

    /// Get notification title (using internationalization key)
    var notificationTitle: String {
        switch self {
        case .network:
            "Network Error"
        case .fileSystem:
            "File System Error"
        case .authentication:
            "Authentication Error"
        case .validation:
            "Validation Error"
        case .download:
            "Download Error"
        case .installation:
            "Installation Error"
        case .gameLaunch:
            "Game Launch Error"
        case .resource:
            "Resource Error"
        case .player:
            "Player Error"
        case .configuration:
            "Configuration Error"
        case .unknown:
            "Unknown Error"
        }
    }
}

// MARK: - Error Conversion Extensions

extension GlobalError {
    /// Convert from other error types to global errors
    static func from(_ error: Error) -> GlobalError {
        switch error {
        case let globalError as GlobalError:
            return globalError

        default:
            if let urlError = error as? URLError {
                // If it is a cancellation error, use the silent level and do not display notifications
                let level: ErrorLevel = urlError.code == .cancelled ? .silent : .notification
                return .network(
                    chineseMessage: urlError.localizedDescription,
                    i18nKey: "Network URL Error",
                    level: level
                )
            }

            // Check if it is a file system error
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain {
                return .fileSystem(
                    chineseMessage: nsError.localizedDescription,
                    i18nKey: "File System Error",
                    level: .notification
                )
            }

            return .unknown(
                chineseMessage: error.localizedDescription,
                i18nKey: "error.unknown.generic",
                level: .silent
            )
        }
    }
}

// MARK: - Global Error Handler

class GlobalErrorHandler: ObservableObject {
    static let shared = GlobalErrorHandler()

    @Published var currentError: GlobalError?
    @Published var errorHistory: [GlobalError] = []

    private let maxHistoryCount = 100

    private init() {}

    func handle(_ error: Error) {
        let globalError = GlobalError.from(error)
        handle(globalError)
    }

    func handle(_ globalError: GlobalError) {
        DispatchQueue.main.async {
            self.currentError = globalError
            self.addToHistory(globalError)
            self.logError(globalError)
            self.handleErrorByLevel(globalError)
        }
    }

    /// Handle errors based on error level
    private func handleErrorByLevel(_ error: GlobalError) {
        switch error.level {
        case .popup:
            Logger.shared.error("[GlobalError-Popup] \(error.chineseMessage)")

        case .notification:
            // Send notification
            NotificationManager.sendSilently(
                title: error.notificationTitle,
                body: error.localizedDescription
            )

        case .silent:
            // Silent processing, only logging
            Logger.shared.error("[GlobalError-Silent] \(error.chineseMessage)")

        case .disabled:
            // do nothing
            break
        }
    }

    /// Clear current errors
    func clearCurrentError() {
        DispatchQueue.main.async {
            self.currentError = nil
        }
    }

    /// Clear error history
    func clearHistory() {
        DispatchQueue.main.async {
            self.errorHistory.removeAll()
        }
    }

    /// Add error to history
    private func addToHistory(_ error: GlobalError) {
        errorHistory.append(error)

        // Limit the number of history records
        if errorHistory.count > maxHistoryCount {
            errorHistory.removeFirst()
        }
    }

    /// Clean memory when app exits
    func cleanup() {
        DispatchQueue.main.async {
            self.currentError = nil
            self.errorHistory.removeAll(keepingCapacity: false)
        }
    }

    /// Record errors to log
    private func logError(_ error: GlobalError) {
        Logger.shared.error("[GlobalError] \(error.chineseMessage) | Key: \(error.i18nKey) | Level: \(error.level.rawValue)")
    }
}

// MARK: - Error Handling View Modifier

struct GlobalErrorHandlerModifier: ViewModifier {
    @StateObject private var errorHandler = GlobalErrorHandler.shared

    func body(content: Content) -> some View {
        content
            .onReceive(errorHandler.$currentError) { error in
                if let error {
                    // Only logs are recorded, pop-up windows are handled by ErrorAlertModifier
                    Logger.shared.error("Global error occurred: \(error.chineseMessage)")
                }
            }
    }
}

// MARK: - View Extension

extension View {
    func globalErrorHandler() -> some View {
        modifier(GlobalErrorHandlerModifier())
    }
}

// MARK: - Convenience Methods

extension GlobalErrorHandler {
    static func network(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .network(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func fileSystem(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .fileSystem(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func authentication(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .popup) -> GlobalError {
        .authentication(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func validation(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .validation(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func download(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .download(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func installation(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .installation(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func gameLaunch(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .popup) -> GlobalError {
        .gameLaunch(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func resource(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .resource(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func player(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .player(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func configuration(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .configuration(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }

    static func unknown(_ chineseMessage: String, i18nKey: String, level: ErrorLevel = .silent) -> GlobalError {
        .unknown(chineseMessage: chineseMessage, i18nKey: i18nKey, level: level)
    }
}
