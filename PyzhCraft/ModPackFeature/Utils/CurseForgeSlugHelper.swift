import Foundation

/// CurseForge slug tool
/// Official Rules: ^[\w!@$()`.+,"\-']{3,64}$
/// Allowed characters: letters, numbers, underscore, and !@$()`.+,"\-'
/// Length: 3-64 characters
enum CurseForgeSlugHelper {
    private static let allowedCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "_!@$()`.+,\"-'")
        return set
    }()
    
    static func toSlug(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        
        let lowercased = text.lowercased()
        var result = ""
        var lastWasDash = false
        
        for ch in lowercased {
            // Check if a character is in the allowed character set
            if ch.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) {
                result.append(ch)
                lastWasDash = false
            } else {
                // Disallowed characters are replaced with `-`, but multiple `-`s in a row are avoided
                if !lastWasDash {
                    result.append("-")
                    lastWasDash = true
                }
            }
        }
        
        // Remove the leading and trailing `-`
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        
        // Verification length (3-64)
        if trimmed.count < 3 {
            return ""
        }
        if trimmed.count > 64 {
            return String(trimmed.prefix(64))
        }
        
        return trimmed
    }
    
    static func isValid(_ slug: String) -> Bool {
        // Length check: 3-64
        guard slug.count >= 3 && slug.count <= 64 else {
            return false
        }
        
        // Character checking: only allow characters in allowedCharacters
        for scalar in slug.unicodeScalars where !allowedCharacters.contains(scalar) {
            return false
        }
        
        return true
    }
}
