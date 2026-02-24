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
                title: "Core Files",
                state: gameSetupService.downloadState,
                type: .core
            )
            progressSection(
                title: "Resource Files",
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
        title: LocalizedStringKey,
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
        let title: LocalizedStringKey
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
        case "fabric", "quilt": gameSetupService.fabricDownloadState
        case "forge": gameSetupService.forgeDownloadState
        case "neoforge": gameSetupService.neoForgeDownloadState
        default: nil
        }
    }

    private func getLoaderTitle(for loaderType: String) -> LocalizedStringKey {
        switch loaderType.lowercased() {
        case "fabric": "Fabric Loader"
        case "quilt": "QuiltMC Loader"
        case "forge": "Forge Loader"
        case "neoforge": "NeoForge Loader"
        default: ""
        }
    }
}
