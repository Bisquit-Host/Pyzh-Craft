import SwiftUI

/// Window style configuration tool
enum WindowStyleHelper {
    /// Configure standard window styles (disable shrink and zoom)
    static func configureStandardWindow(_ window: NSWindow) {
        window.styleMask.remove([.miniaturizable, .resizable])
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }
}

/// Window style configuration modifiers
struct WindowStyleConfig: ViewModifier {
    let windowID: WindowID

    func body(content: Content) -> some View {
        content
            .background(
                WindowAccessor(synchronous: false) { window in
                    // Make sure the window identifier is set correctly (for singleton lookup)
                    if window.identifier?.rawValue != windowID.rawValue {
                        window.identifier = NSUserInterfaceItemIdentifier(windowID.rawValue)
                    }

                    // Uniform use of standard window styles
                    WindowStyleHelper.configureStandardWindow(window)
                }
            )
    }
}

extension View {
    /// Apply window style configuration
    func windowStyleConfig(for windowID: WindowID) -> some View {
        modifier(WindowStyleConfig(windowID: windowID))
    }
}

/// window cleanup modifier
struct WindowCleanup: ViewModifier {
    let windowID: WindowID

    func body(content: Content) -> some View {
        content
            .onDisappear {
                WindowDataStore.shared.cleanup(for: windowID)
            }
    }
}

extension View {
    /// Apply window cleaning configuration
    func windowCleanup(for windowID: WindowID) -> some View {
        modifier(WindowCleanup(windowID: windowID))
    }
}
