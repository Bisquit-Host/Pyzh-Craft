import SwiftUI

struct ServerAddressEditView: View {
    let server: ServerAddress?
    let gameName: String
    let onRefresh: (() -> Void)?
    @Environment(\.dismiss)
    private var dismiss

    @State private var serverName: String
    @State private var serverAddress: String
    @State private var serverPort: String
    @State private var isHidden: Bool
    @State private var acceptTextures: Bool
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showError = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage = ""

    var isNewServer: Bool {
        server == nil
    }

    init(server: ServerAddress? = nil, gameName: String, onRefresh: (() -> Void)? = nil) {
        self.server = server
        self.gameName = gameName
        self.onRefresh = onRefresh
        if let server = server {
            _serverName = State(initialValue: server.name)
            _serverAddress = State(initialValue: server.address)
            _serverPort = State(initialValue: server.port > 0 ? String(server.port) : "")
            _isHidden = State(initialValue: server.hidden)
            _acceptTextures = State(initialValue: server.acceptTextures)
        } else {
            _serverName = State(initialValue: "")
            _serverAddress = State(initialValue: "")
            _serverPort = State(initialValue: "")
            _isHidden = State(initialValue: false)
            _acceptTextures = State(initialValue: false)
        }
    }

    var body: some View {
        CommonSheetView(
            header: { headerView },
            body: { bodyView },
            footer: { footerView }
        )
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog("Delete Server", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteServer()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(String(format: String(localized: "Are you sure you want to delete server \"\(serverName)\"? This action cannot be undone.")))
        }
    }

    private var headerView: some View {
        HStack {
            Text(
                isNewServer
                ? LocalizedStringKey("Add Server")
                : LocalizedStringKey("Edit Server")
            )
            .font(.headline)
            Spacer()
            if let shareText = shareTextForServer, !shareText.isEmpty {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shareTextForServer: String? {
        let address = serverAddress.trimmingCharacters(in: .whitespaces)
        let port = serverPort.trimmingCharacters(in: .whitespaces)

        if !address.isEmpty {
            if !port.isEmpty {
                return "\(address):\(port)"
            } else {
                return address
            }
        }

        if let existing = server {
            return existing.fullAddress
        }

        return nil
    }

    private var bodyView: some View {
        VStack(alignment: .leading) {
            Text("Server Name")
            TextField("Server Name", text: $serverName)
                .textFieldStyle(.roundedBorder)
                .padding(.bottom, 20)

            HStack {
                VStack(alignment: .leading) {
                    Text("Server Address")
                    TextField("Server Address", text: $serverAddress)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: serverAddress) { _, newValue in
                            if let colonIndex = newValue.lastIndex(of: ":") {
                                let afterColon = String(newValue[newValue.index(after: colonIndex)...])
                                if let port = Int(afterColon), port > 0 && port <= 65535 {
                                    let addressOnly = String(newValue[..<colonIndex])
                                    if serverAddress != addressOnly {
                                        serverAddress = addressOnly
                                    }
                                    if serverPort != afterColon {
                                        serverPort = afterColon
                                    }
                                }
                            }
                        }
                }
                VStack(alignment: .leading) {
                    Text("Port")
                    TextField("25565 (Optional)", text: $serverPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                }
            }
            .padding(.bottom, 20)

            HStack {
                Toggle("Hidden", isOn: $isHidden)
                Spacer()
                Toggle("Accept Textures", isOn: $acceptTextures)
            }
            .padding(.bottom, 20)
        }
    }

    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving || isDeleting)
            if !isNewServer {
                Button("Delete") {
                    saveServer()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(isSaving || isDeleting)
            }
            Spacer()
            Button("Save") {
                saveServer()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving || isDeleting || !isFormValid)
        }
    }

    private var isFormValid: Bool {
        let trimmedName = serverName.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = serverAddress.trimmingCharacters(in: .whitespaces)
        let trimmedPort = serverPort.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty && !trimmedAddress.isEmpty else {
            return false
        }

        if !trimmedPort.isEmpty {
            return Int(trimmedPort) != nil
        }

        return true
    }

    private var portValue: Int? {
        let trimmedPort = serverPort.trimmingCharacters(in: .whitespaces)
        if trimmedPort.isEmpty {
            return nil
        }
        return Int(trimmedPort)
    }

    private func saveServer() {
        let trimmedName = serverName.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = serverAddress.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty && !trimmedAddress.isEmpty else {
            errorMessage = String(localized: "Please fill in all required fields")
            showError = true
            return
        }

        let port = portValue ?? 0

        isSaving = true

        Task {
            do {
                var currentServers = try await ServerAddressService.shared.loadServerAddresses(for: gameName)

                if let existingServer = server {
                    let updatedServer = ServerAddress(
                        id: existingServer.id,
                        name: trimmedName,
                        address: trimmedAddress,
                        port: port,
                        hidden: isHidden,
                        icon: existingServer.icon,
                        acceptTextures: acceptTextures
                    )

                    if let index = currentServers.firstIndex(where: { $0.id == existingServer.id }) {
                        currentServers[index] = updatedServer
                    } else {
                        currentServers.append(updatedServer)
                    }
                } else {
                    let newServer = ServerAddress(
                        name: trimmedName,
                        address: trimmedAddress,
                        port: port,
                        hidden: isHidden,
                        icon: nil,
                        acceptTextures: acceptTextures
                    )
                    currentServers.append(newServer)
                }

                try await ServerAddressService.shared.saveServerAddresses(currentServers, for: gameName)

                await MainActor.run {
                    isSaving = false
                    dismiss()
                    onRefresh?()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func deleteServer() {
        guard let serverToDelete = server else {
            return
        }

        isDeleting = true

        Task {
            do {
                var currentServers = try await ServerAddressService.shared.loadServerAddresses(for: gameName)

                currentServers.removeAll { $0.id == serverToDelete.id }

                try await ServerAddressService.shared.saveServerAddresses(currentServers, for: gameName)

                await MainActor.run {
                    isDeleting = false
                    dismiss()
                    onRefresh?()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
