import SwiftUI

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
