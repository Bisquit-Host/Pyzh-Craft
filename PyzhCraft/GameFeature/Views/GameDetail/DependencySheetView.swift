import SwiftUI

struct DependencySheetView: View {
    @ObservedObject var viewModel: DependencySheetViewModel
    @Binding var isDownloadingAllDependencies: Bool
    @Binding var isDownloadingMainResourceOnly: Bool
    let projectDetail: ModrinthProjectDetail
    @State private var error: GlobalError?

    let onDownloadAll: () async -> Void
    let onDownloadMainOnly: () async -> Void

    var body: some View {
        CommonSheetView(
            header: {
                Text("Required Mods to Download")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                if viewModel.isLoadingDependencies {
                    ProgressView().frame(height: 100).controlSize(.small)
                } else {
                    ModrinthProjectTitleView(projectDetail: projectDetail)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.missingDependencies, id: \.id) { dep in
                            let versions =
                                viewModel.dependencyVersions[dep.id] ?? []
                            if !versions.isEmpty {
                                VStack(alignment: .leading) {
                                    HStack(alignment: .center) {
                                        Text(dep.title)
                                            .font(.headline)
                                        Spacer()
                                    }
                                    Picker(
                                        "Select Version:",
                                        selection: Binding(
                                            get: {
                                                viewModel
                                                    .selectedDependencyVersion[
                                                        dep.id
                                                    ]
                                                    ?? (versions.first?.id ?? "")
                                            },
                                            set: {
                                                viewModel
                                                    .selectedDependencyVersion[
                                                        dep.id
                                                    ] = $0
                                            }
                                        )
                                    ) {
                                        ForEach(versions, id: \.id) { v in
                                            Text(v.name).tag(v.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            },
            footer: {
                if viewModel.isLoadingDependencies {
                    HStack {
                        Spacer()
                        Button("Close") {
                            viewModel.showDependenciesSheet = false
                        }
                    }
                } else if !viewModel.missingDependencies.isEmpty {
                    HStack {
                        Button("Close") {
                            viewModel.showDependenciesSheet = false
                        }
                        Spacer()

                        let hasDownloading = viewModel.missingDependencies
                            .contains {
                                viewModel.dependencyDownloadStates[$0.id]
                                    == .downloading
                            }
                        Button {
                            Task {
                                await onDownloadMainOnly()
                            }
                        } label: {
                            if isDownloadingMainResourceOnly {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Download Main Only")
                            }
                        }
                        .disabled(
                            isDownloadingAllDependencies
                                || isDownloadingMainResourceOnly
                        )
                        switch viewModel.overallDownloadState {
                        case .idle:
                            Button {
                                isDownloadingAllDependencies = true
                                Task {
                                    await onDownloadAll()
                                    isDownloadingAllDependencies = false
                                }
                            } label: {
                                if isDownloadingAllDependencies || hasDownloading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Download All And Continue")
                                }
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(
                                isDownloadingAllDependencies || hasDownloading
                            )

                        case .failed:
                            Button {
                                isDownloadingAllDependencies = true
                                Task {
                                    await onDownloadAll()
                                    isDownloadingAllDependencies = false
                                }
                            } label: {
                                if isDownloadingAllDependencies || hasDownloading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Continue")
                                }
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(
                                isDownloadingAllDependencies || hasDownloading
                                    || !viewModel.allDependenciesDownloaded
                            )

                        case .retrying:
                            EmptyView()
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        Button("Close") {
                            viewModel.showDependenciesSheet = false
                        }
                    }
                }
            }
        )
        .alert("Download Error", isPresented: .constant(error != nil)) {
            Button("Close") {
                error = nil
            }
        } message: {
            if let error {
                Text(error.chineseMessage)
            }
        }
    }

    private func handleDownloadError(_ error: Error) {
        let globalError = GlobalError.from(error)
        Logger.shared.error("依赖下载错误: \(globalError.chineseMessage)")
        GlobalErrorHandler.shared.handle(globalError)
        
        Task { @MainActor in
            self.error = globalError
        }
    }
}
