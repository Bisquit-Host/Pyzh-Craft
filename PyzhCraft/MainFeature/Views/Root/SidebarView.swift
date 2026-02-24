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

    // MARK: - Add Player State
    @State private var showingAddPlayerSheet = false
    @State private var playerName = ""
    @State private var isPlayerNameValid = false

    // MARK: - Skin Editor State
    @State private var showEditSkin = false
    @State private var isLoadingSkin = false
    @State private var preloadedSkinInfo: PlayerSkinService.PublicSkinInfo?
    @State private var preloadedProfile: MinecraftProfileResponse?
    
    public init() {}
    
    public var body: some View {
        List(selection: detailState.selectedItemOptionalBinding) {
            // Resources section
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
            
            // game section
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
            HStack(spacing: 8) {
                // Show player selector (if there are players)
                if !playerListViewModel.players.isEmpty {
                    PlayerListView()
                }

                Spacer()

                // Skin management button - only for online accounts
                if currentPlayer?.isOnlineAccount == true {
                    Button {
                        Task { await openSkinManager() }
                    } label: {
                        if isLoadingSkin {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "tshirt")
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Skin")
                    .disabled(isLoadingSkin)
                    .sheet(isPresented: $showEditSkin) {
                        SkinToolDetailView(
                            preloadedSkinInfo: preloadedSkinInfo,
                            preloadedProfile: preloadedProfile
                        )
                        .onDisappear {
                            preloadedSkinInfo = nil
                            preloadedProfile = nil
                        }
                    }
                }

                // Add player button
                Button {
                    playerName = ""
                    isPlayerNameValid = false
                    showingAddPlayerSheet = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Add Player")
                .sheet(isPresented: $showingAddPlayerSheet) {
                    AddPlayerSheetView(
                        playerName: $playerName,
                        isPlayerNameValid: $isPlayerNameValid,
                        onAdd: {
                            if playerListViewModel.addPlayer(name: playerName) {
                                Logger.shared.debug("Player \(playerName) was added successfully (via ViewModel)")
                            } else {
                                Logger.shared.debug("Failed to add player \(playerName) (via ViewModel)")
                            }
                            isPlayerNameValid = true
                            showingAddPlayerSheet = false
                        },
                        onCancel: {
                            playerName = ""
                            isPlayerNameValid = false
                            showingAddPlayerSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                MinecraftAuthService.shared.clearAuthenticationData()
                            }
                        },
                        onLogin: { profile in
                            Logger.shared.debug("Genuine login successful, user: \(profile.name)")
                            _ = playerListViewModel.addOnlinePlayer(profile: profile)
                            PremiumAccountFlagManager.shared.setPremiumAccountAdded()
                            showingAddPlayerSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                MinecraftAuthService.shared.clearAuthenticationData()
                            }
                        },
                        playerListViewModel: playerListViewModel
                    )
                }
            }
            .padding()
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
    
    // MARK: - Computed Properties

    private var currentPlayer: Player? {
        playerListViewModel.currentPlayer
    }

    // Only perform fuzzy search on game name
    private var filteredGames: [GameVersionInfo] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return gameRepository.games
        }
        
        let lower = searchText.lowercased()
        return gameRepository.games.filter { $0.gameName.lowercased().contains(lower) }
    }

    // MARK: - Skin Manager

    /// Open the skin manager (load data first, then display the sheet)
    private func openSkinManager() async {
        guard let player = currentPlayer else { return }

        await MainActor.run {
            isLoadingSkin = true
        }

        // If it is an offline account, use it directly without refreshing the token
        guard player.isOnlineAccount else {
            async let skinInfo = PlayerSkinService.fetchCurrentPlayerSkinFromServices(player: player)
            async let profile = PlayerSkinService.fetchPlayerProfile(player: player)
            let (loadedSkinInfo, loadedProfile) = await (skinInfo, profile)

            await MainActor.run {
                preloadedSkinInfo = loadedSkinInfo
                preloadedProfile = loadedProfile
                isLoadingSkin = false
                showEditSkin = true
            }
            return
        }

        Logger.shared.info("Verify player \(player.name)'s Token before opening the skin manager")

        // Load authentication credentials on demand from Keychain
        var playerWithCredential = player
        if playerWithCredential.credential == nil {
            let dataManager = PlayerDataManager()
            if let credential = dataManager.loadCredential(userId: playerWithCredential.id) {
                playerWithCredential.credential = credential
            }
        }

        // Verify and try to refresh the token
        let authService = MinecraftAuthService.shared
        let validatedPlayer: Player
        do {
            validatedPlayer = try await authService.validateAndRefreshPlayerTokenThrowing(for: playerWithCredential)

            if validatedPlayer.authAccessToken != player.authAccessToken {
                Logger.shared.info("Player \(player.name)'s Token has been updated and saved to the data manager")
                let dataManager = PlayerDataManager()
                let success = dataManager.updatePlayerSilently(validatedPlayer)
                if success {
                    Logger.shared.debug("Token information in player data manager has been updated")
                    NotificationCenter.default.post(
                        name: PlayerSkinService.playerUpdatedNotification,
                        object: nil,
                        userInfo: ["updatedPlayer": validatedPlayer]
                    )
                }
            }
        } catch {
            Logger.shared.error("Failed to refresh Token: \(error.localizedDescription)")
            validatedPlayer = playerWithCredential
        }

        // Preload skin data
        async let skinInfo = PlayerSkinService.fetchCurrentPlayerSkinFromServices(player: validatedPlayer)
        async let profile = PlayerSkinService.fetchPlayerProfile(player: validatedPlayer)
        let (loadedSkinInfo, loadedProfile) = await (skinInfo, profile)

        await MainActor.run {
            preloadedSkinInfo = loadedSkinInfo
            preloadedProfile = loadedProfile
            isLoadingSkin = false
            showEditSkin = true
        }
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
    let onOpenServerSettings: () -> Void
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
        Button(
            isRunning ? "Stop" : "Start",
            systemImage: isRunning ? "stop.fill" : "play.fill",
            action: toggleGameState
        )
        
        Button("Show in Finder", systemImage: "folder") {
            gameActionManager.showInFinder(game: game)
        }
        
        Button("Server Settings", systemImage: "server.rack") {
            selectedGameManager.setSelectedGame(game.id)
            onOpenServerSettings()
        }
        
        Divider()
        
        Button("Export", systemImage: "square.and.arrow.up", action: onExport)
        Button("Delete Game", systemImage: "trash", role: .destructive, action: onDelete)
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
