import SwiftUI

/// Sidebar navigation items
public enum SidebarItem: Hashable, Identifiable {
    case game(String), resource(ResourceType) // Game item includes game ID
    
    public var id: String {
        switch self {
        case .game(let gameId): "game_\(gameId)"
        case .resource(let type): "resource_\(type.rawValue)"
        }
    }
    
    public var title: LocalizedStringKey {
        switch self {
        case .game(let gameId): LocalizedStringKey(gameId) // Name can be obtained from game data
        case .resource(let type): type.localizedName
        }
    }
}

/// Resource type
public enum ResourceType: String, CaseIterable {
    case mod, datapack, shader, resourcepack, modpack
    
    public var localizedNameKey: LocalizedStringKey {
        switch self {
        case .mod: "Mod"
        case .datapack: "Data Pack"
        case .shader: "Shader"
        case .resourcepack: "Resource Pack"
        case .modpack: "Modpack"
        }
    }
    
    public var localizedName: LocalizedStringKey {
        switch self {
        case .mod: "Mod"
        case .datapack: "Data Pack"
        case .shader: "Shader"
        case .resourcepack: "Resource Pack"
        case .modpack: "Modpack"
        }
    }
    
    /// SF Symbol icon name for the resource type
    public var systemImage: String {
        switch self {
        case .mod: "puzzlepiece.extension"
        case .datapack: "doc.on.doc"
        case .shader: "sparkles"
        case .resourcepack: "photo.stack"
        case .modpack: "cube.box"
        }
    }
}
