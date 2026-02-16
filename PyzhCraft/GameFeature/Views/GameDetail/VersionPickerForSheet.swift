import SwiftUI

// MARK: - version selection block
struct VersionPickerForSheet: View {
    let project: ModrinthProject
    let resourceType: String
    @Binding var selectedGame: GameVersionInfo?
    @Binding var selectedVersion: ModrinthProjectDetailVersion?
    @Binding var availableVersions: [ModrinthProjectDetailVersion]
    @Binding var mainVersionId: String
    var onVersionChange: ((ModrinthProjectDetailVersion?) -> Void)?
    @State private var isLoading = false
    @State private var error: GlobalError?

    var body: some View {
        VStack(alignment: .leading) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else if !availableVersions.isEmpty {
                Text(project.title).font(.headline).bold().frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                Picker(
                    "Select Version",
                    selection: $selectedVersion
                ) {
                    ForEach(availableVersions, id: \.id) { version in
                        if resourceType == "shader" {
                            let loaders = version.loaders.joined(
                                separator: ", "
                            )
                            Text("\(version.name) (\(loaders))").tag(
                                Optional(version)
                            )
                        } else {
                            Text(version.name).tag(Optional(version))
                        }
                    }
                }
                .pickerStyle(.menu)
            } else {
                Text("No Version Available")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear(perform: loadVersions)
        .onChange(of: selectedGame) { loadVersions() }
        .onChange(of: selectedVersion) { _, newValue in
            // Update major version ID
            if let newValue = newValue {
                mainVersionId = newValue.id
            } else {
                mainVersionId = ""
            }
            onVersionChange?(newValue)
        }
    }

    private func loadVersions() {
        isLoading = true
        error = nil
        Task {
            do {
                try await loadVersionsThrowing()
            } catch {
                let globalError = GlobalError.from(error)
                _ = await MainActor.run {
                    self.error = globalError
                    self.isLoading = false
                }
            }
        }
    }

    private func loadVersionsThrowing() async throws {
        guard !project.projectId.isEmpty else {
            throw GlobalError.validation(
                chineseMessage: "项目ID不能为空",
                i18nKey: "Project ID Empty",
                level: .notification
            )
        }

        guard let game = selectedGame else {
            _ = await MainActor.run {
                availableVersions = []
                selectedVersion = nil
                mainVersionId = ""
                isLoading = false
            }
            return
        }

        // Use server-side filtering methods to reduce client-side filtering
        let filtered = try await ModrinthService.fetchProjectVersionsFilter(
            id: project.projectId,
            selectedVersions: [game.gameVersion],
            selectedLoaders: [game.modLoader],
            type: resourceType
        )

        _ = await MainActor.run {
            availableVersions = filtered
            selectedVersion = filtered.first
            // Update major version ID
            if let firstVersion = filtered.first {
                mainVersionId = firstVersion.id
            } else {
                mainVersionId = ""
            }
            isLoading = false
        }
    }
}
