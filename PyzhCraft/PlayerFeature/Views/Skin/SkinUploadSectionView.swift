import SwiftUI
import UniformTypeIdentifiers
import SkinRenderKit

struct SkinUploadSectionView: View {
    @Binding var currentModel: PlayerSkinService.PublicSkinInfo.SkinModel
    @Binding var showingFileImporter: Bool
    @Binding var selectedSkinImage: NSImage?
    @Binding var selectedSkinPath: String?
    @Binding var currentSkinRenderImage: NSImage?
    @Binding var selectedCapeLocalPath: String?
    @Binding var selectedCapeImage: NSImage?
    @Binding var selectedCapeImageURL: String?
    @Binding var isCapeLoading: Bool
    @Binding var capeLoadCompleted: Bool
    @Binding var showingSkinPreview: Bool

    let onSkinDropped: (NSImage) -> Void
    let onDrop: ([NSItemProvider]) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("skin.upload".localized()).font(.headline)

            skinRenderArea

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drop skin file here or click to select")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("PNG 64×64 or legacy 64×32")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
                Spacer()
                Button {
                    openSkinPreviewWindow()
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .disabled(selectedSkinImage == nil && currentSkinRenderImage == nil && selectedSkinPath == nil)
            }
        }
    }

    private var skinRenderArea: some View {
        let playerModel = convertToPlayerModel(currentModel)
        // Determine whether there is a SkinRenderView displayed (when there is a skin, SkinRenderView will handle dragging)
        // Judgment based on whether there is skin data, does not rely on capeLoadCompleted
        // Avoid mistakenly thinking that no view is rendered during cloak loading, causing the view structure to switch back and forth
        let hasSkinRenderView = (selectedSkinImage != nil || currentSkinRenderImage != nil || selectedSkinPath != nil)

        return skinRenderContent(playerModel: playerModel)
            .frame(height: 220)
            .onTapGesture { showingFileImporter = true }
            .conditionalDrop(isEnabled: !hasSkinRenderView, perform: onDrop)
    }

    @ViewBuilder
    private func skinRenderContent(playerModel: PlayerModel) -> some View {
        ZStack {
            // The bottom layer always decides whether to render the character based on skin data
            // No longer switch view types back and forth due to cloak loading status, preventing SceneKit views from being destroyed and rebuilt
            Group {
                if let image = selectedSkinImage ?? currentSkinRenderImage {
                    SkinRenderView(
                        skinImage: image,
                        // Cloak update process:
                        // 1. selectedCapeImage @Binding change (user operation/initialization)
                        // 2. SwiftUI body re-evaluates and creates/updates SceneKitCharacterViewRepresentable
                        // 3. updateNSViewController is called
                        // 4. Check whether capeImage exists and call updateCapeTexture(image:) or removeCapeTexture()
                        // 5. applyCapeUpdate checks whether the instances are the same (!==), if different, updates and calls rebuildCharacter()
                        // 6. Rebuild or incrementally update character nodes, including new cloak textures
                        // 7. SceneKit renders new character model
                        capeImage: $selectedCapeImage,
                        playerModel: playerModel,
                        rotationDuration: 0,
                        backgroundColor: NSColor.clear,
                        onSkinDropped: { dropped in
                            onSkinDropped(dropped)
                        },
                        onCapeDropped: { _ in }
                    )
                } else if let skinPath = selectedSkinPath {
                    SkinRenderView(
                        texturePath: skinPath,
                        // The cape update process is the same as above: selectedCapeImage change → SwiftUI re-evaluation → SkinRenderView internal processing update
                        capeImage: $selectedCapeImage,
                        playerModel: playerModel,
                        rotationDuration: 0,
                        backgroundColor: NSColor.clear,
                        onSkinDropped: { dropped in
                            onSkinDropped(dropped)
                        },
                        onCapeDropped: { _ in }
                    )
                } else {
                    Color.clear
                }
            }
        }
    }

    private func convertToPlayerModel(_ skinModel: PlayerSkinService.PublicSkinInfo.SkinModel) -> PlayerModel {
        switch skinModel {
        case .classic:
            return .steve
        case .slim:
            return .alex
        }
    }

    /// Open skin preview window
    private func openSkinPreviewWindow() {
        let playerModel = convertToPlayerModel(currentModel)
        // Store to WindowDataStore
        WindowDataStore.shared.skinPreviewData = SkinPreviewData(
            skinImage: selectedSkinImage ?? currentSkinRenderImage,
            skinPath: selectedSkinPath,
            capeImage: selectedCapeImage,
            playerModel: playerModel
        )
        // open window
        WindowManager.shared.openWindow(id: .skinPreview)
    }
}

// MARK: - View Extension for Conditional Drop
extension View {
    /// Conditionally apply drag handling modifiers
    @ViewBuilder
    func conditionalDrop(isEnabled: Bool, perform: @escaping ([NSItemProvider]) -> Bool) -> some View {
        if isEnabled {
            self.onDrop(of: [UTType.image.identifier, UTType.fileURL.identifier], isTargeted: nil, perform: perform)
        } else {
            self
        }
    }
}
