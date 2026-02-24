import SwiftUI

struct PlayerAvatarView: View {
    let player: Player
    var size: CGFloat

    var body: some View {
        MinecraftSkinUtils(type: player.isOnlineAccount ? .url : .asset, src: player.avatarName, size: size)
            .id(player.id)
            .id(player.avatarName)
    }
}
