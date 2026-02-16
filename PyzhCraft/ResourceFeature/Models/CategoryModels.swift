import Foundation

// MARK: - filter item model
struct FilterItem: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
}
enum ProjectType {
    static let modpack = "modpack"
    static let mod = "mod"
    static let datapack = "datapack"
    static let resourcepack = "resourcepack"
    static let shader = "shader"
}

enum CategoryHeader {
    static let categories = "categories"
    static let features = "features"
    static let resolutions = "resolutions"
    static let performanceImpact = "performance impact"
    static let environment = "environment"
}

enum FilterTitle {
    static let category = "Category"
    static let environment = "Environment"
    static let behavior = "Behavior"
    static let resolutions = "Resolutions"
    static let performance = "Performance"
    static let version = "Versions"
}
