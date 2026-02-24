import SwiftUI

// MARK: - Footer button block
struct GameResourceInstallFooter: View {
    let project: ModrinthProject
    let resourceType: String
    var isUpdateMode = false  // Update mode: Display "Download", do not display dependencies (controlled by the parent and do not display dependent blocks)
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
                    "Manual download of all dependencies failed: \(globalError.chineseMessage)"
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
                Logger.shared.error("Failed to download resource: \(globalError.chineseMessage)")
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

        _ = await MainActor.run {
            onDownloadSuccess?(fileName, hash)
            isDownloadingAll = false
            isPresented = false
        }
    }
}
