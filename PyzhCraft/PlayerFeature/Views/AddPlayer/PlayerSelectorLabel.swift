import SwiftUI

struct PlayerSelectorLabel: View {
    let selectedPlayer: Player?
    @StateObject private var statusManager = PlayerStatusManager.shared

    var body: some View {
        if let selectedPlayer = selectedPlayer {
            HStack(spacing: 8) {
                PlayerAvatarView(player: selectedPlayer, size: 32)

                Text(selectedPlayer.name)
                    .foregroundColor(.primary)
                    .font(.system(size: 13).bold())
                    .lineLimit(1)
            }
            .onAppear {
                statusManager.checkStatus(for: selectedPlayer)
            }
        } else {
            EmptyView()
        }
    }
}
