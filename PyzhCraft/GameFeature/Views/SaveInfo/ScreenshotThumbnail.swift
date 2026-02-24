import SwiftUI

struct ScreenshotThumbnail: View {
    private enum Constants {
        static let thumbnailSize: CGFloat = 60
    }

    let screenshot: ScreenshotInfo
    let action: () -> Void

    @State private var image: NSImage?

    var body: some View {
        Button(action: action) {
            Group {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo.fill")
                        .foregroundColor(.secondary)
                }
            }
            .frame(
                width: Constants.thumbnailSize,
                height: Constants.thumbnailSize
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task {
            loadImage()
        }
    }

    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let nsImage = NSImage(contentsOf: screenshot.path) {
                DispatchQueue.main.async {
                    self.image = nsImage
                }
            }
        }
    }
}
