import SwiftUI
import UserNotifications
import OSLog

// MARK: - Notification Center Delegate

final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// App receives notification when it is in the foreground and decides how to display it
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Allow displaying banners/lists in the foreground and playing sounds and updating logos
        completionHandler([.banner, .list, .sound, .badge])
    }
}

enum NotificationManager {

    /// Send notification
    /// - Parameters:
    ///   - title: notification title
    ///   - body: notification content
    /// - Throws: GlobalError when the operation fails
    static func send(title: String, body: String) throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        let semaphore = DispatchSemaphore(value: 0)
        var notificationError: Error?

        UNUserNotificationCenter.current().add(request) { error in
            notificationError = error
            semaphore.signal()
        }

        semaphore.wait()

        if let error = notificationError {
            Logger.shared.error("Error adding notification request: \(error.localizedDescription)")
            throw GlobalError.resource(
                i18nKey: "Notification Send Failed",
                level: .silent
            )
        }
    }

    /// Send notification (silent version, logs errors but does not throw exceptions on failure)
    /// - Parameters:
    ///   - title: notification title
    ///   - body: notification content
    static func sendSilently(title: String, body: String) {
        do {
            try send(title: title, body: body)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to send notification: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// Request notification permission
    /// - Throws: GlobalError when the operation fails
    static func requestAuthorization() async throws {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])

            if granted {
                Logger.shared.info("Notification permission granted")
            } else {
                Logger.shared.warning("User denied notification permission")
                throw GlobalError.configuration(
                    i18nKey: "Notification Permission Denied",
                    level: .notification
                )
            }
        } catch {
            Logger.shared.error("Error while requesting notification permission: \(error.localizedDescription)")
            if error is GlobalError {
                throw error
            } else {
                throw GlobalError.configuration(
                    i18nKey: "Notification Permission Request Failed",
                    level: .notification
                )
            }
        }
    }

    /// Request notification permission (silent version, logs an error but does not throw an exception on failure)
    static func requestAuthorizationIfNeeded() async {
        do {
            try await requestAuthorization()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("Failed to request notification permission: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
        }
    }

    /// - Returns: permission status
    static func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Check if you have notification permission
    /// - Returns: Do you have permission?
    static func hasAuthorization() async -> Bool {
        let status = await checkAuthorizationStatus()
        return status == .authorized
    }
}
