import SwiftUI

// MARK: - Error Level Enum

/// error level enum
enum ErrorLevel: String, CaseIterable {
    case popup,         // Pop-up window display
         notification, // Notification display
         silent,      // Silent processing, only logging
         disabled    // Do nothing, record nothing
}

// MARK: - Global Error Types

/// Global error type enum
enum GlobalError: Error, LocalizedError, Identifiable {
    case network(
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case fileSystem(
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case authentication(
        i18nKey: String,
        level: ErrorLevel = .popup
    )
    case validation(
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case download(
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case installation(
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case gameLaunch(
        i18nKey: String,
        level: ErrorLevel = .popup
    )
    case resource(
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case player(
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case configuration(
        i18nKey: String,
        level: ErrorLevel = .notification
    )
    case unknown(
        i18nKey: String,
        level: ErrorLevel = .silent
    )

    var id: String {
        "\(typeIdentifier)_\(i18nKey)_\(level.rawValue)"
    }

    private var typeIdentifier: String {
        switch self {
        case .network: "network"
        case .fileSystem: "filesystem"
        case .authentication: "auth"
        case .validation: "validation"
        case .download: "download"
        case .installation: "installation"
        case .gameLaunch: "gameLaunch"
        case .resource: "resource"
        case .player: "player"
        case .configuration: "config"
        case .unknown: "unknown"
        }
    }

    /// Chinese error description
    var chineseMessage: String {
        localizedDescription
    }

    /// International key
    var i18nKey: String {
        switch self {
        case let .network(key, _): key
        case let .fileSystem(key, _): key
        case let .authentication(key, _): key
        case let .validation(key, _): key
        case let .download(key, _): key
        case let .installation(key, _): key
        case let .gameLaunch(key, _): key
        case let .resource(key, _): key
        case let .player(key, _): key
        case let .configuration(key, _): key
        case let .unknown(key, _): key
        }
    }

    /// error level
    var level: ErrorLevel {
        switch self {
        case let .network(_, level): level
        case let .fileSystem(_, level): level
        case let .authentication(_, level): level
        case let .validation(_, level): level
        case let .download(_, level): level
        case let .installation(_, level): level
        case let .gameLaunch(_, level): level
        case let .resource(_, level): level
        case let .player(_, level): level
        case let .configuration(_, level): level
        case let .unknown(_, level): level
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

    /// Localized description derived from the localization key
    var localizedDescription: String {
        LanguageManager.shared.bundle.localizedString(
            forKey: i18nKey,
            value: i18nKey,
            table: nil
        )
    }

    /// Get notification title (using internationalization key)
    var notificationTitle: String {
        switch self {
        case .network: "Network Error"
        case .fileSystem: "File System Error"
        case .authentication: "Authentication Error"
        case .validation: "Validation Error"
        case .download: "Download Error"
        case .installation: "Installation Error"
        case .gameLaunch: "Game Launch Error"
        case .resource: "Resource Error"
        case .player: "Player Error"
        case .configuration: "Configuration Error"
        case .unknown: "Unknown Error"
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
                    i18nKey: "Network URL Error",
                    level: level
                )
            }

            // Check if it is a file system error
            let nsError = error as NSError
            
            if nsError.domain == NSCocoaErrorDomain {
                return .fileSystem(
                    i18nKey: "File System Error",
                    level: .notification
                )
            }

            return .unknown(
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
    static func network(i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .network(i18nKey: i18nKey, level: level)
    }

    static func fileSystem(i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .fileSystem(i18nKey: i18nKey, level: level)
    }

    static func authentication(i18nKey: String, level: ErrorLevel = .popup) -> GlobalError {
        .authentication(i18nKey: i18nKey, level: level)
    }

    static func validation(i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .validation(i18nKey: i18nKey, level: level)
    }

    static func download(i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .download(i18nKey: i18nKey, level: level)
    }

    static func installation(i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .installation(i18nKey: i18nKey, level: level)
    }

    static func gameLaunch(i18nKey: String, level: ErrorLevel = .popup) -> GlobalError {
        .gameLaunch(i18nKey: i18nKey, level: level)
    }

    static func resource(i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .resource(i18nKey: i18nKey, level: level)
    }

    static func player(i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .player(i18nKey: i18nKey, level: level)
    }

    static func configuration(i18nKey: String, level: ErrorLevel = .notification) -> GlobalError {
        .configuration(i18nKey: i18nKey, level: level)
    }

    static func unknown(i18nKey: String, level: ErrorLevel = .silent) -> GlobalError {
        .unknown(i18nKey: i18nKey, level: level)
    }
}
