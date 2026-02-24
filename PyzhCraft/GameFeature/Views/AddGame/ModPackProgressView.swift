import SwiftUI

// MARK: - ModPack Progress View
struct ModPackProgressView: View {
    @ObservedObject var modPackViewModel: ModPackDownloadSheetViewModel

    var body: some View {
        if modPackViewModel.modPackInstallState.isInstalling {
            VStack(spacing: 24) {
                // Show overrides progress bar (only displayed when there are files that need to be merged)
                if modPackViewModel.modPackInstallState.overridesTotal > 0 {
                    modPackProgressSection(
                        title: "Copy Files",
                        state: modPackViewModel.modPackInstallState,
                        type: .overrides
                    )
                }

                modPackProgressSection(
                    title: "Modpack Files",
                    state: modPackViewModel.modPackInstallState,
                    type: .files
                )

                if modPackViewModel.modPackInstallState.dependenciesTotal > 0 {
                    modPackProgressSection(
                        title: "Modpack Dependencies",
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
        title: LocalizedStringKey,
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
