import SwiftUI

struct PlayerInfoSectionView: View {
    let player: Player?
    @Binding var currentModel: PlayerSkinService.PublicSkinInfo.SkinModel
    
    var body: some View {
        VStack(spacing: 16) {
            if let player = player {
                VStack(spacing: 12) {
                    MinecraftSkinUtils(
                        type: player.isOnlineAccount ? .url : .asset,
                        src: player.avatarName,
                        size: 88
                    )
                    
                    Text(player.name)
                        .font(.title2.bold())
                    
                    HStack(spacing: 4) {
                        Text("Classic")
                            .font(.caption)
                            .foregroundColor(currentModel == .classic ? .primary : .secondary)
                        
                        Toggle(isOn: Binding(
                            get: { currentModel == .slim },
                            set: { currentModel = $0 ? .slim : .classic }
                        )) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        
                        Text("Slim")
                            .font(.caption)
                            .foregroundColor(currentModel == .slim ? .primary : .secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    String(localized: "No Player Selected"),
                    systemImage: "person",
                    description: Text("Please add a player first")
                )
            }
        }.frame(width: 280)
    }
}
