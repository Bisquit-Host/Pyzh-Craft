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
                title: Text("No Local Game"),
                message: Text("Please add a local game first before performing this operation."),
                dismissButton: .default(Text("Confirm"))
            )
        case .noPlayer:
            return Alert(
                title: Text("No Players"),
                message: Text("No player information. Please add player information first before adding games"),
                dismissButton: .default(Text("Confirm"))
            )
        }
    }
}
