import SwiftUI

/// Sidebar navigation items
public enum SidebarItem: Hashable, Identifiable {
    case game(String)  // Game item, including game ID
    case resource(ResourceType)  // Resource item

    public var id: String {
        switch self {
        case .game(let gameId): "game_\(gameId)"
        case .resource(let type): "resource_\(type.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .game(let gameId): gameId // Name can be obtained from game data
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

    public var localizedName: String {
        switch self {
        case .mod: String(localized: "Mod")
        case .datapack: String(localized: "Data Pack")
        case .shader: String(localized: "Shader")
        case .resourcepack: String(localized: "Resource Pack")
        case .modpack: String(localized: "Modpack")
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
