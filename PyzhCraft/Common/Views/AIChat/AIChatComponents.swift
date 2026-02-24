import SwiftUI

/// AI avatar view
struct AIAvatarView: View {
    let size: CGFloat
    let url: String

    init(size: CGFloat, url: String = "https://mcskins.top/assets/snippets/download/skin.php?n=7050") {
        self.size = size
        self.url = url
    }

    var body: some View {
        MinecraftSkinUtils(
            type: .url,
            src: url,
            size: size
        )
    }
}
