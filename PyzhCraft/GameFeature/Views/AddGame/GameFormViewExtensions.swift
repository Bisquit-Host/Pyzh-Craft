import SwiftUI

// MARK: - Game Form View Extensions
extension View {
    /// Universal game form status listening modifier
    func gameFormStateListeners<T: BaseGameFormViewModel>(
        viewModel: T,
        triggerConfirm: Binding<Bool>,
        triggerCancel: Binding<Bool>
    ) -> some View {
        self
            // Optimization: only update when the value actually changes, reducing unnecessary view updates
            .onChange(of: viewModel.gameNameValidator.gameName) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.gameNameValidator.isGameNameDuplicate) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.gameSetupService.downloadState.isDownloading) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: triggerConfirm.wrappedValue) { _, newValue in
                if newValue {
                    viewModel.handleConfirm()
                    triggerConfirm.wrappedValue = false
                }
            }
            .onChange(of: triggerCancel.wrappedValue) { _, newValue in
                if newValue {
                    viewModel.handleCancel()
                    triggerCancel.wrappedValue = false
                }
            }
    }
}

// MARK: - Common Error Handling
extension BaseGameFormViewModel {
    /// Unified file access error handling
    func handleFileAccessError(_ error: Error, context: String) {
        let globalError = GlobalError.fileSystem(
            chineseMessage: "无法访问文件: \(context)",
            i18nKey: "error.filesystem.file_access_failed",
            level: .notification
        )
        handleNonCriticalError(globalError, message: "error.file.access.failed".localized())
    }

    /// Unified file read error handling
    func handleFileReadError(_ error: Error, context: String) {
        let globalError = GlobalError.fileSystem(
            chineseMessage: "无法读取文件: \(context)",
            i18nKey: "error.filesystem.file_read_failed",
            level: .notification
        )
        handleNonCriticalError(globalError, message: "error.file.read.failed".localized())
    }
}
