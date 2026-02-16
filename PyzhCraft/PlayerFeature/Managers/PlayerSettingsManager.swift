import SwiftUI

class PlayerSettingsManager: ObservableObject {
    static let shared = PlayerSettingsManager()

    @AppStorage("currentPlayerId")
    var currentPlayerId = "" {
        didSet { objectWillChange.send() }
    }

    private init() {}
}
