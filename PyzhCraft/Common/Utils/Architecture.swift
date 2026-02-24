import Foundation

/// Unified architecture auxiliary tools to centrally handle compile-time architecture branches
enum Architecture {
    case arm64, x86_64
    
    /// Current compilation architecture
    static let current: Architecture = {
#if arch(arm64)
        return .arm64
#else
        return .x86_64
#endif
    }()
    
    /// Java related schema strings
    var javaArch: String {
        switch self {
        case .arm64: "aarch64"
        case .x86_64: "x86_64"
        }
    }
    
    /// Sparkle / Common Schema Strings
    var sparkleArch: String {
        switch self {
        case .arm64: "arm64"
        case .x86_64: "x86_64"
        }
    }
    
    /// Platform ID for Java Runtime API
    var macPlatformId: String {
        switch self {
        case .arm64: "mac-os-arm64"
        case .x86_64: "mac-os"
        }
    }
    
    /// List of macOS identifiers for the current architecture (by priority)
    /// - Parameter isLowVersion: Whether it is a low version (Minecraft < 1.19)
    func macOSIdentifiers(isLowVersion: Bool) -> [String] {
        switch self {
        case .arm64:
            if isLowVersion {
                return ["osx-arm64", "macos-arm64"]
            } else {
                return ["osx-arm64", "macos-arm64", "osx", "macos"]
            }
        case .x86_64:
            return ["osx", "macos"]
        }
    }
}
