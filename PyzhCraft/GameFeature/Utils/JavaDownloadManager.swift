import Foundation

/// Java download manager
@MainActor
class JavaDownloadManager: ObservableObject {
    static let shared = JavaDownloadManager()

    @Published var downloadState = JavaDownloadState()
    @Published var isWindowVisible = false

    private let javaRuntimeService = JavaRuntimeService.shared
    private var dismissCallback: (() -> Void)?

    /// Set window close callback
    func setDismissCallback(_ callback: @escaping () -> Void) {
        dismissCallback = callback
    }

    /// Start downloading Java runtime
    func downloadJavaRuntime(version: String) async {
        do {
            // reset state
            downloadState.reset()
            downloadState.startDownload(version: version)

            // Show download pop-up window
            showDownloadWindow()

            // Set progress callback
            javaRuntimeService.setProgressCallback { [weak self] fileName, completed, total in
                Task { @MainActor in
                    // Check if canceled
                    guard let self = self, !self.downloadState.isCancelled else { return }
                    let progress = total > 0 ? Double(completed) / Double(total) : 0.0
                    self.downloadState.updateProgress(fileName: fileName, progress: progress)
                }
            }

            // Set cancel check callback
            javaRuntimeService.setCancelCallback { [weak self] in
                return self?.downloadState.isCancelled ?? false
            }

            // Start downloading
            try await javaRuntimeService.downloadJavaRuntime(for: version)

            // Check if canceled
            if downloadState.isCancelled {
                Logger.shared.info("Java下载已被取消")
                cleanupCancelledDownload()
                return
            }

            // Download Complete - Set completion status to automatically close the window later
            downloadState.isDownloading = false

            closeWindow()
        } catch {
            // Download failed
            if !downloadState.isCancelled {
                downloadState.setError(error.localizedDescription)
            }
        }
    }

    /// Cancel download
    func cancelDownload() {
        downloadState.cancel()
        // The cancellation status will be passed to JavaRuntimeService through the shouldCancel callback
        // Close window now
        cleanupCancelledDownload()
    }

    /// Retry download
    func retryDownload() {
        guard !downloadState.version.isEmpty else { return }
        Task {
            await downloadJavaRuntime(version: downloadState.version)
        }
    }

    /// Show download window
    private func showDownloadWindow() {
        WindowManager.shared.openWindow(id: .javaDownload)
        isWindowVisible = true
    }

    /// close window
    func closeWindow() {
        WindowManager.shared.closeWindow(id: .javaDownload)
        isWindowVisible = false
        downloadState.reset()
        dismissCallback?()
    }

    /// Clean canceled download data
    func cleanupCancelledDownload() {
        // Clean up some downloaded files
        // Cleaning logic can be added
        Logger.shared.info("Cleaning up cancelled Java download for version: \(downloadState.version)")
        // Reset state and close window
        closeWindow()
    }
}
