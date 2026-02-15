import SwiftUI
import Combine

/// Sidebar: Game list and resource list navigation
public struct SidebarView: View {
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var gameRepository: GameRepository
    @EnvironmentObject var gameLaunchUseCase: GameLaunchUseCase
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @State private var searchText: String = ""
    @State private var showDeleteAlert: Bool = false
    @State private var gameToDelete: GameVersionInfo?
    @State private var gameToExport: GameVersionInfo?
    @StateObject private var gameActionManager = GameActionManager.shared
    @StateObject private var gameStatusManager = GameStatusManager.shared
    @ObservedObject private var selectedGameManager = SelectedGameManager.shared
    @State private var iconRefreshTriggers: [String: UUID] = [:]
    @State private var cancellable: AnyCancellable?

    @Environment(\.openSettings)
    private var openSettings

    public init() {}

    public var body: some View {
        List(selection: detailState.selectedItemOptionalBinding) {
            // Resources section
            Section(header: Text("sidebar.resources.title".localized())) {
                ForEach(ResourceType.allCases, id: \.self) { type in
                    NavigationLink(value: SidebarItem.resource(type)) {
                        HStack(spacing: 6) {
                            Image(systemName: type.systemImage)
                                .frame(width: 16, height: 16)
                                .foregroundColor(.secondary)
                            Text(type.localizedName)
                        }
                    }
                }
            }

            // game section
            Section(header: Text("sidebar.games.title".localized())) {
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
                            onOpenSettings: { openSettings() },
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
            // Show player list (if there are players)
            if !playerListViewModel.players.isEmpty {
                PlayerListView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            // Initialize refresh triggers for all games
            for game in gameRepository.games where iconRefreshTriggers[game.gameName] == nil {
                iconRefreshTriggers[game.gameName] = UUID()
            }
            // Listen for icon refresh notifications
            cancellable = IconRefreshNotifier.shared.refreshPublisher
                .sink { refreshedGameName in
                    if let gameName = refreshedGameName {
                        // Refresh the icon for a specific game
                        iconRefreshTriggers[gameName] = UUID()
                    } else {
                        // Refresh icons for all games
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
            // Initialize refresh triggers for new games when the game list changes
            for game in newGames where iconRefreshTriggers[game.gameName] == nil {
                iconRefreshTriggers[game.gameName] = UUID()
            }
        }
        .confirmationDialog(
            "delete.title".localized(),
            isPresented: $showDeleteAlert,
            titleVisibility: .visible
        ) {
            Button("common.delete".localized(), role: .destructive) {
                if let game = gameToDelete {
                    gameActionManager.deleteGame(
                        game: game,
                        gameRepository: gameRepository,
                        selectedItem: detailState.selectedItemBinding,
                        gameType: detailState.gameTypeBinding
                    )
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("common.cancel".localized(), role: .cancel) {}
        } message: {
            if let game = gameToDelete {
                Text(
                    String(format: "delete.game.confirm".localized(), game.gameName)
                )
            }
        }
        .sheet(item: $gameToExport) { game in
            ModPackExportSheet(gameInfo: game)
        }
    }

    // Only perform fuzzy search on game name
    private var filteredGames: [GameVersionInfo] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return gameRepository.games
        }
        let lower = searchText.lowercased()
        return gameRepository.games.filter { $0.gameName.lowercased().contains(lower) }
    }
}

// MARK: - Game Icon View

/// Game icon view component, supports icon refresh
private struct GameIconView: View {
    let game: GameVersionInfo
    let refreshTrigger: UUID

    /// Get icon URL (add refresh trigger as query parameter, force AsyncImage to reload)
    private var iconURL: URL {
        let profileDir = AppPaths.profileDirectory(gameName: game.gameName)
        let baseURL = profileDir.appendingPathComponent(game.gameIcon)
        // Add a refresh trigger as a query parameter to ensure that the file can be reloaded after updating
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "refresh", value: refreshTrigger.uuidString)]
        return components?.url ?? baseURL
    }

    var body: some View {
        Group {
            if FileManager.default.fileExists(atPath: profileDir.appendingPathComponent(game.gameIcon).path) {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().controlSize(.mini)
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    case .failure:
                        Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 20, height: 29)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(width: 20, height: 20, alignment: .center)
    }

    private var profileDir: URL {
        AppPaths.profileDirectory(gameName: game.gameName)
    }
}

// MARK: - Game Context Menu

/// Game right-click menu component to optimize memory usage
/// Use independent view components and cached state to reduce memory usage
private struct GameContextMenu: View {
    let game: GameVersionInfo
    let onDelete: () -> Void
    let onOpenSettings: () -> Void
    let onExport: () -> Void

    @ObservedObject private var gameStatusManager = GameStatusManager.shared
    @ObservedObject private var gameActionManager = GameActionManager.shared
    @ObservedObject private var selectedGameManager = SelectedGameManager.shared
    @EnvironmentObject private var playerListViewModel: PlayerListViewModel
    @EnvironmentObject private var gameRepository: GameRepository
    @EnvironmentObject private var gameLaunchUseCase: GameLaunchUseCase

    /// Use cached game state to avoid checking the process every render
    /// This is more efficient than calling isGameRunning() because it reads the cached state directly
    private var isRunning: Bool {
        gameStatusManager.allGameStates[game.id] ?? false
    }

    var body: some View {
        Button(action: {
            toggleGameState()
        }, label: {
            Label(
                isRunning ? "stop.fill".localized() : "play.fill".localized(),
                systemImage: isRunning ? "stop.fill" : "play.fill"
            )
        })

        Button(action: {
            gameActionManager.showInFinder(game: game)
        }, label: {
            Label("sidebar.context_menu.show_in_finder".localized(), systemImage: "folder")
        })

        Button(action: {
            selectedGameManager.setSelectedGameAndOpenAdvancedSettings(game.id)
            onOpenSettings()
        }, label: {
            Label("settings.game.advanced.tab".localized(), systemImage: "gearshape")
        })

        Divider()

        Button(action: onExport) {
            Label("modpack.export.button".localized(), systemImage: "square.and.arrow.up")
        }

        Button(action: onDelete) {
            Label("sidebar.context_menu.delete_game".localized(), systemImage: "trash")
        }
    }

    /// Start or stop the game
    private func toggleGameState() {
        Task {
            // Reduce process queries using cached state instead of rechecking
            let currentlyRunning = gameStatusManager.allGameStates[game.id] ?? false
            if currentlyRunning {
                await gameLaunchUseCase.stopGame(game: game)
            } else {
                gameStatusManager.setGameLaunching(gameId: game.id, isLaunching: true)
                defer { gameStatusManager.setGameLaunching(gameId: game.id, isLaunching: false) }
                await gameLaunchUseCase.launchGame(
                    player: playerListViewModel.currentPlayer,
                    game: game
                )
            }
        }
    }
}
