import Foundation

/// Supported launcher types
enum ImportLauncherType: String, CaseIterable {
    case multiMC = "MultiMC",
         prismLauncher = "PrismLauncher",
         gdLauncher = "GDLauncher",
         hmcl = "HMCL",
         sjmcLauncher = "SJMCLauncher",
         xmcl = "XMCL"
}
