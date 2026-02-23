import SwiftUI

struct VersionSelectionView: View {
    @Binding var selectedGameVersion: String
    @Binding var selectedModPackVersion: ModrinthProjectDetailVersion?
    
    let availableGameVersions: [String]
    let filteredModPackVersions: [ModrinthProjectDetailVersion]
    let isLoadingModPackVersions: Bool
    let isProcessing: Bool
    
    let onGameVersionChange: (String) -> Void
    let onModPackVersionAppear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            gameVersionPicker
            if !selectedGameVersion.isEmpty {
                modPackVersionPicker
            }
        }
    }
    
    private var gameVersionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Game Version")
                .foregroundColor(.primary)
            
            Picker(
                "",
                selection: $selectedGameVersion
            ) {
                Text("Select game version").tag("")
                
                ForEach(availableGameVersions, id: \.self) {
                    Text($0)
                        .tag($0)
                }
            }
            .pickerStyle(.menu)
            .font(.subheadline)
            .labelsHidden()
            .onChange(of: selectedGameVersion) { _, newValue in
                onGameVersionChange(newValue)
            }
        }
    }
    
    private var modPackVersionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoadingModPackVersions {
                Text("Modpack Version")
                    .foregroundColor(.primary)
                HStack {
                    ProgressView()
                        .controlSize(.small).frame(maxWidth: .infinity)
                }
            } else if !selectedGameVersion.isEmpty {
                Text("Modpack Version")
                    .foregroundColor(.primary)
                Picker(
                    "",
                    selection: $selectedModPackVersion
                ) {
                    ForEach(filteredModPackVersions, id: \.id) {
                        Text($0.name)
                            .tag($0 as ModrinthProjectDetailVersion?)
                    }
                }
                .labelsHidden()
                .font(.subheadline)
                .pickerStyle(.menu)
                .onAppear {
                    onModPackVersionAppear()
                }
            }
        }
    }
}
