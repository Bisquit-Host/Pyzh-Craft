import Foundation

// MARK: - World Information Model
struct WorldInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let path: URL
    let lastPlayed: Date?
    let gameMode: String?
    let difficulty: String?
    /// Whether to limit mode (the field position is different in different versions, false when it cannot be parsed)
    let hardcore: Bool
    /// Whether to allow cheats/commands (allowCommands), false if it cannot be parsed
    let cheats: Bool
    let version: String?
    let seed: Int64?
    
    init(
        name: String,
        path: URL,
        lastPlayed: Date? = nil,
        gameMode: String? = nil,
        difficulty: String? = nil,
        hardcore: Bool = false,
        cheats: Bool = false,
        version: String? = nil,
        seed: Int64? = nil
    ) {
        self.id = path.lastPathComponent
        self.name = name
        self.path = path
        self.lastPlayed = lastPlayed
        self.gameMode = gameMode
        self.difficulty = difficulty
        self.hardcore = hardcore
        self.cheats = cheats
        self.version = version
        self.seed = seed
    }
}

// MARK: - Screenshot information model
struct ScreenshotInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let path: URL
    let createdDate: Date?
    let fileSize: Int64
    
    init(name: String, path: URL, createdDate: Date? = nil, fileSize: Int64 = 0) {
        self.id = path.lastPathComponent
        self.name = name
        self.path = path
        self.createdDate = createdDate
        self.fileSize = fileSize
    }
}

// MARK: - Log information model
struct LogInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let path: URL
    let createdDate: Date?
    let fileSize: Int64
    let isCrashLog: Bool
    
    init(name: String, path: URL, createdDate: Date? = nil, fileSize: Int64 = 0, isCrashLog: Bool = false) {
        self.id = path.lastPathComponent
        self.name = name
        self.path = path
        self.createdDate = createdDate
        self.fileSize = fileSize
        self.isCrashLog = isCrashLog
    }
}
// MARK: - world detail model
struct WorldDetailMetadata {
    let levelName: String
    let folderName: String
    let path: URL
    let lastPlayed: Date?
    let gameMode: String
    let difficulty: String
    let hardcore: Bool
    let cheats: Bool
    let versionName: String?
    let versionId: Int?
    let dataVersion: Int?
    let seed: Int64?
    let spawn: String?
    let time: Int64?
    let dayTime: Int64?
    let weather: String?
    let worldBorder: String?
    let gameRules: [String]?
}
