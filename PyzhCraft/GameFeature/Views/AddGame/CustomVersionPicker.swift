import SwiftUI

private enum Constants {
    static let versionPopoverMinWidth: CGFloat = 320
    static let versionPopoverMaxHeight: CGFloat = 360
    static let versionPopoverMinHeight: CGFloat = 200
}

struct CustomVersionPicker: View {
    @Binding var selected: String
    let availableVersions: [String]
    @Binding var time: String
    let onVersionSelected: (String) async -> String  // New: version selection callback, return time information
    @State private var showMenu = false
    @State private var error: GlobalError?

    private var versionItems: [FilterItem] {
        availableVersions.map { FilterItem(id: $0, name: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Version")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Text(
                    time.isEmpty ? "" : String(localized: "Released: ") + time
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            versionInput
        }
        .alert("Validation Error", isPresented: .constant(error != nil)) {
            Button("Close") {
                error = nil
            }
        } message: {
            if let error {
                Text(error.chineseMessage)
            }
        }
    }

    private var versionInput: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.quaternaryLabelColor), lineWidth: 1)
                .background(Color(.textBackgroundColor))
            HStack {
                if selected.isEmpty {
                    Text("Select game version")
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                } else {
                    Text(selected).foregroundColor(.primary)
                        .padding(.horizontal, 8)
                }
                Spacer()
            }
        }
        .frame(height: 22)
        .onTapGesture {
            if !availableVersions.isEmpty {
                showMenu.toggle()
            } else {
                handleEmptyVersionsError()
            }
        }
        .popover(isPresented: $showMenu, arrowEdge: .trailing) {
            versionPopoverContent
        }
    }

    private var versionPopoverContent: some View {
        VersionGroupedView(
            items: versionItems,
            selectedItem: Binding<String?>(
                get: { selected.isEmpty ? nil : selected },
                set: { newValue in
                    if let newValue = newValue {
                        selected = newValue
                        showMenu = false
                        // Use version time mapping to set time information
                        Task {
                            time = await onVersionSelected(newValue)
                        }
                    }
                }
            )
        ) { version in
            selected = version
            showMenu = false
            // Use version time mapping to set time information
            Task {
                time = await onVersionSelected(version)
            }
        }
        .frame(
            minWidth: Constants.versionPopoverMinWidth,
            maxWidth: Constants.versionPopoverMinWidth,
            minHeight: Constants.versionPopoverMinHeight,
            maxHeight: Constants.versionPopoverMaxHeight
        )
    }

    private func handleEmptyVersionsError() {
        let globalError = GlobalError.resource(
            i18nKey: "No Versions Available",
            level: .notification
        )
        Logger.shared.error("版本选择器错误: \(globalError.chineseMessage)")
        GlobalErrorHandler.shared.handle(globalError)
        error = globalError
    }

    private func handleVersionSelectionError(_ error: Error) {
        let globalError = GlobalError.from(error)
        Logger.shared.error("版本选择错误: \(globalError.chineseMessage)")
        GlobalErrorHandler.shared.handle(globalError)
        self.error = globalError
    }
}
