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
                                "global_resource.dependency_version".localized(),
                                selection:
                                    Binding(
                                    get: {
                                        state.selected[dep.id] ?? versions.first
                                    },
                                    set: { state.selected[dep.id] = $0 }
                                )
                            ) {
                                ForEach(versions, id: \.id) { v in
                                    Text(v.name).tag(Optional(v))
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            Text("global_resource.no_version".localized())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}
