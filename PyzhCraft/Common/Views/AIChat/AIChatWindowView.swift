import SwiftUI
import UniformTypeIdentifiers

/// AI conversation window view
struct AIChatWindowView: View {
    @ObservedObject var chatState: ChatState
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @EnvironmentObject var gameRepository: GameRepository
    @StateObject private var aiSettings = AISettingsManager.shared
    @StateObject private var attachmentManager = AIChatAttachmentManager()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var selectedGameId: String?
    @State private var showFilePicker = false
    
    // Cache avatar view to avoid reloading every time message is updated
    @State private var cachedAIAvatar: AnyView?
    @State private var cachedUserAvatar: AnyView?
    
    // MARK: - Constants
    private enum Constants {
        static let avatarSize: CGFloat = 32
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Message list
            AIChatMessageListView(
                chatState: chatState,
                currentPlayer: playerListViewModel.currentPlayer,
                cachedAIAvatar: cachedAIAvatar,
                cachedUserAvatar: cachedUserAvatar,
                aiAvatarURL: aiSettings.aiAvatarURL
            )
            
            Divider()
            
            // Preview of attachments to be sent
            if !attachmentManager.pendingAttachments.isEmpty {
                AIChatAttachmentPreviewView(
                    attachments: attachmentManager.pendingAttachments
                ) { index in
                    attachmentManager.removeAttachment(at: index)
                }
            }
            
            // input area
            AIChatInputAreaView(
                inputText: $inputText,
                selectedGameId: $selectedGameId,
                isInputFocused: $isInputFocused,
                games: gameRepository.games,
                isSending: chatState.isSending,
                canSend: canSend,
                onSend: sendMessage
            ) {
                showFilePicker = true
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.text, .pdf, .json, .plainText, .log],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
        .fileDialogDefaultDirectory(
            selectedGame.map { AppPaths.profileDirectory(gameName: $0.gameName) } ?? FileManager.default.homeDirectoryForCurrentUser
        )
        .onAppear {
            isInputFocused = true
            // The first game is selected by default
            if selectedGameId == nil && !gameRepository.games.isEmpty {
                selectedGameId = gameRepository.games.first?.id
            }
            // Initialize avatar cache
            initializeAvatarCache()
        }
        .onChange(of: gameRepository.games) { _, newGames in
            // When the game list is loaded and no game is selected, the first game is automatically selected
            if selectedGameId == nil && !newGames.isEmpty {
                selectedGameId = newGames.first?.id
            }
        }
        .onChange(of: playerListViewModel.currentPlayer?.id) { _, _ in
            // When the current player changes, update the user avatar cache (only monitor ID changes to reduce unnecessary updates)
            updateUserAvatarCache()
        }
        .onChange(of: aiSettings.aiAvatarURL) { oldValue, newValue in
            // Update the AI ​​avatar cache when the AI ​​avatar URL changes (only updates when the URL actually changes)
            if oldValue != newValue {
                updateAIAvatarCache()
            }
        }
        .onDisappear {
            // Clear all data after closing the page
            clearAllData()
        }
    }
    
    // MARK: - Computed Properties
    
    private var selectedGame: GameVersionInfo? {
        guard let selectedGameId = selectedGameId else { return nil }
        return gameRepository.games.first { $0.id == selectedGameId }
    }
    
    private var canSend: Bool {
        !chatState.isSending && (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachmentManager.pendingAttachments.isEmpty)
    }
    
    // MARK: - Methods
    
    /// Initialize avatar cache
    private func initializeAvatarCache() {
        // Initialize AI avatar (using URL from settings)
        updateAIAvatarCache()
        
        // Initialize user avatar
        updateUserAvatarCache()
    }
    
    /// Update AI avatar cache
    private func updateAIAvatarCache() {
        cachedAIAvatar = AnyView(
            AIAvatarView(size: Constants.avatarSize, url: aiSettings.aiAvatarURL)
        )
    }
    
    /// Update user avatar cache
    private func updateUserAvatarCache() {
        if let player = playerListViewModel.currentPlayer {
            cachedUserAvatar = AnyView(
                MinecraftSkinUtils(
                    type: player.isOnlineAccount ? .url : .asset,
                    src: player.avatarName,
                    size: Constants.avatarSize
                )
            )
        } else {
            cachedUserAvatar = AnyView(
                Image(systemName: "person.fill")
                    .font(.system(size: Constants.avatarSize))
                    .foregroundStyle(.secondary)
            )
        }
    }
    
    /// Clear avatar cache
    private func clearAvatarCache() {
        cachedAIAvatar = nil
        cachedUserAvatar = nil
    }
    
    /// Clear all data on the page
    private func clearAllData() {
        // Clear avatar cache
        clearAvatarCache()
        // Clean input text and attachments
        inputText = ""
        attachmentManager.clearAll()
        // Reset focus state
        isInputFocused = false
        // Clear selected games
        selectedGameId = nil
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        
        let attachments = attachmentManager.pendingAttachments
        inputText = ""
        attachmentManager.clearAll()
        
        Task {
            await AIChatManager.shared.sendMessage(text, attachments: attachments, chatState: chatState)
        }
    }
    
    /// Process file selection results
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            attachmentManager.handleFileSelection(urls)
        case .failure(let error):
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
        }
    }
}
