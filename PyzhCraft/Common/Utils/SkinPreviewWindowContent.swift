import SwiftUI

/// Skin preview window content view (used to observe WindowDataStore changes)
struct SkinPreviewWindowContent: View {
    @ObservedObject private var windowDataStore = WindowDataStore.shared

    var body: some View {
        Group {
            if let data = windowDataStore.skinPreviewData {
                SkinPreviewWindowView(
                    skinImage: data.skinImage,
                    skinPath: data.skinPath,
                    capeImage: data.capeImage,
                    playerModel: data.playerModel
                )
            } else {
                EmptyView()
            }
        }
    }
}
