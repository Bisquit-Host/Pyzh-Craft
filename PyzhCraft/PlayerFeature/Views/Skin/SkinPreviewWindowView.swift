import SwiftUI
import SkinRenderKit

/// Skin preview window view
struct SkinPreviewWindowView: View {
    let skinImage: NSImage?
    let skinPath: String?
    let capeImage: NSImage?
    let playerModel: PlayerModel
    
    @State private var capeBinding: NSImage?
    // Use @State to manage data so it can be cleaned up when the window is closed
    @State private var currentSkinImage: NSImage?
    @State private var currentSkinPath: String?
    
    init(
        skinImage: NSImage?,
        skinPath: String?,
        capeImage: NSImage?,
        playerModel: PlayerModel
    ) {
        self.skinImage = skinImage
        self.skinPath = skinPath
        self.capeImage = capeImage
        self.playerModel = playerModel
        self._capeBinding = State(initialValue: capeImage)
        // Set the current value during initialization
        self._currentSkinImage = State(initialValue: skinImage)
        self._currentSkinPath = State(initialValue: skinPath)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if currentSkinImage != nil || currentSkinPath != nil {
                previewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 1200, height: 800)
        .onDisappear {
            clearAllData()
        }
    }
    
    @ViewBuilder private var previewContent: some View {
        if let image = currentSkinImage {
            SkinRenderView(
                skinImage: image,
                capeImage: $capeBinding,
                playerModel: playerModel,
                rotationDuration: 0,
                backgroundColor: NSColor.clear,
                onSkinDropped: { _ in },
                onCapeDropped: { _ in }
            )
        }
    }
    
    /// Clean all data
    private func clearAllData() {
        // Clear the skin data, which will cause the SkinRenderView to be removed, triggering its cleanup logic
        currentSkinImage = nil
        currentSkinPath = nil
        capeBinding = nil
    }
}
