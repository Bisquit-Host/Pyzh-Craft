import SwiftUI

// MARK: - Constants
private enum ServerAddressSectionConstants {
    static let maxHeight: CGFloat = 235
    static let verticalPadding: CGFloat = 4
    static let headerBottomPadding: CGFloat = 4
    static let placeholderCount: Int = 5
    static let popoverWidth: CGFloat = 320
    static let popoverMaxHeight: CGFloat = 320
    static let chipPadding: CGFloat = 16
    static let estimatedCharWidth: CGFloat = 10
    static let maxItems: Int = 4  // Display up to 4
    static let maxWidth: CGFloat = 320
}

// MARK: - Server address area view
struct ServerAddressSectionView: View {
    // MARK: - Properties
    let servers: [ServerAddress]
    let isLoading: Bool
    let gameName: String
    let onRefresh: (() -> Void)?

    @State private var showOverflowPopover = false
    @State private var selectedServer: ServerAddress?
    @State private var showAddServer = false
    @State private var serverStatuses: [String: ServerConnectionStatus] = [:]

    init(servers: [ServerAddress], isLoading: Bool, gameName: String, onRefresh: (() -> Void)? = nil) {
        self.servers = servers
        self.isLoading = isLoading
        self.gameName = gameName
        self.onRefresh = onRefresh
    }

    // MARK: - Body
    var body: some View {
        VStack {
            headerView
            if isLoading {
                loadingPlaceholder
            } else {
                contentWithOverflow
            }
        }
        .sheet(item: $selectedServer) { server in
            ServerAddressEditView(server: server, gameName: gameName, onRefresh: onRefresh)
        }
        .sheet(isPresented: $showAddServer) {
            ServerAddressEditView(gameName: gameName, onRefresh: onRefresh)
        }
        .onAppear {
            checkAllServers()
        }
        .onChange(of: servers) { _, _ in
            checkAllServers()
        }
    }

    // MARK: - Header Views
    private var headerView: some View {
        let (_, overflowItems) = computeVisibleAndOverflowItems()
        return HStack {
            headerTitle
            Spacer()
            HStack(spacing: 8) {
                addServerButton
                if !overflowItems.isEmpty {
                    overflowButton
                }
            }
        }
        .padding(.bottom, ServerAddressSectionConstants.headerBottomPadding)
    }

    private var addServerButton: some View {
        Button {
            showAddServer = true
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.plain)
    }

    private var headerTitle: some View {
        Text("Servers")
            .font(.headline)
    }

    private var overflowButton: some View {
        let (_, overflowItems) = computeVisibleAndOverflowItems()
        return Button {
            showOverflowPopover = true
        } label: {
            Text("+\(overflowItems.count)")
                .font(.caption)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showOverflowPopover, arrowEdge: .leading) {
            overflowPopoverContent
        }
    }

    private var overflowPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                FlowLayout {
                    // Show all servers
                    ForEach(servers) { server in
                        ServerAddressChip(
                            title: server.name,
                            address: server.address,
                            port: server.port,
                            isLoading: false,
                            connectionStatus: serverStatuses[server.id] ?? .unknown
                        ) {
                            selectedServer = server
                        }
                    }
                }
                .padding()
            }
            .frame(maxHeight: ServerAddressSectionConstants.popoverMaxHeight)
        }
        .frame(width: ServerAddressSectionConstants.popoverWidth)
    }

    // MARK: - Content Views
    private var loadingPlaceholder: some View {
        ScrollView {
            FlowLayout {
                ForEach(
                    0..<ServerAddressSectionConstants.placeholderCount,
                    id: \.self
                ) { _ in
                    ServerAddressChip(
                        title: "Loading",
                        address: "",
                        port: nil,
                        isLoading: true,
                        connectionStatus: .unknown
                    )
                    .redacted(reason: .placeholder)
                }
            }
        }
        .frame(maxHeight: ServerAddressSectionConstants.maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, ServerAddressSectionConstants.verticalPadding)
    }

    private var contentWithOverflow: some View {
        let (visibleItems, _) = computeVisibleAndOverflowItems()

        return Group {
            if servers.isEmpty {
                Text("No servers")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, ServerAddressSectionConstants.verticalPadding)
                    .padding(.bottom, ServerAddressSectionConstants.verticalPadding)
            } else {
                FlowLayout {
                    ForEach(visibleItems) { server in
                        ServerAddressChip(
                            title: server.name,
                            address: server.address,
                            port: server.port,
                            isLoading: false,
                            connectionStatus: serverStatuses[server.id] ?? .unknown
                        ) {
                            selectedServer = server
                        }
                    }
                }
                .frame(maxHeight: ServerAddressSectionConstants.maxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, ServerAddressSectionConstants.verticalPadding)
                .padding(.bottom, ServerAddressSectionConstants.verticalPadding)
            }
        }
    }

    // MARK: - Helper Methods
    private func computeVisibleAndOverflowItems() -> (
        [ServerAddress], [ServerAddress]
    ) {
        // Display up to 4
        let visibleItems = Array(servers.prefix(ServerAddressSectionConstants.maxItems))
        let overflowItems = Array(servers.dropFirst(ServerAddressSectionConstants.maxItems))

        return (visibleItems, overflowItems)
    }

    /// Concurrently detect the connection status of all servers
    private func checkAllServers() {
        guard !servers.isEmpty else { return }

        // Initialize all server status to detecting
        var initialStatuses: [String: ServerConnectionStatus] = [:]
        for server in servers {
            initialStatuses[server.id] = .checking
        }
        serverStatuses = initialStatuses

        // Concurrent detection of all servers
        Task {
            await withTaskGroup(of: (String, ServerConnectionStatus).self) { group in
                for server in servers {
                    group.addTask {
                        let status = await NetworkUtils.checkServerConnectionStatus(
                            address: server.address,
                            port: server.port,
                            timeout: 5.0
                        )
                        return (server.id, status)
                    }
                }

                for await (serverId, status) in group {
                    await MainActor.run {
                        serverStatuses[serverId] = status
                    }
                }
            }
        }
    }
}

