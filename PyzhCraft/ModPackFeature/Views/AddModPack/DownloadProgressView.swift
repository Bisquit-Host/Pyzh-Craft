import SwiftUI

struct DownloadProgressView: View {
    @ObservedObject var gameSetupService: GameSetupUtil
    @ObservedObject var modPackInstallState: ModPackInstallState
    let lastParsedIndexInfo: ModrinthIndexInfo?

    var body: some View {
        VStack(spacing: 24) {
            gameDownloadProgress
            modLoaderDownloadProgress
            modPackInstallProgress
        }
    }

    private var gameDownloadProgress: some View {
        Group {
            progressRow(
                title: "Core Files",
                state: gameSetupService.downloadState,
                type: .core
            )
            progressRow(
                title: "Resource Files",
                state: gameSetupService.downloadState,
                type: .resources
            )
        }
    }

    private var modLoaderDownloadProgress: some View {
        Group {
            if let indexInfo = lastParsedIndexInfo {
                let loaderType = indexInfo.loaderType.lowercased()
                let title = getLoaderTitle(for: indexInfo.loaderType)

                if loaderType == "fabric" || loaderType == "quilt" {
                    progressRow(
                        title: title,
                        state: gameSetupService.fabricDownloadState,
                        type: .core,
                        version: indexInfo.loaderVersion
                    )
                } else if loaderType == "forge" {
                    progressRow(
                        title: title,
                        state: gameSetupService.forgeDownloadState,
                        type: .core,
                        version: indexInfo.loaderVersion
                    )
                } else if loaderType == "neoforge" {
                    progressRow(
                        title: title,
                        state: gameSetupService.neoForgeDownloadState,
                        type: .core,
                        version: indexInfo.loaderVersion
                    )
                }
            }
        }
    }

    private var modPackInstallProgress: some View {
        Group {
            if modPackInstallState.isInstalling {
                if modPackInstallState.overridesTotal > 0 {
                    progressRow(
                        title: "Copy Files",
                        installState: modPackInstallState,
                        type: .overrides
                    )
                }

                progressRow(
                    title: "Modpack Files",
                    installState: modPackInstallState,
                    type: .files
                )

                if modPackInstallState.dependenciesTotal > 0 {
                    progressRow(
                        title: "Modpack Dependencies",
                        installState: modPackInstallState,
                        type: .dependencies
                    )
                }
            }
        }
    }

    private func progressRow(
        title: LocalizedStringKey,
        state: DownloadState,
        type: ProgressType,
        version: String? = nil
    ) -> some View {
        FormSection {
            ProgressRowWrapper(
                title: title,
                state: state,
                type: type,
                version: version
            )
        }
    }

    private func progressRow(
        title: LocalizedStringKey,
        installState: ModPackInstallState,
        type: InstallProgressType
    ) -> some View {
        FormSection {
            DownloadProgressRow(
                title: title,
                progress: {
                    switch type {
                    case .files:
                        return installState.filesProgress
                    case .dependencies:
                        return installState.dependenciesProgress
                    case .overrides:
                        return installState.overridesProgress
                    }
                }(),
                currentFile: {
                    switch type {
                    case .files:
                        return installState.currentFile
                    case .dependencies:
                        return installState.currentDependency
                    case .overrides:
                        return installState.currentOverride
                    }
                }(),
                completed: {
                    switch type {
                    case .files:
                        return installState.filesCompleted
                    case .dependencies:
                        return installState.dependenciesCompleted
                    case .overrides:
                        return installState.overridesCompleted
                    }
                }(),
                total: {
                    switch type {
                    case .files:
                        return installState.filesTotal
                    case .dependencies:
                        return installState.dependenciesTotal
                    case .overrides:
                        return installState.overridesTotal
                    }
                }(),
                version: nil
            )
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

enum ProgressType {
    case core, resources
}

enum InstallProgressType {
    case files, dependencies, overrides
}
