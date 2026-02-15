import SwiftUI

// MARK: - Game selection block
struct CommonSheetGameBody: View {
    let compatibleGames: [GameVersionInfo]
    @Binding var selectedGame: GameVersionInfo?

    var body: some View {
        Picker(
            "global_resource.select_game".localized(),
            selection: $selectedGame
        ) {
            Text("global_resource.please_select_game".localized()).tag(
                GameVersionInfo?(nil)
            )
            ForEach(compatibleGames, id: \.id) { game in
                (Text("\(game.gameName)-")
                    + Text("\(game.gameVersion)-").foregroundStyle(.secondary)
                    + Text("\(game.modLoader)-")
                    + Text("\(game.modVersion)").foregroundStyle(.secondary))
                    .tag(Optional(game))
            }
        }
        .pickerStyle(.menu)
    }
}
