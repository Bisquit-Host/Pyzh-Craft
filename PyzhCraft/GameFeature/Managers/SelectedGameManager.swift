import SwiftUI

/// Select game manager
/// The main view shares the currently selected game ID with the settings page
class SelectedGameManager: ObservableObject {
    // MARK: - Singleton instance
    static let shared = SelectedGameManager()

    /// The currently selected game ID
    @Published var selectedGameId: String? {
        didSet {
            // Automatically notify observers when the game ID changes
            objectWillChange.send()
        }
    }

    /// Whether the advanced settings tab should be opened
    @Published var shouldOpenAdvancedSettings = false {
        didSet {
            objectWillChange.send()
        }
    }

    private init() {
    }

    /// Set selected game ID
    /// - Parameter gameId: game ID, if nil, clear the selected state
    func setSelectedGame(_ gameId: String?) {
        selectedGameId = gameId
    }

    /// Clear selected games
    func clearSelection() {
        selectedGameId = nil
        shouldOpenAdvancedSettings = false
    }

    /// Settings selected game and mark should open advanced settings
    /// - Parameter gameId: game ID
    func setSelectedGameAndOpenAdvancedSettings(_ gameId: String?) {
        selectedGameId = gameId
        shouldOpenAdvancedSettings = true
    }
}
