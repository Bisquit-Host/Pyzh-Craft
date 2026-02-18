import SwiftUI

/// Window style configuration tool
enum WindowStyleHelper {
    /// Configure standard window styles (disable shrink and zoom)
    static func configureStandardWindow(_ window: NSWindow) {
        window.styleMask.remove([.miniaturizable, .resizable])
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    /// 从工具栏右键菜单中移除「仅文字」选项，只保留「仅图标」与「文字和图标」
    static func disableToolbarTextOnlyMode(_ window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        // 使用 _toolbarView 访问工具栏视图以获取其上下文菜单（系统未公开允许的 display 模式 API）
        guard let toolbarView = toolbar.value(forKey: "_toolbarView") as? NSView,
              let menu = toolbarView.menu else { return }
        let textOnlyTag = 3 // 系统菜单中「仅文字」对应的 tag
        if let index = menu.items.firstIndex(where: { $0.action == NSSelectorFromString("changeToolbarDisplayMode:") && $0.tag == textOnlyTag }) {
            menu.removeItem(at: index)
        }
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