// MARK: - Server Address Chip
struct ServerAddressChip: View {
    let title: String
    let address: String
    let port: Int?
    let isLoading: Bool
    let connectionStatus: ServerConnectionStatus
    let action: (() -> Void)?

    init(
        title: String,
        address: String,
        port: Int? = nil,
        isLoading: Bool,
        connectionStatus: ServerConnectionStatus = .unknown,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.address = address
        self.port = port
        self.isLoading = isLoading
        self.connectionStatus = connectionStatus
        self.action = action
    }

    var body: some View {
        Button(action: action ?? {}) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.caption)
                        .foregroundColor(iconColor)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .frame(maxWidth: 150)
                }
                if !address.isEmpty {
                    if let port = port, port > 0 {
                        Text("\(address):\(String(port))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 150)
                    } else {
                        Text(address)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 150)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.clear)
            )
            .foregroundStyle(.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    /// Return icon color based on connection status
    private var iconColor: Color {
        switch connectionStatus {
        case .success:
            return .green
        case .timeout:
            return .yellow
        case .failed:
            return .red
        case .checking:
            return .blue.opacity(0.5)
        case .unknown:
            return .secondary
        }
    }
}

// MARK: - Server Address Row
struct ServerAddressRow: View {
    let server: ServerAddress

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)

                Text(server.fullAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(server.fullAddress, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Server Address Edit View
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
    @State private var isSaving: Bool = false
    @State private var isDeleting: Bool = false
    @State private var showError: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var errorMessage: String = ""

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
            // If the port is 0, it means it is not set and is displayed as empty
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

    /// The shared text of the current server (the address and port being edited are used first)
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
                            // If the address contains a port, it is automatically separated into the port field
                            if let colonIndex = newValue.lastIndex(of: ":") {
                                let afterColon = String(newValue[newValue.index(after: colonIndex)...])
                                if let port = Int(afterColon), port > 0 && port <= 65535 {
                                    // The address contains a valid port
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

        // Name and address are required, port is optional
        guard !trimmedName.isEmpty && !trimmedAddress.isEmpty else {
            return false
        }

        // Must be a valid number if port is not empty
        if !trimmedPort.isEmpty {
            return Int(trimmedPort) != nil
        }

        return true
    }

    /// Get the port number, or nil if empty
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

        // Port is optional. If it is empty, the port will not be saved (saved as 0, indicating not set)
        let port = portValue ?? 0

        isSaving = true

        Task {
            do {
                // Get current server list
                var currentServers = try await ServerAddressService.shared.loadServerAddresses(for: gameName)

                if let existingServer = server {
                    // Edit Mode: Update an existing server
                    let updatedServer = ServerAddress(
                        id: existingServer.id,
                        name: trimmedName,
                        address: trimmedAddress,
                        port: port,
                        hidden: isHidden,
                        icon: existingServer.icon,
                        acceptTextures: acceptTextures
                    )

                    // Find and update servers
                    if let index = currentServers.firstIndex(where: { $0.id == existingServer.id }) {
                        currentServers[index] = updatedServer
                    } else {
                        // If not found, add new
                        currentServers.append(updatedServer)
                    }
                } else {
                    // New mode: Add new server
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

                // Save server list
                try await ServerAddressService.shared.saveServerAddresses(currentServers, for: gameName)

                await MainActor.run {
                    isSaving = false
                    dismiss()
                    // Refresh server list
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

    /// Delete server
    private func deleteServer() {
        guard let serverToDelete = server else {
            return
        }

        isDeleting = true

        Task {
            do {
                // Get current server list
                var currentServers = try await ServerAddressService.shared.loadServerAddresses(for: gameName)

                // Remove the server to be deleted
                currentServers.removeAll { $0.id == serverToDelete.id }

                // Save server list
                try await ServerAddressService.shared.saveServerAddresses(currentServers, for: gameName)

                await MainActor.run {
                    isDeleting = false
                    dismiss()
                    // Refresh server list
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
