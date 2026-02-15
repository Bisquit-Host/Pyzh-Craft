import Foundation

// MARK: - Mac rule evaluator

enum MacOS: String {
    case osx,
         osxArm64 = "osx-arm64",
         osxX86_64 = "osx-x86_64"

    static func fromJavaArch(_ javaArch: String) -> Self {
        let arch = javaArch.lowercased()
        
        if arch.contains("aarch64") {
            return .osxArm64
        } else if arch.contains("x86_64") || arch.contains("amd64") {
            return .osxX86_64
        } else {
            return .osx
        }
    }
}

enum RuleAction: String {
    case allow, disallow
}

struct MacRule {
    let action: RuleAction
    let os: MacOS?
}

enum MacRuleEvaluator {
    static func getCurrentJavaArch() -> String {
        #if os(macOS)
        Architecture.current.javaArch
        #else
        "x86_64"
        #endif
    }

    static func isLowVersion(_ version: String) -> Bool {
        let versionComponents = version.split(separator: ".").compactMap { Int($0) }
        guard versionComponents.count >= 2 else { return false }

        let major = versionComponents[0]
        let minor = versionComponents[1]

        // Versions below 1.19 use strict schema matching
        return major < 1 || (major == 1 && minor < 19)
    }

    // Returns a list of supported macOS identifiers, sorted by priority
    static func getSupportedMacOSIdentifiers(minecraftVersion: String? = nil) -> [String] {
        #if os(macOS)
        let isLowVersion = minecraftVersion.map { Self.isLowVersion($0) } ?? false

        return Architecture.current.macOSIdentifiers(isLowVersion: isLowVersion)
        #elseif os(Linux)
        return ["linux"]
        #elseif os(Windows)
        return ["windows"]
        #else
        return []
        #endif
    }

    static func isPlatformIdentifierSupported(_ identifier: String, minecraftVersion: String? = nil) -> Bool {
        getSupportedMacOSIdentifiers(minecraftVersion: minecraftVersion).contains(identifier)
    }

    static func convertFromMinecraftRules(_ rules: [Rule]) -> [MacRule] {
        return rules.compactMap { rule in
            guard let action = RuleAction(rawValue: rule.action) else { return nil }

            let macOS: MacOS?
            if let osName = rule.os?.name, let validMacOS = MacOS(rawValue: osName) {
                macOS = validMacOS
            } else if rule.os?.name != nil {
                return nil // Non-macOS rules
            } else {
                macOS = nil // No OS restrictions
            }

            return MacRule(action: action, os: macOS)
        }
    }

    static func isAllowed(_ rules: [Rule], minecraftVersion: String? = nil) -> Bool {
        guard !rules.isEmpty else { return true }

        let macRules = convertFromMinecraftRules(rules)

        // If the original rules are not empty but are empty after conversion, it means they are non-macOS rules
        if macRules.isEmpty {
            return false
        }

        // Get the list of identifiers supported by the current platform
        let supportedIdentifiers = getSupportedMacOSIdentifiers(minecraftVersion: minecraftVersion)

        // Get applicable rules based on supported identifiers (ordered by priority)
        var applicableRules: [MacRule] = []

        // Find high-priority rules first
        for identifier in supportedIdentifiers {
            let macOS = MacOS(rawValue: identifier)
            let matchingRules = macRules.filter { rule in
                rule.os == nil || rule.os == macOS
            }
            if !matchingRules.isEmpty {
                applicableRules = matchingRules
                break
            }
        }

        // If no matching rule is found, use the rule without OS restrictions
        if applicableRules.isEmpty {
            applicableRules = macRules.filter { $0.os == nil }
        }

        guard !applicableRules.isEmpty else { return false }

        // Check disallow rules first
        if applicableRules.contains(where: { $0.action == .disallow }) {
            return false
        }

        // Check allow rules
        return applicableRules.contains { $0.action == .allow }
    }
}
