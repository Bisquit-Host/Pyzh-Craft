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
        .onChange(of: servers) {
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
                .background(.gray.opacity(0.15))
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
