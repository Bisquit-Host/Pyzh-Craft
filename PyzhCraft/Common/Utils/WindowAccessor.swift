import SwiftUI

/// SwiftUI component for accessing and manipulating underlying macOS NSWindow objects
struct WindowAccessor: NSViewRepresentable {
    var synchronous = false
    var callback: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = WindowAccessorView(callback: callback, synchronous: synchronous)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Also tries to get the window when updating (if not obtained before)
        if let accessorView = nsView as? WindowAccessorView, let window = nsView.window {
            accessorView.configureWindow(window)
        }
    }
}

/// Custom NSView is used to monitor window changes
private class WindowAccessorView: NSView {
    var callback: (NSWindow) -> Void
    var synchronous: Bool
    private var hasConfigured = false
    
    init(callback: @escaping (NSWindow) -> Void, synchronous: Bool) {
        self.callback = callback
        self.synchronous = synchronous
        super.init(frame: .zero)
    }
    
    /// Only used to load from xib/storyboard (this view is only created by code) to avoid crashing in the production environment
    required init?(coder: NSCoder) {
        self.callback = { _ in }
        self.synchronous = false
        super.init(coder: coder)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Configure the window immediately when the view is added to the window
        if let window = window, !hasConfigured {
            hasConfigured = true
            
            if synchronous {
                // Synchronous execution to avoid flickering caused by delays
                configureWindow(window)
            } else {
                // Asynchronous execution
                DispatchQueue.main.async { [weak self] in
                    self?.configureWindow(window)
                }
            }
        }
    }
    
    func configureWindow(_ window: NSWindow) {
        callback(window)
    }
}
