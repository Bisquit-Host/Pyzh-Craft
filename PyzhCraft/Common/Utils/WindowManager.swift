import SwiftUI

/// Window manager for opening and closing windows (with Window, all windows are singletons)
@MainActor
class WindowManager {
    static let shared = WindowManager()

    private var openWindowAction: ((String) -> Void)?

    private init() {}

    /// Set the window opening action (called by WindowOpener)
    func setOpenWindowAction(_ action: @escaping (String) -> Void) {
        self.openWindowAction = action
    }

    /// Find the window with the specified ID
    private func findWindow(id: WindowID) -> NSWindow? {
        let windows = NSApplication.shared.windows
        for window in windows {
            // Find a matching window by its identifier
            if let identifier = window.identifier?.rawValue,
               identifier == id.rawValue {
                return window
            }
        }
        return nil
    }

    /// Open the window with the specified ID (Window itself is a singleton and will automatically activate existing windows)
    func openWindow(id: WindowID) {
        if let openWindow = openWindowAction {
            // Use OpenWindowAction to open the window (Window will automatically handle the singleton logic)
            openWindow(id.rawValue)
        } else {
            // If not set, notify the main view through the notification center
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenWindow"),
                object: nil,
                userInfo: ["windowID": id.rawValue]
            )
        }
    }

    /// Close the window with the specified ID
    func closeWindow(id: WindowID) {
        if let window = findWindow(id: id) {
            window.close()
        }
    }
}

/// Window opener modifier for setting a global OpenWindowAction in the main view
struct WindowOpener: ViewModifier {
    @Environment(\.openWindow)
    private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Set the global window opening action (use closure to wrap OpenWindowAction)
                WindowManager.shared.setOpenWindowAction { windowID in
                    openWindow(id: windowID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenWindow"))) { notification in
                // Listen for notifications and open a window (alternative solution)
                if let windowIDString = notification.userInfo?["windowID"] as? String {
                    openWindow(id: windowIDString)
                }
            }
    }
}

extension View {
    /// Application window opener configuration
    func windowOpener() -> some View {
        modifier(WindowOpener())
    }
}
