import SwiftUI

struct JavaDownloadProgressWindow: View {
    @ObservedObject var downloadState: JavaDownloadState
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        // Download list
        VStack {
            if downloadState.hasError {
                // Error status To show the retry button
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
                // Downloading status
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
                // Empty status when there is no download task
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("download.no.tasks".localized())
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .onAppear {
            // Set window close callback
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
        // Clean data when window is closed
    }
}

// Downloads view
struct DownloadItemView: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: DownloadStatus
    let onCancel: () -> Void
    let downloadState: JavaDownloadState?

    var body: some View {
        HStack(spacing: 12) {
            // icon
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
            }

            // content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(Int((downloadState?.progress ?? 0) * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Progress bar and progress information (only displayed when downloading is in progress)
                if case .downloading(let progress) = status {
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action button (Cancel/Retry)
            Button(action: onCancel) {
                Image(systemName: buttonIcon)
                    .foregroundColor(buttonColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var iconColor: Color {
        switch status {
        case .downloading: .accentColor
        case .error: .red
        default: .accentColor
        }
    }

    private var iconBackgroundColor: Color {
        switch status {
        case .downloading: .blue.opacity(0.1)
        case .error: .red.opacity(0.1)
        default: .accentColor
        }
    }

    private var buttonIcon: String {
        switch status {
        case .downloading: "xmark.circle.fill"  // cancel icon
        case .error: "arrow.clockwise.circle.fill"  // Retry goal
        case .completed, .cancelled: "xmark.circle.fill"  // Default close icon
        }
    }

    private var buttonColor: Color {
        switch status {
        case .downloading: .secondary  // Use secondary color for cancel button
        case .error: .blue  // Retry button in blue
        case .completed, .cancelled: .secondary  // Default secondary color
        }
    }
}

// Download status enum
enum DownloadStatus {
    case downloading(progress: Double)
    case completed, error, cancelled
}
