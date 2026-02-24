import SwiftUI

// Downloads view
struct DownloadItemView: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: DownloadStatus
    let onCancel: () -> Void
    let downloadState: JavaDownloadState?

    private var progressText: String {
        (downloadState?.progress ?? 0).formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text(progressText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if case .downloading(let progress) = status {
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        case .downloading: "xmark.circle.fill"
        case .error: "arrow.clockwise.circle.fill"
        case .completed, .cancelled: "xmark.circle.fill"
        }
    }

    private var buttonColor: Color {
        switch status {
        case .downloading: .secondary
        case .error: .blue
        case .completed, .cancelled: .secondary
        }
    }
}

// Download status enum
enum DownloadStatus {
    case downloading(progress: Double)
    case completed, error, cancelled
}
