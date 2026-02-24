import SwiftUI

/// Details area toolbar content
public struct DetailToolbarView: ToolbarContent {
    @Environment(\.openURL)
    private var openURL
    @EnvironmentObject var filterState: ResourceFilterState
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var gameRepository: GameRepository
    @EnvironmentObject var gameLaunchUseCase: GameLaunchUseCase
    @EnvironmentObject var playerListViewModel: PlayerListViewModel
    @StateObject private var gameStatusManager = GameStatusManager.shared
    @StateObject private var gameActionManager = GameActionManager.shared
    
    private var currentGame: GameVersionInfo? {
        if case .game(let gameId) = detailState.selectedItem {
            return gameRepository.getGame(by: gameId)
        }
        return nil
    }
    
    private func isGameRunning(gameId: String) -> Bool {
        gameStatusManager.isGameRunning(gameId: gameId)
    }
    
    /// Open the project page of the current resource in the browser
    private func openCurrentResourceInBrowser() {
        guard let slug = detailState.loadedProjectDetail?.slug else { return }
        
        let baseURL: String = switch filterState.dataSource {
        case .modrinth:
            URLConfig.API.Modrinth.webProjectBase
        case .curseforge:
            URLConfig.API.CurseForge.webProjectBase
        }
        
        guard let url = URL(string: baseURL + slug) else { return }
        openURL(url)
    }
    
    public var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            switch detailState.selectedItem {
            case .game:
                if let game = currentGame {
                    resourcesTypeMenu
                    resourcesMenu
                    if !detailState.gameType {
                        localResourceFilterMenu
                    }
                    if detailState.gameType {
                        dataSourceMenu
                    }
                    
                    Spacer()
                    
                    Button {
                        Task {
                            let isRunning = isGameRunning(gameId: game.id)
                            if isRunning {
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
                    } label: {
                        let isRunning = isGameRunning(gameId: game.id)
                        let isLaunchingGame = gameStatusManager.isGameLaunching(gameId: game.id)
                        if isLaunchingGame && !isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                isRunning
                                ? LocalizedStringKey("Stop")
                                : LocalizedStringKey("Start"),
                                systemImage: isRunning
                                ? "stop.fill" : "play.fill"
                            )
                        }
                    }
                    .help(
                        isGameRunning(gameId: game.id)
                        ? "Stop"
                        : (gameStatusManager.isGameLaunching(gameId: game.id) ? "" : "Start")
                    )
                    .disabled(gameStatusManager.isGameLaunching(gameId: game.id))
                    .applyReplaceTransition()
                    
                    Button {
                        gameActionManager.showInFinder(game: game)
                    } label: {
                        Label("Path", systemImage: "folder")
                            .foregroundStyle(.primary)
                    }
                    .help("Path")
                }
            case .resource:
                if detailState.selectedProjectId != nil {
                    Button {
                        if let id = detailState.gameId {
                            detailState.selectedItem = .game(id)
                        } else {
                            detailState.selectedProjectId = nil
                            filterState.selectedTab = 0
                        }
                    } label: {
                        Label("Return", systemImage: "arrow.backward")
                    }
                    .help("Return")
                    Spacer()
                    Button {
                        openCurrentResourceInBrowser()
                    } label: {
                        Label("Browser", systemImage: "safari")
                    }
                    .help("Open in Browser")
                } else {
                    if detailState.gameType {
                        dataSourceMenu
                    }
                }
            }
        }
    }
    
    private var currentResourceTitle: String {
        resourceTypeTitle(for: detailState.gameResourcesType)
    }
    private var currentResourceTypeTitle: String {
        detailState.gameType
        ? String(localized: "Resource Library")
        : String(localized: "Installed")
    }
    
    private var resourcesMenu: some View {
        Menu {
            ForEach(resourceTypesForCurrentGame, id: \.self) { sort in
                Button(resourceTypeTitle(for: sort)) {
                    detailState.gameResourcesType = sort
                }
            }
        } label: {
            Label(currentResourceTitle, systemImage: "").labelStyle(.titleOnly)
        }.help("Resource Type")
    }
    
    private var resourcesTypeMenu: some View {
        Button {
            detailState.gameType.toggle()
        } label: {
            Label(
                currentResourceTypeTitle,
                systemImage: detailState.gameType
                ? "tray.and.arrow.down" : "icloud.and.arrow.down"
            ).foregroundStyle(.primary)
        }
        .help("Resource Location")
        .applyReplaceTransition()
    }
    
    private var resourceTypesForCurrentGame: [String] {
        var types = ["datapack", "resourcepack"]
        if let game = currentGame, game.modLoader.lowercased() != "vanilla" {
            types.insert("mod", at: 0)
            types.insert("shader", at: 2)
        }
        return types
    }
    
    private func resourceTypeTitle(for type: String) -> String {
        switch type.lowercased() {
        case "mod":
            String(localized: "Mod")
        case "datapack":
            String(localized: "Data Pack")
        case "shader":
            String(localized: "Shader")
        case "resourcepack":
            String(localized: "Resource Pack")
        case "modpack":
            String(localized: "Modpack")
        case "local":
            String(localized: "Installed")
        case "server":
            String(localized: "Resource Library")
        default:
            type.capitalized
        }
    }
    
    private var dataSourceMenu: some View {
        Menu {
            ForEach(DataSource.allCases, id: \.self) { source in
                Button(source.localizedNameKey) {
                    filterState.dataSource = source
                }
            }
        } label: {
            Label(filterState.dataSource.localizedNameKey, systemImage: "network")
                .labelStyle(.titleOnly)
        }
    }
    
    private var localResourceFilterMenu: some View {
        Menu {
            ForEach(LocalResourceFilter.allCases) { filter in
                Button {
                    filterState.localResourceFilter = filter
                } label: {
                    if filterState.localResourceFilter == filter {
                        Label(filter.title, systemImage: "checkmark")
                    } else {
                        Text(filter.title)
                    }
                }
            }
        } label: {
            Text(filterState.localResourceFilter.title)
        }
    }
}
