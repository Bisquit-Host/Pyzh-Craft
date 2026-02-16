import SwiftUI

// MARK: - Footer button block
struct GlobalResourceFooter: View {
    let project: ModrinthProject
    let resourceType: String
    @Binding var isPresented: Bool
    let projectDetail: ModrinthProjectDetail?
    let selectedGame: GameVersionInfo?
    let selectedVersion: ModrinthProjectDetailVersion?
    let dependencyState: DependencyState
    @Binding var isDownloadingAll: Bool
    @Binding var isDownloadingMainOnly: Bool
    let gameRepository: GameRepository
    let loadDependencies:
        (ModrinthProjectDetailVersion, GameVersionInfo) -> Void
    @Binding var mainVersionId: String
    let compatibleGames: [GameVersionInfo]

    var body: some View {
        Group {
            if projectDetail != nil {
                if compatibleGames.isEmpty {
                    HStack {
                        Spacer()
                        Button("Close") { isPresented = false }
                    }
                } else {
                    HStack {
                        Button("Close") { isPresented = false }
                        Spacer()
                        if resourceType == "mod" {
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
                }
            } else {
                HStack {
                    Spacer()
                    Button("Close") { isPresented = false }
                }
            }
        }
    }

    private func downloadMainOnly() {
        guard let game = selectedGame, selectedVersion != nil else { return }
        isDownloadingMainOnly = true
        Task {
            do {
                try await downloadMainOnlyThrowing(game: game)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("下载主资源失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
            }
            
            _ = await MainActor.run {
                isDownloadingMainOnly = false
                isPresented = false
            }
        }
    }

    private func downloadMainOnlyThrowing(game: GameVersionInfo) async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "项目ID不能为空",
                i18nKey: "Project ID Empty",
                level: .notification
            )
        }

        let (success, _, _) =
            await ModrinthDependencyDownloader.downloadMainResourceOnly(
                mainProjectId: project.projectId,
                gameInfo: game,
                query: resourceType,
                gameRepository: gameRepository,
                filterLoader: true
            )

        if !success {
            throw GlobalError.download(
                chineseMessage: "下载主资源失败",
                i18nKey: "Main Resource Failed",
                level: .notification
            )
        }
    }

    private func downloadAllManual() {
        guard let game = selectedGame, selectedVersion != nil else { return }
        isDownloadingAll = true
        Task {
            do {
                try await downloadAllManualThrowing(game: game)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error(
                    "手动下载所有依赖项失败: \(globalError.chineseMessage)"
                )
                GlobalErrorHandler.shared.handle(globalError)
            }
            _ = await MainActor.run {
                isDownloadingAll = false
                isPresented = false
            }
        }
    }

    private func downloadAllManualThrowing(game: GameVersionInfo) async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "项目ID不能为空",
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
                gameInfo: game,
                query: resourceType,
                gameRepository: gameRepository,
                onDependencyDownloadStart: { _ in },
                onDependencyDownloadFinish: { _, _ in }
            )

        if !success {
            throw GlobalError.download(
                chineseMessage: "手动下载依赖项失败",
                i18nKey: "Manual Dependencies Failed",
                level: .notification
            )
        }
    }

    private func downloadResource() {
        guard let game = selectedGame, selectedVersion != nil else { return }
        isDownloadingAll = true
        Task {
            do {
                try await downloadResourceThrowing(game: game)
            } catch {
                let globalError = GlobalError.from(error)
                Logger.shared.error("下载资源失败: \(globalError.chineseMessage)")
                GlobalErrorHandler.shared.handle(globalError)
            }
            _ = await MainActor.run {
                isDownloadingAll = false
                isPresented = false
            }
        }
    }

    private func downloadResourceThrowing(game: GameVersionInfo) async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "项目ID不能为空",
                i18nKey: "Project ID Empty",
                level: .notification
            )
        }

        let (success, _, _) =
            await ModrinthDependencyDownloader.downloadMainResourceOnly(
                mainProjectId: project.projectId,
                gameInfo: game,
                query: resourceType,
                gameRepository: gameRepository,
                filterLoader: true
            )

        if !success {
            throw GlobalError.download(
                chineseMessage: "下载资源失败",
                i18nKey: "Resource Download Failed",
                level: .notification
            )
        }
    }
}
