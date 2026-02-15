import SwiftUI

// MARK: - Download Progress Section
struct DownloadProgressSection: View {
    @ObservedObject var gameSetupService: GameSetupUtil
    var modPackViewModel: ModPackDownloadSheetViewModel?
    let modPackIndexInfo: ModrinthIndexInfo?
    let selectedModLoader: String

    init(
        gameSetupService: GameSetupUtil,
        selectedModLoader: String = "vanilla",
        modPackViewModel: ModPackDownloadSheetViewModel? = nil,
        modPackIndexInfo: ModrinthIndexInfo? = nil
    ) {
        self.gameSetupService = gameSetupService
        self.selectedModLoader = selectedModLoader
        self.modPackViewModel = modPackViewModel
        self.modPackIndexInfo = modPackIndexInfo
    }

    var body: some View {
        VStack(spacing: 24) {
            // Game core download progress
            gameDownloadProgressView
            // Mod loader download progress
            modLoaderProgressView
            // Integration package installation progress
            if let modPackViewModel = modPackViewModel {
                ModPackProgressView(modPackViewModel: modPackViewModel)
            }
        }
    }

    // MARK: - Game Download Progress
    private var gameDownloadProgressView: some View {
        VStack(spacing: 24) {
            progressSection(
                title: "download.core.title".localized(),
                state: gameSetupService.downloadState,
                type: .core
            )
            progressSection(
                title: "download.resources.title".localized(),
                state: gameSetupService.downloadState,
                type: .resources
            )
        }
    }

    // MARK: - Mod Loader Progress
    @ViewBuilder private var modLoaderProgressView: some View {
        if let loaderProgressInfo = getLoaderProgressInfo() {
            progressSection(
                title: loaderProgressInfo.title,
                state: loaderProgressInfo.state,
                type: .core,
                version: loaderProgressInfo.version
            )
        }
    }

    // MARK: - Helper Methods

    private enum ProgressType {
        case core, resources
    }

    private func progressSection(
        title: String,
        state: DownloadState,
        type: ProgressType,
        version: String? = nil
    ) -> some View {
        FormSection {
            DownloadProgressRow(
                title: title,
                progress: type == .core ? state.coreProgress : state.resourcesProgress,
                currentFile: type == .core ? state.currentCoreFile : state.currentResourceFile,
                completed: type == .core ? state.coreCompletedFiles : state.resourcesCompletedFiles,
                total: type == .core ? state.coreTotalFiles : state.resourcesTotalFiles,
                version: version
            )
        }
    }

    private struct LoaderProgressInfo {
        let title: String
        let state: DownloadState
        let version: String?
    }

    private func getLoaderProgressInfo() -> LoaderProgressInfo? {
        let loaderType = selectedModLoader.lowercased()

        // If it is integration package mode, use the loader information of the integration package
        if let indexInfo = modPackIndexInfo {
            let loaderState = getLoaderDownloadState(for: indexInfo.loaderType)
            let title = getLoaderTitle(for: indexInfo.loaderType)

            if let state = loaderState {
                return LoaderProgressInfo(
                    title: title,
                    state: state,
                    version: indexInfo.loaderVersion
                )
            }
        } else {
            // Normal game creation mode
            let state = getLoaderDownloadState(for: loaderType)
            let title = getLoaderTitle(for: loaderType)

            if let state = state {
                return LoaderProgressInfo(
                    title: title,
                    state: state,
                    version: nil
                )
            }
        }

        return nil
    }

    private func getLoaderDownloadState(for loaderType: String) -> DownloadState? {
        switch loaderType.lowercased() {
        case "fabric", "quilt":
            return gameSetupService.fabricDownloadState
        case "forge":
            return gameSetupService.forgeDownloadState
        case "neoforge":
            return gameSetupService.neoForgeDownloadState
        default:
            return nil
        }
    }

    private func getLoaderTitle(for loaderType: String) -> String {
        switch loaderType.lowercased() {
        case "fabric":
            return "fabric.loader.title".localized()
        case "quilt":
            return "quilt.loader.title".localized()
        case "forge":
            return "forge.loader.title".localized()
        case "neoforge":
            return "neoforge.loader.title".localized()
        default:
            return ""
        }
    }
}

// MARK: - ModPack Progress View
private struct ModPackProgressView: View {
    @ObservedObject var modPackViewModel: ModPackDownloadSheetViewModel

    var body: some View {
        if modPackViewModel.modPackInstallState.isInstalling {
            VStack(spacing: 24) {
                // Show overrides progress bar (only displayed when there are files that need to be merged)
                if modPackViewModel.modPackInstallState.overridesTotal > 0 {
                    modPackProgressSection(
                        title: "launcher.import.copying_files".localized(),
                        state: modPackViewModel.modPackInstallState,
                        type: .overrides
                    )
                }

                modPackProgressSection(
                    title: "modpack.files.title".localized(),
                    state: modPackViewModel.modPackInstallState,
                    type: .files
                )

                if modPackViewModel.modPackInstallState.dependenciesTotal > 0 {
                    modPackProgressSection(
                        title: "modpack.dependencies.title".localized(),
                        state: modPackViewModel.modPackInstallState,
                        type: .dependencies
                    )
                }
            }
        }
    }

    private enum ModPackProgressType {
        case files, dependencies, overrides
    }

    private func modPackProgressSection(
        title: String,
        state: ModPackInstallState,
        type: ModPackProgressType
    ) -> some View {
        FormSection {
            DownloadProgressRow(
                title: title,
                progress: {
                    switch type {
                    case .files:
                        return state.filesProgress
                    case .dependencies:
                        return state.dependenciesProgress
                    case .overrides:
                        return state.overridesProgress
                    }
                }(),
                currentFile: {
                    switch type {
                    case .files:
                        return state.currentFile
                    case .dependencies:
                        return state.currentDependency
                    case .overrides:
                        return state.currentOverride
                    }
                }(),
                completed: {
                    switch type {
                    case .files:
                        return state.filesCompleted
                    case .dependencies:
                        return state.dependenciesCompleted
                    case .overrides:
                        return state.overridesCompleted
                    }
                }(),
                total: {
                    switch type {
                    case .files:
                        return state.filesTotal
                    case .dependencies:
                        return state.dependenciesTotal
                    case .overrides:
                        return state.overridesTotal
                    }
                }(),
                version: nil
            )
        }
    }
}
