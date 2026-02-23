import SwiftUI

// MARK: - dependency related status
struct DependencyState {
    var dependencies: [ModrinthProjectDetail] = []
    var versions: [String: [ModrinthProjectDetailVersion]] = [:]
    var selected: [String: ModrinthProjectDetailVersion?] = [:]
    var isLoading = false
}

// MARK: - dependent block
struct DependencySectionView: View {
    @Binding var state: DependencyState

    var body: some View {
        if state.isLoading {
            ProgressView().controlSize(.small)
        } else if !state.dependencies.isEmpty {
            spacerView()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(state.dependencies, id: \.id) { dep in
                    VStack(alignment: .leading) {
                        Text(dep.title).font(.headline).bold()
                        
                        if let versions = state.versions[dep.id],
                            !versions.isEmpty {
                            Picker(
                                "Dependency Version",
                                selection:
                                    Binding(
                                    get: {
                                        state.selected[dep.id] ?? versions.first
                                    },
                                    set: { state.selected[dep.id] = $0 }
                                )
                            ) {
                                ForEach(versions, id: \.id) {
                                    Text($0.name)
                                        .tag(Optional($0))
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            Text("No Version")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}
