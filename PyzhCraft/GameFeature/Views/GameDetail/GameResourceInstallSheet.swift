import SwiftUI

// MARK: - Game resource installation sheet (preset game information, no need to select a game)
struct GameResourceInstallSheet: View {
    let project: ModrinthProject
    let resourceType: String
    let gameInfo: GameVersionInfo  // Preset game information
    @Binding var isPresented: Bool
    let preloadedDetail: ModrinthProjectDetail?  // Preloaded project details
    var isUpdateMode: Bool = false  // Update mode: The footer displays "Download" and does not display dependencies
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
                            selectedGame: .constant(gameInfo),  // Preset game information
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
            // Clean up all state data when sheet closes to free up memory
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
                Logger.shared.error("加载依赖项失败: \(globalError.chineseMessage)")
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

// MARK: - Footer button block
struct GameResourceInstallFooter: View {
    let project: ModrinthProject
    let resourceType: String
    var isUpdateMode: Bool = false  // Update mode: Display "Download", do not display dependencies (controlled by the parent and do not display dependent blocks)
    @Binding var isPresented: Bool
    let projectDetail: ModrinthProjectDetail?
    let gameInfo: GameVersionInfo
    let selectedVersion: ModrinthProjectDetailVersion?
    let dependencyState: DependencyState
    @Binding var isDownloadingAll: Bool
    let gameRepository: GameRepository
    let loadDependencies:
        (ModrinthProjectDetailVersion, GameVersionInfo) -> Void
    @Binding var mainVersionId: String
    /// Download success callback, the parameters are (fileName, hash), only the downloadResource path will pass the value, downloadAllManual will pass (nil, nil)
    var onDownloadSuccess: ((String?, String?) -> Void)?

    var body: some View {
        Group {
            if projectDetail != nil {
                HStack {
                    Button("Close") { isPresented = false }
                    Spacer()
                    if resourceType == "mod", !isUpdateMode {
                        // Mod in installation mode: displays "Download All" (including dependencies)
                        if !dependencyState.isLoading {
                            if selectedVersion != nil {
                                Button(action: downloadAllManual) {
                                    if isDownloadingAll {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Text("Download All")
                                    }
                                }
                                .disabled(isDownloadingAll)
                                .keyboardShortcut(.defaultAction)
                            }
                        }
                    } else {
                        // Non-mod, or update mode: Show "Download" (main resource only)
                        if selectedVersion != nil {
                            Button(action: downloadResource) {
                                if isDownloadingAll {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Download")
                                }
                            }
                            .disabled(isDownloadingAll)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Button("Close") { isPresented = false }
                }
            }
        }
    }

    private func downloadAllManual() {
        guard selectedVersion != nil else { return }
        isDownloadingAll = true
        Task {
            do {
                try await downloadAllManualThrowing()
                // Successful download has been handled in downloadAllManualThrowing to close the sheet
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error(
                    "手动下载所有依赖项失败: \(globalError.chineseMessage)"
                )
                GlobalErrorHandler.shared.handle(globalError)
                _ = await MainActor.run {
                    isDownloadingAll = false
                }
            }
        }
    }

    private func downloadAllManualThrowing() async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                i18nKey: "Project ID Empty",
                level: .notification
            )
        }

        let success =
            await ModrinthDependencyDownloader.downloadManualDependenciesAndMain(
                dependencies: dependencyState.dependencies,
                selectedVersions: dependencyState.selected.compactMapValues {
                    $0?.id
                },
                dependencyVersions: dependencyState.versions,
                mainProjectId: project.projectId,
                mainProjectVersionId: mainVersionId.isEmpty
                    ? nil : mainVersionId,
                gameInfo: gameInfo,
                query: resourceType,
                gameRepository: gameRepository,
                onDependencyDownloadStart: { _ in },
                onDependencyDownloadFinish: { _, _ in }
            )

        if !success {
            throw GlobalError.download(
                i18nKey: "Manual Dependencies Failed",
                level: .notification
            )
        }

        // The download is successful, the button status is updated and the sheet is closed (downloadAllManual does not pass fileName/hash)
        _ = await MainActor.run {
            onDownloadSuccess?(nil, nil)
            isDownloadingAll = false
            isPresented = false
        }
    }

    private func downloadResource() {
        guard selectedVersion != nil else { return }
        isDownloadingAll = true
        Task {
            do {
                try await downloadResourceThrowing()
                // Successful download has been handled in downloadResourceThrowing to close the sheet
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("下载资源失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
                _ = await MainActor.run {
                    isDownloadingAll = false
                }
            }
        }
    }

    private func downloadResourceThrowing() async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                i18nKey: "Project ID Empty",
                level: .notification
            )
        }

        let (success, fileName, hash) =
            await ModrinthDependencyDownloader.downloadMainResourceOnly(
                mainProjectId: project.projectId,
                gameInfo: gameInfo,
                query: resourceType,
                gameRepository: gameRepository,
                filterLoader: true
            )

        if !success {
            throw GlobalError.download(
                i18nKey: "Resource Download Failed",
                level: .notification
            )
        }

        // If the download is successful, update the button status and close the sheet. Pass (fileName, hash) for partial refresh in the update process
        _ = await MainActor.run {
            onDownloadSuccess?(fileName, hash)
            isDownloadingAll = false
            isPresented = false
        }
    }
}
