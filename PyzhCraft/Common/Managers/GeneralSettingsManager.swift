import SwiftUI
import Combine

/// Main interface layout style: Classic (list on the left, content on the right) / Focus (content on the left, list on the right)
public enum InterfaceLayoutStyle: String, CaseIterable {
    case classic,   // classic
         focused  // focus
    
    public var localizedName: LocalizedStringKey {
        switch self {
        case .classic: "Classic"
        case .focused: "Focused"
        }
    }
}

public enum ThemeMode: String, CaseIterable {
    case light, dark, system
    
    public var localizedName: LocalizedStringKey {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Follow System"
        }
    }
    
    public var effectiveColorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
            
        case .dark:
            return .dark
            
        case .system:
            // Safely access system skins on the main thread
            if Thread.isMainThread {
                // Use NSApplication.shared instead of NSApp, safer
                let appearance = NSApplication.shared.effectiveAppearance
                let bestMatch = appearance.bestMatch(from: [.aqua, .darkAqua])
                return bestMatch == .darkAqua ? .dark : .light
            } else {
                // If not in the main thread, return to the default light theme
                return .light
            }
        }
    }
    
    /// Corresponding AppKit skin, used to affect AppKit-based UI (such as Sparkle)
    public var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }
}

class GeneralSettingsManager: ObservableObject, WorkingPathProviding {
    static let shared = GeneralSettingsManager()
    
    /// Whether to enable GitHub proxy (enabled by default)
    @AppStorage("enableGitHubProxy")
    var enableGitHubProxy = true {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("gitProxyURL")
    var gitProxyURL = "https://gh-proxy.com" {
        didSet { objectWillChange.send() }
    }
    
    // MARK: - Apply settings properties
    @AppStorage("concurrentDownloads")
    var concurrentDownloads: Int = 64 {
        didSet {
            if concurrentDownloads < 1 {
                concurrentDownloads = 1
            }
            objectWillChange.send()
        }
    }
    
    // New: Launcher working directory
    @AppStorage("launcherWorkingDirectory")
    var launcherWorkingDirectory: String = AppPaths.launcherSupportDirectory.path {
        didSet { objectWillChange.send() }
    }
    
    /// Interface style: Classic (list | content) / Focus (content | list)
    @AppStorage("interfaceLayoutStyle")
    var interfaceLayoutStyle: InterfaceLayoutStyle = .classic {
        didSet { objectWillChange.send() }
    }
    
    private init() {}
    
    /// Current launcher working directory (WorkingPathProviding)
    /// Use default support directory when empty
    var currentWorkingPath: String {
        launcherWorkingDirectory.isEmpty ? AppPaths.launcherSupportDirectory.path : launcherWorkingDirectory
    }
    
    var workingPathWillChange: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }
}
