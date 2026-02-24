import SwiftUI

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
            guard !isSelected else { return }

            selectedCapeId = id

            if let imageURL = imageURL {
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
        .disabled(isSelected)
    }

    private func capeIconContainer(isSelected: Bool, imageURL: String?, isSystemOption: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray.opacity(0.1))
                .frame(width: 50, height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.accentColor : .gray.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            if let imageURL = imageURL {
                CapeTextureView(imageURL: imageURL)
                    .id(imageURL)
                    .frame(width: 42, height: 62)
                    .clipped()
                    .cornerRadius(6)
            } else if isSystemOption {
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
    }
}
