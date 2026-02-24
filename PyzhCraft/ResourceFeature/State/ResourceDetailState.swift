import SwiftUI

/// Resource/game details and navigation related status (observable)
public final class ResourceDetailState: ObservableObject {
    
    @Published public var selectedItem: SidebarItem
    @Published public var gameType: Bool  // false = local, true = server
    @Published public var gameId: String?
    @Published public var gameResourcesType: String
    @Published public var selectedProjectId: String? {
        didSet {
            if selectedProjectId != oldValue {
                loadedProjectDetail = nil
            }
        }
    }
    @Published public var loadedProjectDetail: ModrinthProjectDetail?
    
    public init(
        selectedItem: SidebarItem = .resource(.mod),
        gameType: Bool = true,
        gameId: String? = nil,
        gameResourcesType: String = "mod",
        selectedProjectId: String? = nil,
        loadedProjectDetail: ModrinthProjectDetail? = nil
    ) {
        self.selectedItem = selectedItem
        self.gameType = gameType
        self.gameId = gameId
        self.gameResourcesType = gameResourcesType
        self.selectedProjectId = selectedProjectId
        self.loadedProjectDetail = loadedProjectDetail
    }
    
    // MARK: - Convenience method
    
    public func selectGame(id: String?) {
        gameId = id
    }
    
    public func selectResource(type: String) {
        gameResourcesType = type
    }
    
    /// Clear the project/game selected state (used to switch back to the list, etc.)
    public func clearSelection() {
        selectedProjectId = nil
        loadedProjectDetail = nil
    }
    
    // MARK: - Bindings (for use by subviews, GameActionManager, etc.)
    
    public var selectedItemBinding: Binding<SidebarItem> {
        Binding(get: { [weak self] in self?.selectedItem ?? .resource(.mod) }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.selectedItem = value }
        })
    }
    
    /// Used for APIs that require Optional such as List(selection:)
    public var selectedItemOptionalBinding: Binding<SidebarItem?> {
        Binding(get: { [weak self] in self?.selectedItem }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { if let v = value { self.selectedItem = v } }
        })
    }
    public var gameTypeBinding: Binding<Bool> {
        Binding(get: { [weak self] in self?.gameType ?? true }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.gameType = value }
        })
    }
    public var gameIdBinding: Binding<String?> {
        Binding(get: { [weak self] in self?.gameId }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.gameId = value }
        })
    }
    public var gameResourcesTypeBinding: Binding<String> {
        Binding(get: { [weak self] in self?.gameResourcesType ?? "mod" }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.gameResourcesType = value }
        })
    }
    public var selectedProjectIdBinding: Binding<String?> {
        Binding(get: { [weak self] in self?.selectedProjectId }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.selectedProjectId = value }
        })
    }
    public var loadedProjectDetailBinding: Binding<ModrinthProjectDetail?> {
        Binding(get: { [weak self] in self?.loadedProjectDetail }, set: { [weak self] value in
            guard let self else { return }
            DispatchQueue.main.async { self.loadedProjectDetail = value }
        })
    }
}
