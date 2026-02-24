import SwiftUI

func newErrorView(_ error: GlobalError) -> some View {
    ContentUnavailableView {
        Label("😩 Query error, please try again later!", systemImage: "xmark.icloud")
    } description: {
        Text(error.notificationTitle)
    }
}

func emptyResultView() -> some View {
    ContentUnavailableView {
        Label(
            "No Results Found",
            systemImage: "magnifyingglass"
        )
    }
}

func emptyDropBackground() -> some View {
    RoundedRectangle(cornerRadius: 12)
        .fill(.gray.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .foregroundColor(.secondary.opacity(0.5))
        )
}

func spacerView() -> some View {
    Spacer().frame(maxHeight: 20)
}

// path setting line
struct DirectorySettingRow: View {
    private let title: String
    private let path: String
    private let description: String?
    private let onChoose: () -> Void
    private let onReset: () -> Void
    
    init(title: String, path: String, description: String? = nil, onChoose: @escaping () -> Void, onReset: @escaping () -> Void, showPopover: Bool = false) {
        self.title = title
        self.path = path
        self.description = description
        self.onChoose = onChoose
        self.onReset = onReset
        self.showPopover = showPopover
    }
    
    @State private var showPopover = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onChoose) {
                    PathBreadcrumbView(path: path)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                Button("Reset", action: onReset)
                    .padding(.leading, 8)
            }
            
            if let description {
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}
// Path segment display control (Finder style icon)
struct PathBreadcrumbView: View {
    let path: String
    let maxVisible: Int = 3  // Maximum number of paragraphs to display (including first and last paragraphs)
    
    var body: some View {
        let components = path.split(separator: "/").map(String.init)
        let paths: [String] = {
            var result: [String] = []
            var current = path.hasPrefix("/") ? "/" : ""
            for comp in components {
                // Use string interpolation instead of string concatenation
                let separator = current == "/" ? "" : "/"
                current = "\(current)\(separator)\(comp)"
                result.append(current)
            }
            return result
        }()
        
        let count = components.count
        let showEllipsis = count > maxVisible
        let headCount = showEllipsis ? 1 : max(0, count - maxVisible)
        let tailCount = showEllipsis ? maxVisible - 1 : count
        let startTail = max(count - tailCount, headCount)
        
        func segmentView(idx: Int) -> some View {
            // Securely obtain file icons and avoid NSXPC warnings
            let icon: NSImage = {
                // Check if the file exists
                guard FileManager.default.fileExists(atPath: paths[idx]) else {
                    if #available(macOS 12, *) {
                        return NSWorkspace.shared.icon(for: .folder)
                    } else {
                        return NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(0))
                    }
                }
                // Use try-catch wrapper to avoid potential NSXPC warnings
                return NSWorkspace.shared.icon(forFile: paths[idx])
            }()
            return HStack(spacing: 2) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(3)
                Text(components[idx])
                    .font(.body)
            }
        }
        
        return HStack(spacing: 0) {
            // beginning
            ForEach(0..<headCount, id: \.self) { idx in
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                }
                
                segmentView(idx: idx)
            }
            // Ellipsis
            if showEllipsis {
                if headCount > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                }
                
                Text("…")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            // ending
            ForEach(startTail..<count, id: \.self) { idx in
                if idx > headCount || (showEllipsis && idx == startTail) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                }
                if idx == count - 1 {
                    segmentView(idx: idx)
                } else {
                    segmentView(idx: idx)
                }
            }
        }
    }
}

// MARK: - Extension
extension View {
    @ViewBuilder
    func applyReplaceTransition() -> some View {
        if #available(macOS 15.0, *) {
            self.contentTransition(.symbolEffect(.replace.magic(fallback: .offUp.byLayer), options: .nonRepeating))
        } else {
            self.contentTransition(.symbolEffect(.replace.offUp.byLayer, options: .nonRepeating))
        }
    }
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
extension Scene {
    func conditionalRestorationBehavior() -> some Scene {
        if #available(macOS 15.0, *) {
            return self.restorationBehavior(.disabled)
        } else {
            return self
        }
    }
    
    /// Disable window recovery behavior (on all supported macOS versions)
    func applyRestorationBehaviorDisabled() -> some Scene {
        if #available(macOS 15.0, *) {
            return self.restorationBehavior(.disabled)
        } else {
            return self
        }
    }
}

// MARK: - Universal information icon component (with Popover)
/// A universal question mark component that displays detailed instructions when the mouse is hovering
struct InfoIconWithPopover<Content: View>: View {
    /// What appears in the Popover
    let content: Content
    /// icon size
    let iconSize: CGFloat
    /// Delay display time (seconds)
    let delay: Double
    
    @State private var isHovering = false
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?
    
    init(
        iconSize: CGFloat = 14,
        delay: Double = 0.5,
        @ViewBuilder content: () -> Content
    ) {
        self.iconSize = iconSize
        self.delay = delay
        self.content = content()
    }
    
    var body: some View {
        Button {
            // Also show popover when clicked
            showPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: iconSize))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            // Cancel previous task
            hoverTask?.cancel()
            
            if hovering {
                // Delay the display of popover to avoid frequent display when the mouse moves quickly
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    if !Task.isCancelled && isHovering {
                        await MainActor.run {
                            showPopover = true
                        }
                    }
                }
            } else {
                showPopover = false
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            content
                .padding()
                .frame(maxWidth: 400, maxHeight: .infinity)
                .fixedSize(horizontal: true, vertical: true)
        }
        .onDisappear {
            hoverTask?.cancel()
            showPopover = false
        }
    }
}

// MARK: - Convenience initialization method (using strings)
extension InfoIconWithPopover {
    /// Convenience initialization method for creating InfoIconWithPopover using string literals
    init(
        text: LocalizedStringKey,
        iconSize: CGFloat = 14,
        delay: Double = 0.5
    ) where Content == AnyView {
        self.init(iconSize: iconSize, delay: delay) {
            AnyView(
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            )
        }
    }
}

struct HelpButton: NSViewRepresentable {
    var action: () -> Void
    
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .helpButton
        button.title = ""
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked)
        return button
    }
    
    func updateNSView(_ nsView: NSButton, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }
    
    class Coordinator: NSObject {
        let action: () -> Void
        
        init(action: @escaping () -> Void) {
            self.action = action
        }
        
        @objc func clicked() {
            action()
        }
    }
}
