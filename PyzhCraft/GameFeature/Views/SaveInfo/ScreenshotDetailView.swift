import SwiftUI

struct ScreenshotDetailView: View {
    let screenshot: ScreenshotInfo
    let gameName: String
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        CommonSheetView(
            header: { headerView },
            body: { bodyView },
            footer: { footerView }
        )
        .frame(minWidth: 600, minHeight: 400)
    }

    private var headerView: some View {
        HStack {
            Text(screenshot.name)
                .font(.headline)
            Spacer()
            ShareLink(item: screenshot.path) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bodyView: some View {
        ScrollView {
            ScreenshotImageView(path: screenshot.path)
                .frame(maxWidth: .infinity)
        }
    }

    private var footerView: some View {
        HStack {
            if let createdDate = screenshot.createdDate {
                Label {
                    Text(createdDate.formatted(date: .abbreviated, time: .standard))
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
