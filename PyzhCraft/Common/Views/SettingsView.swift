import SwiftUI

/// Set tab enumeration
enum SettingsTab: Int {
    case general = 0
    case game = 1
    case advanced = 2
    case ai = 3
}

/// Common settings view
/// Apply settings
public struct SettingsView: View {
    @StateObject private var general = GeneralSettingsManager.shared
    @StateObject private var selectedGameManager = SelectedGameManager.shared
    @EnvironmentObject private var gameRepository: GameRepository
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
            GameAdvancedSettingsView()
                .tabItem {
                    Label(
                        "Advanced",
                        systemImage: "gearshape.2"
                    )
                }
                .tag(SettingsTab.advanced)
                .disabled(selectedGameManager.selectedGameId == nil)
        }
        .padding()
        .onChange(of: selectedGameManager.shouldOpenAdvancedSettings) { _, shouldOpen in
            // When the flag is set (when the window is open), switch to the Advanced Settings tab
            if shouldOpen {
                checkAndOpenAdvancedSettings()
            }
        }
        .onAppear {
            // When the settings window first opens, switch to the advanced settings tab if the flag is already set
            // This happens when the settings button is clicked when the window is not open
            checkAndOpenAdvancedSettings()
        }
    }

    private func checkAndOpenAdvancedSettings() {
        if selectedGameManager.shouldOpenAdvancedSettings && selectedGameManager.selectedGameId != nil {
            selectedTab = .advanced
            selectedGameManager.shouldOpenAdvancedSettings = false
        }
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
