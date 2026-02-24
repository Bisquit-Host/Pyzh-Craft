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
