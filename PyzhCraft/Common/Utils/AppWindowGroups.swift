import SwiftUI

/// Apply window group definition
extension PyzhCraftApp {
    /// Create all application window groups
    @SceneBuilder
    func appWindowGroups() -> some Scene {
        // Contributor window
        Window("about.contributors".localized(), id: WindowID.contributors.rawValue) {
            AboutView(showingAcknowledgements: false)
                .environmentObject(generalSettingsManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .windowStyleConfig(for: .contributors)
                .windowCleanup(for: .contributors)
        }
        .defaultSize(width: 280, height: 600)

        // acknowledgment window
        Window("about.acknowledgements".localized(), id: WindowID.acknowledgements.rawValue) {
            AboutView(showingAcknowledgements: true)
                .environmentObject(generalSettingsManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .windowStyleConfig(for: .acknowledgements)
                .windowCleanup(for: .acknowledgements)
        }
        .defaultSize(width: 280, height: 600)

        // AI chat window
        Window("ai.assistant.title".localized(), id: WindowID.aiChat.rawValue) {
            AIChatWindowContent()
                .environmentObject(playerListViewModel)
                .environmentObject(gameRepository)
                .environmentObject(generalSettingsManager)
                .windowStyleConfig(for: .aiChat)
                .windowCleanup(for: .aiChat)
        }
        .defaultSize(width: 500, height: 600)

        // Java download window
        Window("global_resource.download".localized(), id: WindowID.javaDownload.rawValue) {
            JavaDownloadProgressWindow(downloadState: JavaDownloadManager.shared.downloadState)
                .windowStyleConfig(for: .javaDownload)
                .windowCleanup(for: .javaDownload)
        }
        .defaultSize(width: 400, height: 100)

        // Skin preview window
        Window("skin.preview".localized(), id: WindowID.skinPreview.rawValue) {
            SkinPreviewWindowContent()
                .windowStyleConfig(for: .skinPreview)
                .windowCleanup(for: .skinPreview)
        }
        .defaultSize(width: 1200, height: 800)
    }
}

// MARK: - window content view

/// AI chat window content view (used to observe WindowDataStore changes)
private struct AIChatWindowContent: View {
    @ObservedObject private var windowDataStore = WindowDataStore.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @EnvironmentObject var gameRepository: GameRepository
    @EnvironmentObject var generalSettingsManager: GeneralSettingsManager

    var body: some View {
        Group {
            if let chatState = windowDataStore.aiChatState {
                AIChatWindowView(chatState: chatState)
                    .preferredColorScheme(themeManager.currentColorScheme)
            } else {
                EmptyView()
            }
        }
    }
}

/// Skin preview window content view (used to observe WindowDataStore changes)
private struct SkinPreviewWindowContent: View {
    @ObservedObject private var windowDataStore = WindowDataStore.shared

    var body: some View {
        Group {
            if let data = windowDataStore.skinPreviewData {
                SkinPreviewWindowView(
                    skinImage: data.skinImage,
                    skinPath: data.skinPath,
                    capeImage: data.capeImage,
                    playerModel: data.playerModel
                )
            } else {
                EmptyView()
            }
        }
    }
}
