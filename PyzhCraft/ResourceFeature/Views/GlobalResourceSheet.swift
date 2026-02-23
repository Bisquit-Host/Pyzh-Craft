import SwiftUI

// MARK: - Add Sheet to the main resource
struct GlobalResourceSheet: View {
    let project: ModrinthProject
    let resourceType: String
    @Binding var isPresented: Bool
    let preloadedDetail: ModrinthProjectDetail?  // Preloaded project details
    let preloadedCompatibleGames: [GameVersionInfo]  // Pre-detected list of compatible games
    @EnvironmentObject var gameRepository: GameRepository
    @State private var selectedGame: GameVersionInfo?
    @State private var selectedVersion: ModrinthProjectDetailVersion?
    @State private var availableVersions: [ModrinthProjectDetailVersion] = []
    @State private var dependencyState = DependencyState()
    @State private var isDownloadingAll = false
    @State private var isDownloadingMainOnly = false
    @State private var mainVersionId = ""

    var body: some View {
        CommonSheetView(
            header: {
                Text(
                    selectedGame.map {
                        String(format: String(localized: "Add For Game \($0.gameName)"))
                    } ?? String(localized: "Add")
                )
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                if let detail = preloadedDetail {
                    if preloadedCompatibleGames.isEmpty {
                        Text("No Game List")
                            .foregroundColor(.secondary).padding()
                    } else {
                        VStack {
                            ModrinthProjectTitleView(
                                projectDetail: detail
                            ).padding(.bottom, 18)
                            CommonSheetGameBody(
                                compatibleGames: preloadedCompatibleGames,
                                selectedGame: $selectedGame
                            )
                            if let game = selectedGame {
                                spacerView()
                                VersionPickerForSheet(
                                    project: project,
                                    resourceType: resourceType,
                                    selectedGame: $selectedGame,
                                    selectedVersion: $selectedVersion,
                                    availableVersions: $availableVersions,
                                    mainVersionId: $mainVersionId
                                ) { version in
                                    if resourceType == "mod",
                                        let v = version {
                                        loadDependencies(for: v, game: game)
                                    } else {
                                        dependencyState = DependencyState()
                                    }
                                }
                                if resourceType == "mod" {
                                    if dependencyState.isLoading || !dependencyState.dependencies.isEmpty {
                                        spacerView()
                                        DependencySectionView(state: $dependencyState)
                                    }
                                }
                            }
                        }
                    }
                }
            },
            footer: {
                GlobalResourceFooter(
                    project: project,
                    resourceType: resourceType,
                    isPresented: $isPresented,
                    projectDetail: preloadedDetail,
                    selectedGame: selectedGame,
                    selectedVersion: selectedVersion,
                    dependencyState: dependencyState,
                    isDownloadingAll: $isDownloadingAll,
                    isDownloadingMainOnly: $isDownloadingMainOnly,
                    gameRepository: gameRepository,
                    loadDependencies: loadDependencies,
                    mainVersionId: $mainVersionId,
                    compatibleGames: preloadedCompatibleGames
                )
            }
        )
        .onDisappear {
            // Clean up all state data when sheet closes to free up memory
            selectedGame = nil
            selectedVersion = nil
            availableVersions = []
            dependencyState = DependencyState()
            isDownloadingAll = false
            isDownloadingMainOnly = false
            mainVersionId = ""
        }
    }

    private func loadDependencies(
        for version: ModrinthProjectDetailVersion,
        game: GameVersionInfo
    ) {
        dependencyState.isLoading = true
        Task {
            do {
                try await loadDependenciesThrowing(for: version, game: game)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("Failed to load dependencies: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
                _ = await MainActor.run {
                    dependencyState = DependencyState()
                }
            }
        }
    }

    private func loadDependenciesThrowing(
        for version: ModrinthProjectDetailVersion,
        game: GameVersionInfo
    ) async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                i18nKey: "Project ID Empty",
                level: .notification
            )
        }

        // Get missing dependencies (with version information)
        let missingWithVersions =
            await ModrinthDependencyDownloader
            .getMissingDependenciesWithVersions(
                for: project.projectId,
                gameInfo: game
            )

        var depVersions: [String: [ModrinthProjectDetailVersion]] = [:]
        var depSelected: [String: ModrinthProjectDetailVersion?] = [:]
        var dependencies: [ModrinthProjectDetail] = []

        for (detail, versions) in missingWithVersions {
            dependencies.append(detail)
            depVersions[detail.id] = versions
            depSelected[detail.id] = versions.first
        }

        _ = await MainActor.run {
            dependencyState = DependencyState(
                dependencies: dependencies,
                versions: depVersions,
                selected: depSelected,
                isLoading: false
            )
        }
    }
}
