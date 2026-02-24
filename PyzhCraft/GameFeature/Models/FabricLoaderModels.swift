import Foundation

struct FabricLoader: Codable {
    let loader: LoaderInfo
    
    struct LoaderInfo: Codable {
        let version: String
    }
}
