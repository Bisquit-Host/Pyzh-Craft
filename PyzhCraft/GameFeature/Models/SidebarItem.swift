import Foundation

/// Sidebar navigation items
public enum SidebarItem: Hashable, Identifiable {
    case game(String)  // Game item, including game ID
    case resource(ResourceType)  // Resource item

    public var id: String {
        switch self {
        case .game(let gameId):
            return "game_\(gameId)"
        case .resource(let type):
            return "resource_\(type.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .game(let gameId):
            return gameId  // Name can be obtained from game data
        case .resource(let type):
            return type.localizedName
        }
    }
}

/// Resource type
public enum ResourceType: String, CaseIterable {
    case mod, datapack, shader, resourcepack, modpack

    public var localizedName: String {
        "resource.content.type.\(rawValue)".localized()
    }

    /// SF Symbol icon name for the resource type
    public var systemImage: String {
        switch self {
        case .mod:
            return "puzzlepiece.extension"
        case .datapack:
            return "doc.on.doc"
        case .shader:
            return "sparkles"
        case .resourcepack:
            return "photo.stack"
        case .modpack:
            return "cube.box"
        }
    }
}
