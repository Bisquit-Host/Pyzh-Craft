import SwiftUI

struct CapeTextureView: View {
    let imageURL: String

    var body: some View {
        AsyncImage(url: URL(string: imageURL.httpToHttps())) { phase in
            switch phase {
            case .empty:
                ProgressView().controlSize(.mini)
            case .success(let image):
                capeImageContent(image: image)
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            @unknown default:
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func capeImageContent(image: Image) -> some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let containerHeight = geometry.size.height
            let capeAspectRatio: CGFloat = 10.0 / 16.0
            let containerAspectRatio = containerWidth / containerHeight

            let scale: CGFloat = containerAspectRatio > capeAspectRatio
                ? containerHeight / 16.0
                : containerWidth / 10.0

            let offsetX = (containerWidth - 10.0 * scale) / 2.0 - 1.0 * scale
            let offsetY = (containerHeight - 16.0 * scale) / 2.0 - 1.0 * scale

            image
                .resizable()
                .interpolation(.none)
                .frame(width: 64.0 * scale, height: 32.0 * scale)
                .offset(x: offsetX, y: offsetY)
                .clipped()
        }
    }

    @ViewBuilder
    private func capeImageContent(image: NSImage) -> some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let containerHeight = geometry.size.height
            let capeAspectRatio: CGFloat = 10.0 / 16.0
            let containerAspectRatio = containerWidth / containerHeight

            let scale: CGFloat = containerAspectRatio > capeAspectRatio
                ? containerHeight / 16.0
                : containerWidth / 10.0

            let offsetX = (containerWidth - 10.0 * scale) / 2.0 - 1.0 * scale
            let offsetY = (containerHeight - 16.0 * scale) / 2.0 - 1.0 * scale

            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: 64.0 * scale, height: 32.0 * scale)
                .offset(x: offsetX, y: offsetY)
                .clipped()
        }
    }
}
