import SwiftUI

/// AI chat input area view
struct AIChatInputAreaView: View {
    @Binding var inputText: String
    @Binding var selectedGameId: String?
    @FocusState.Binding var isInputFocused: Bool
    let games: [GameVersionInfo]
    let isSending: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onAttachFile: () -> Void
    
    private enum Constants {
        static let inputFontSize: CGFloat = 14
        static let inputHorizontalPadding: CGFloat = 16
        static let inputVerticalPadding: CGFloat = 12
        static let messageSpacing: CGFloat = 16
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // game selector
            HStack(spacing: Constants.messageSpacing) {
                // Show Picker only if game list is not empty
                if !games.isEmpty {
                    gameSelector
                }
                attachFileButton
                textField
                sendButton
            }
            .padding(.horizontal, Constants.inputHorizontalPadding)
            .padding(.vertical, Constants.inputVerticalPadding)
        }
    }
    
    // MARK: - View Components
    
    private var selectedGame: GameVersionInfo? {
        guard let selectedGameId = selectedGameId else { return nil }
        return games.first { $0.id == selectedGameId }
    }
    
    private var gameSelector: some View {
        Menu {
            ForEach(games) { game in
                Button(game.gameName) {
                    selectedGameId = game.id
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let selectedGame = selectedGame {
                    Text(selectedGame.gameName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 50)
    }
    
    private var attachFileButton: some View {
        Button(action: onAttachFile) {
            Image(systemName: "paperclip")
                .font(.system(size: Constants.inputFontSize))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(isSending)
    }
    
    private var textField: some View {
        TextField("Type your message here...", text: $inputText, axis: .vertical)
            .textFieldStyle(.plain)
            .focused($isInputFocused)
            .lineLimit(1...6)
            .onSubmit {
                if canSend {
                    onSend()
                }
            }
            .disabled(isSending)
    }
    
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: Constants.inputFontSize))
                .foregroundStyle(canSend ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }
}
