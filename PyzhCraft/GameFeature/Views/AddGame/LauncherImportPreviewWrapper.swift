import SwiftUI

struct LauncherImportPreviewWrapper: View {
    @State private var isDownloading = false
    @State private var isFormValid = false
    @State private var triggerConfirm = false
    @State private var triggerCancel = false

    var body: some View {
        LauncherImportView(
            configuration: GameFormConfiguration(
                isDownloading: $isDownloading,
                isFormValid: $isFormValid,
                triggerConfirm: $triggerConfirm,
                triggerCancel: $triggerCancel,
                onCancel: {},
                onConfirm: {}
            )
        )
        .environmentObject(GameRepository())
        .environmentObject(PlayerListViewModel())
        .frame(width: 600, height: 500)
        .padding()
    }
}
