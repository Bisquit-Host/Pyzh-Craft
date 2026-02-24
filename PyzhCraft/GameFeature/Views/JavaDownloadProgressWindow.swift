import SwiftUI

struct JavaDownloadProgressWindow: View {
    @ObservedObject var downloadState: JavaDownloadState
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        VStack {
            if downloadState.hasError {
                DownloadItemView(
                    icon: "exclamationmark.triangle.fill",
                    title: downloadState.version,
                    subtitle: downloadState.errorMessage,
                    status: .error,
                    onCancel: {
                        JavaDownloadManager.shared.retryDownload()
                    },
                    downloadState: downloadState
                )
            } else if downloadState.isDownloading {
                DownloadItemView(
                    icon: "cup.and.saucer.fill",
                    title: downloadState.version,
                    subtitle: downloadState.currentFile.isEmpty ? "Preparing..." : downloadState.currentFile,
                    status: .downloading(progress: downloadState.progress),
                    onCancel: {
                        JavaDownloadManager.shared.cancelDownload()
                    },
                    downloadState: downloadState
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No download tasks")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .onAppear {
            JavaDownloadManager.shared.setDismissCallback {
                dismiss()
            }
        }
        .onDisappear {
            clearAllData()
        }
    }

    /// Clean all data
    private func clearAllData() {
    }
}
