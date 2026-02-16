import SwiftUI

/// Data source enumeration
enum DataSource: String, CaseIterable, Codable {
    case modrinth = "Modrinth"
    case curseforge = "CurseForge"

    var displayName: String {
        switch self {
        case .modrinth:
            return "Modrinth"
        case .curseforge:
            return "CurseForge"
        }
    }

    var localizedNameKey: LocalizedStringKey {
        switch self {
        case .modrinth:
            "Modrinth"
        case .curseforge:
            "CurseForge"
        }
    }
}

class GameSettingsManager: ObservableObject {
    // MARK: - Singleton instance
    static let shared = GameSettingsManager()

    @AppStorage("globalXms")
    var globalXms: Int = 512 {
        didSet { objectWillChange.send() }
    }

    @AppStorage("globalXmx")
    var globalXmx: Int = 4096 {
        didSet { objectWillChange.send() }
    }

    @AppStorage("enableAICrashAnalysis")
    var enableAICrashAnalysis: Bool = false {
        didSet { objectWillChange.send() }
    }

    @AppStorage("defaultAPISource")
    var defaultAPISource: DataSource = .modrinth {
        didSet { objectWillChange.send() }
    }

    /// Whether to include snapshot versions in game version selection (global setting)
    @AppStorage("includeSnapshotsForGameVersions")
    var includeSnapshotsForGameVersions: Bool = false {
        didSet { objectWillChange.send() }
    }

    /// Compute the system's maximum available memory allocation (based on 70% of physical memory)
    var maximumMemoryAllocation: Int {
        let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        let physicalMemoryMB = physicalMemoryBytes / 1_048_576
        let calculatedMax = Int(Double(physicalMemoryMB) * 0.7)
        let roundedMax = (calculatedMax / 512) * 512
        return max(roundedMax, 512)
    }
}
