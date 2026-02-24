import SwiftUI
import Combine

/// Sidebar: Game list and resource list navigation
public struct SidebarView: View {
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var gameRepository: GameRepository
    @EnvironmentObject var gameLaunchUseCase: GameLaunchUseCase
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @State private var searchText = ""
    @State private var showDeleteAlert = false
    @State private var gameToDelete: GameVersionInfo?
    @State private var gameToExport: GameVersionInfo?
    @StateObject private var gameActionManager = GameActionManager.shared
    @StateObject private var gameStatusManager = GameStatusManager.shared
    @ObservedObject private var selectedGameManager = SelectedGameManager.shared
    @State private var iconRefreshTriggers: [String: UUID] = [:]
    @State private var cancellable: AnyCancellable?

    public init() {}

    public var body: some View {
        List(selection: detailState.selectedItemOptionalBinding) {
            Section(header: Text("Resource List")) {
                ForEach(ResourceType.allCases, id: \.self) { type in
                    NavigationLink(value: SidebarItem.resource(type)) {
                        HStack(spacing: 6) {
                            Image(systemName: type.systemImage)
                                .frame(width: 16, height: 16)
                                .foregroundColor(.secondary)
                            Text(type.localizedNameKey)
                        }
                    }
                }
            }

            Section(header: Text("Game List")) {
                ForEach(filteredGames) { game in
                    NavigationLink(value: SidebarItem.game(game.id)) {
                        HStack(spacing: 6) {
                            GameIconView(
                                game: game,
                                refreshTrigger: iconRefreshTriggers[game.gameName] ?? UUID()
                            )
                            Text(game.gameName)
                                .lineLimit(1)
                        }
                        .tag(game.id)
                    }
                    .contextMenu {
                        GameContextMenu(
                            game: game,
                            onDelete: { gameToDelete = game; showDeleteAlert = true },
                            onOpenServerSettings: {
                                WindowManager.shared.openWindow(id: .serverSettings)
                            },
                            onExport: {
                                gameToExport = game
                            }
                        )
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: Localized.Sidebar.Search.games)
        .safeAreaInset(edge: .bottom) {
            if !playerListViewModel.players.isEmpty {
                PlayerListView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            for game in gameRepository.games where iconRefreshTriggers[game.gameName] == nil {
                iconRefreshTriggers[game.gameName] = UUID()
            }
            cancellable = IconRefreshNotifier.shared.refreshPublisher
                .sink { refreshedGameName in
                    if let gameName = refreshedGameName {
                        iconRefreshTriggers[gameName] = UUID()
                    } else {
                        for game in gameRepository.games {
                            iconRefreshTriggers[game.gameName] = UUID()
                        }
                    }
                }
        }
        .onDisappear {
            cancellable?.cancel()
        }
        .onChange(of: gameRepository.games) { _, newGames in
            for game in newGames where iconRefreshTriggers[game.gameName] == nil {
                iconRefreshTriggers[game.gameName] = UUID()
            }
        }
        .confirmationDialog(
            "Delete Game Version",
            isPresented: $showDeleteAlert,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let gameToDelete {
                    gameActionManager.deleteGame(
                        game: gameToDelete,
                        gameRepository: gameRepository,
                        selectedItem: detailState.selectedItemBinding,
                        gameType: detailState.gameTypeBinding
                    )
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let gameToDelete {
                Text("Are you sure you want to delete the game \"\(gameToDelete.gameName)\" and all its data? (This will take a very long time)")
            }
        }
        .sheet(item: $gameToExport) { game in
            ModPackExportSheet(gameInfo: game)
        }
    }

    private var filteredGames: [GameVersionInfo] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return gameRepository.games
        }

        let lower = searchText.lowercased()
        return gameRepository.games.filter { $0.gameName.lowercased().contains(lower) }
    }
}
