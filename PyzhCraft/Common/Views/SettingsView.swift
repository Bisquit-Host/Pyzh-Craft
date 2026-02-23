import SwiftUI

/// Set tab enumeration
enum SettingsTab: Int {
    case general = 0
    case game = 1
    case ai = 2
}

/// Common settings view
/// Apply settings
public struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
            GameSettingsView()
                .tabItem {
                    Label("Game", systemImage: "gamecontroller")
                }
                .tag(SettingsTab.game)
            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "brain")
                }
                .tag(SettingsTab.ai)
        }
        .padding()
    }
}

struct CustomLabeledContentStyle: LabeledContentStyle {
    let alignment: VerticalAlignment

    init(alignment: VerticalAlignment = .center) {
        self.alignment = alignment
    }

    // Preserve system layout
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: alignment) {
            // Use system label layout
            HStack(spacing: 0) {
                configuration.label
                Text(":")
            }
            .layoutPriority(1)  // Keep label priority
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 320, alignment: .trailing)  // Container aligned right
            // Right content
            configuration.content
                .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)  // Text left aligned
                .frame(maxWidth: .infinity, alignment: .leading)  // Container left aligned
        }
        .padding(.vertical, 4)
    }
}

// Use extensions to avoid breaking layout
extension LabeledContentStyle where Self == CustomLabeledContentStyle {
    static var custom: Self { .init() }

    static func custom(alignment: VerticalAlignment) -> Self {
        .init(alignment: alignment)
    }
}

#Preview {
    SettingsView()
}
