import SwiftUI

// MARK: - GameNameInputView
struct GameNameInputView: View {
    @Binding var gameName: String
    @Binding var isGameNameDuplicate: Bool
    @FocusState private var isGameNameFocused: Bool
    @State private var showErrorPopover = false
    let isDisabled: Bool
    let gameSetupService: GameSetupUtil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.subheadline)
                .foregroundColor(.primary)
            TextField(
                "Enter game name",
                text: $gameName
            )
            .textFieldStyle(.roundedBorder)
            .foregroundColor(.primary)
            .focused($isGameNameFocused)
            .focusEffectDisabled()
            .disabled(isDisabled)
            .popover(isPresented: $showErrorPopover, arrowEdge: .trailing) {
                if isGameNameDuplicate {
                    Text("Duplicate")
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
            .onChange(of: gameName) { _, newName in
                Task {
                    let isDuplicate = await gameSetupService.checkGameNameDuplicate(newName)
                    await MainActor.run {
                        if isDuplicate != isGameNameDuplicate {
                            isGameNameDuplicate = isDuplicate
                        }
                        showErrorPopover = isDuplicate
                    }
                }
            }
        }
    }
}
