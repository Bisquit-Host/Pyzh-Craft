import SwiftUI

// MARK: - GameNameValidator
@MainActor
class GameNameValidator: ObservableObject {
    @Published var gameName: String = ""
    @Published var isGameNameDuplicate: Bool = false

    private let gameSetupService: GameSetupUtil

    init(gameSetupService: GameSetupUtil) {
        self.gameSetupService = gameSetupService
    }

    /// Verify if game name is duplicate
    func validateGameName() async {
        guard !gameName.isEmpty else {
            isGameNameDuplicate = false
            return
        }

        let isDuplicate = await gameSetupService.checkGameNameDuplicate(gameName)
        if isDuplicate != isGameNameDuplicate {
            isGameNameDuplicate = isDuplicate
        }
    }

    /// Set the default game name (only set if the current name is empty)
    func setDefaultName(_ name: String) {
        if gameName.isEmpty {
            gameName = name
        }
    }

    func reset() {
        gameName = ""
        isGameNameDuplicate = false
    }

    /// Check if the form is valid
    var isFormValid: Bool {
        !gameName.isEmpty && !isGameNameDuplicate
    }
}
