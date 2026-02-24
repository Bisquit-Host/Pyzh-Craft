import SwiftUI

struct ProgressRowWrapper: View {
    let title: LocalizedStringKey
    @ObservedObject var state: DownloadState
    let type: ProgressType
    let version: String?

    var body: some View {
        DownloadProgressRow(
            title: title,
            progress: type == .core
                ? state.coreProgress : state.resourcesProgress,
            currentFile: type == .core
                ? state.currentCoreFile : state.currentResourceFile,
            completed: type == .core
                ? state.coreCompletedFiles : state.resourcesCompletedFiles,
            total: type == .core
                ? state.coreTotalFiles : state.resourcesTotalFiles,
            version: version
        )
    }
}
