import SwiftUI

/// Alert type enumeration for resource buttons
enum ResourceButtonAlertType: Identifiable {
    case noGame, noPlayer

    var id: Self { self }

    /// Create the corresponding Alert
    var alert: Alert {
        switch self {
        case .noGame:
            return Alert(
                title: Text("no_local_game.title".localized()),
                message: Text("no_local_game.message".localized()),
                dismissButton: .default(Text("common.confirm".localized()))
            )
        case .noPlayer:
            return Alert(
                title: Text("sidebar.alert.no_player.title".localized()),
                message: Text("sidebar.alert.no_player.message".localized()),
                dismissButton: .default(Text("common.confirm".localized()))
            )
        }
    }
}
