import SwiftUI

struct ServerSettingsWindowView: View {
    @EnvironmentObject private var gameRepository: GameRepository
    @StateObject private var selectedGameManager = SelectedGameManager.shared
    
    private var gameSelectionLabel: String {
        if gameRepository.games.isEmpty {
            return "No games"
        }
        return "Select game"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Game")
                    .font(.headline)
                
                Picker("Game", selection: $selectedGameManager.selectedGameId) {
                    Text(gameSelectionLabel)
                        .tag(nil as String?)
                    
                    ForEach(gameRepository.games) {
                        Text($0.gameName)
                            .tag(Optional($0.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            
            Divider()
            
            if selectedGameManager.selectedGameId == nil {
                ContentUnavailableView(
                    "No Game Selected",
                    systemImage: "server.rack",
                    description: Text("Select a game to edit advanced server settings")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GameAdvancedSettingsView()
            }
        }
        .padding()
        .onAppear {
            ensureValidSelection()
        }
        .onChange(of: gameRepository.games) {
            ensureValidSelection()
        }
    }
    
    private func ensureValidSelection() {
        guard let selectedGameId = selectedGameManager.selectedGameId else {
            selectedGameManager.setSelectedGame(gameRepository.games.first?.id)
            return
        }
        
        if gameRepository.getGame(by: selectedGameId) == nil {
            selectedGameManager.setSelectedGame(gameRepository.games.first?.id)
        }
    }
}
