import SwiftUI

/// Theme manager: responsible for theme mode, appearance application, and system appearance monitoring
/// Decoupled from GeneralSettingsManager to avoid non-theme setting changes triggering root view reconstruction
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @AppStorage("themeMode")
    var themeMode: ThemeMode = .system {
        didSet {
            applyAppAppearance()
            objectWillChange.send()
        }
    }
    
    private var appearanceObserver: NSKeyValueObservation?
    private var debounceWorkItem: DispatchWorkItem?
    
    private init() {
        DispatchQueue.main.async { [weak self] in
            self?.applyAppAppearance()
            self?.setupAppearanceObserver()
        }
    }
    
    deinit {
        appearanceObserver?.invalidate()
        debounceWorkItem?.cancel()
    }
    
    /// When the theme mode is system, return the current theme of the system
    var currentColorScheme: ColorScheme? {
        guard NSApplication.shared.isRunning else {
            return themeMode == .system ? nil : themeMode.effectiveColorScheme
        }
        return themeMode.effectiveColorScheme
    }
    
    /// Set system appearance change observer (debounce reduces trigger frequency)
    private func setupAppearanceObserver() {
        appearanceObserver = NSApp.observe(
            \.effectiveAppearance,
             options: [.new, .initial]
        ) { [weak self] _, _ in
            guard let self else { return }
            self.debounceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.themeMode == .system else { return }
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
            self.debounceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        }
    }
    
    /// Apply global AppKit appearance based on theme settings (affects AppKit UI such as Sparkle)
    func applyAppAppearance() {
        let appearance = themeMode.nsAppearance
        if Thread.isMainThread {
            NSApp.appearance = appearance
        } else {
            DispatchQueue.main.async {
                NSApp.appearance = appearance
            }
        }
    }
}
