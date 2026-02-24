import SwiftUI

// MARK: - Game resource installation sheet (preset game information, no need to select a game)
struct GameResourceInstallSheet: View {
    let project: ModrinthProject
    let resourceType: String
    let gameInfo: GameVersionInfo  // Preset game information
    @Binding var isPresented: Bool
    let preloadedDetail: ModrinthProjectDetail?  // Preloaded project details
    var isUpdateMode = false  // Update mode: The footer displays "Download" and does not display dependencies
    @EnvironmentObject var gameRepository: GameRepository
    /// Download success callback, the parameters are (fileName, hash), only the downloadResource path will pass the value, downloadAllManual will pass (nil, nil)
    var onDownloadSuccess: ((String?, String?) -> Void)?

    @State private var selectedVersion: ModrinthProjectDetailVersion?
    @State private var availableVersions: [ModrinthProjectDetailVersion] = []
    @State private var dependencyState = DependencyState()
    @State private var isDownloadingAll = false
    @State private var mainVersionId = ""

    var body: some View {
        CommonSheetView(
            header: {
                Text("Add For Game \(gameInfo.gameName)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }, body: {
                if let detail = preloadedDetail {
                    VStack {
                        ModrinthProjectTitleView(
                            projectDetail: detail
                        ).padding(.bottom, 18)

                        VersionPickerForSheet(
                            project: project,
                            resourceType: resourceType,
                            selectedGame: .constant(gameInfo),
                            selectedVersion: $selectedVersion,
                            availableVersions: $availableVersions,
                            mainVersionId: $mainVersionId
                        ) { version in
                            if resourceType == "mod",
                               !isUpdateMode,
                               let v = version {
                                loadDependencies(for: v, game: gameInfo)
                            } else {
                                dependencyState = DependencyState()
                            }
                        }

                        if resourceType == "mod", !isUpdateMode {
                            if dependencyState.isLoading || !dependencyState.dependencies.isEmpty {
                                spacerView()
                                DependencySectionView(state: $dependencyState)
                            }
                        }
                    }
                }
            },
            footer: {
                GameResourceInstallFooter(
                    project: project,
                    resourceType: resourceType,
                    isUpdateMode: isUpdateMode,
                    isPresented: $isPresented,
                    projectDetail: preloadedDetail,
                    gameInfo: gameInfo,
                    selectedVersion: selectedVersion,
                    dependencyState: dependencyState,
                    isDownloadingAll: $isDownloadingAll,
                    gameRepository: gameRepository,
                    loadDependencies: loadDependencies,
                    mainVersionId: $mainVersionId,
                    onDownloadSuccess: onDownloadSuccess
                )
            }
        )
        .onDisappear {
            selectedVersion = nil
            availableVersions = []
            dependencyState = DependencyState()
            isDownloadingAll = false
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
