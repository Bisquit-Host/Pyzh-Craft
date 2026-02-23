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

struct CapeSelectionView: View {
    let playerProfile: MinecraftProfileResponse?
    @Binding var selectedCapeId: String?
    @Binding var selectedCapeImageURL: String?
    @Binding var selectedCapeImage: NSImage?
    let onCapeSelected: (String?, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cape").font(.headline)

            if let playerProfile = playerProfile, let capes = playerProfile.capes, !capes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        capeOption(id: nil, name: String(localized: "No Cape"), isSystemOption: true)
                        ForEach(capes, id: \.id) {
                            capeOption(id: $0.id, name: $0.alias ?? String(localized: "Cape"), imageURL: $0.url)
                        }
                    }
                    .padding(4)
                }
            } else {
                Text("No capes available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func capeOption(id: String?, name: String, imageURL: String? = nil, isSystemOption: Bool = false) -> some View {
        let isSelected = selectedCapeId == id

        return Button {
            // The selected cloak does not allow repeated clicks
            guard !isSelected else { return }

            selectedCapeId = id
            if let imageURL = imageURL {
                // Load NSImage asynchronously
                DispatchQueue.global(qos: .userInitiated).async {
                    if let url = URL(string: imageURL.httpToHttps()),
                        let data = try? Data(contentsOf: url),
                        let nsImage = NSImage(data: data) {
                        DispatchQueue.main.async {
                            selectedCapeImageURL = imageURL
                            selectedCapeImage = nsImage
                        }
                    }
                }
            }
            onCapeSelected(id, imageURL)
        } label: {
            VStack(spacing: 6) {
                capeIconContainer(isSelected: isSelected, imageURL: imageURL, isSystemOption: isSystemOption)
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .frame(width: 42)
            }
        }
        .buttonStyle(.plain)
        // Only the currently selected cloak button is disabled, others can still be selected
        .disabled(isSelected)
    }

    private func capeIconContainer(isSelected: Bool, imageURL: String?, isSystemOption: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .frame(width: 50, height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            if let imageURL = imageURL {
                // Cloak display is loaded using URL by default
                CapeTextureView(imageURL: imageURL)
                    .id(imageURL).frame(width: 42, height: 62).clipped().cornerRadius(6)
            } else if isSystemOption {
                Image(systemName: "xmark").font(.system(size: 16)).foregroundColor(.secondary)
            }
        }
    }
}
