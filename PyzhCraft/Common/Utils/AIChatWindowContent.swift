import SwiftUI

/// AI chat window content view (used to observe WindowDataStore changes)
struct AIChatWindowContent: View {
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
