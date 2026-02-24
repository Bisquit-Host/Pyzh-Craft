import Foundation

/// room code generator
/// Generate room codes in the format U/XXXX-XXXX-XXXX-XXXX
/// Use hexadecimal encoding (0-9, A-Z, excluding I and O)
/// Room number generation mechanism based on Terracotta
enum RoomCodeGenerator {
    // MARK: - Constants
    
    /// Character set: 34 characters (0-9, A-Z, excluding I and O)
    /// Character index corresponding: 0-33
    private static let chars: [Character] = Array("0123456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    
    /// Character to index mapping (0-33)
    private static let charToIndex: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (index, char) in chars.enumerated() {
            map[char] = index
        }
        return map
    }()
    
    /// Character search function (supports character mapping: I -> 1, O -> 0)
    /// - Parameter char: input character
    /// - Returns: character index (0-33), returns nil if the character is invalid
    private static func lookupChar(_ char: Character) -> Int? {
        // Character mapping: I -> 1, O -> 0
        let normalizedChar: Character
        switch char {
        case "I":
            normalizedChar = "1"
        case "O":
            normalizedChar = "0"
        default:
            normalizedChar = char
        }
        
        return charToIndex[normalizedChar]
    }
    
    // MARK: - Public Methods
    
    /// Generate a new room code
    /// - Returns: Room code that matches the format (U/XXXX-XXXX-XXXX-XXXX)
    static func generate() -> String {
        // Generate 16 random character indices (each in the range [0, 33])
        var charIndices = [Int]()
        for _ in 0..<16 {
            charIndices.append(Int.random(in: 0..<34))
        }
        
        // Step 3: Calculate the current value modulo 7
        var mod7Value = 0
        for charIndex in charIndices {
            // Using the properties of modular arithmetic: (a * 34 + b) % 7 = ((a % 7) * (34 % 7) + b) % 7
            // 34 % 7 = 6
            mod7Value = (mod7Value * 6 + charIndex) % 7
        }
        
        // Step 4: Adjust to a multiple of 7 (adjust the last character)
        if mod7Value != 0 {
            // Modulo 7 value calculation: mod7Value = (baseMod * 6 + lastCharIndex) % 7
            // where baseMod is the contribution of the first 15 characters
            // Target: 0 = (baseMod * 6 + newLastChar) % 7
            // So: newLastChar ≡ -baseMod * 6 (mod 7)
            // Also: baseMod * 6 ≡ mod7Value - lastCharIndex (mod 7)
            // Therefore: newLastChar ≡ -(mod7Value - lastCharIndex) ≡ lastCharIndex - mod7Value (mod 7)
            
            let lastCharIndex = charIndices[15]
            let targetLastCharMod = (lastCharIndex - mod7Value + 7) % 7
            
            // Find a value in the range [0, 33] modulo 7 equal to targetLastCharMod
            // and as close as possible to the original value
            var bestNewLastChar = lastCharIndex
            var bestDistance = 34
            
            for candidate in 0..<34 where candidate % 7 == targetLastCharMod {
                let distance = abs(candidate - lastCharIndex)
                if distance < bestDistance {
                    bestDistance = distance
                    bestNewLastChar = candidate
                }
            }
            
            charIndices[15] = bestNewLastChar
        }
        
        // Step 5: Encode to string
        var code = "U/"
        var networkName = "scaffolding-mc-"
        var networkSecret = ""
        
        for i in 0..<16 {
            let char = chars[charIndices[i]]
            
            // Room number encoding (add separator)
            if i == 4 || i == 8 || i == 12 {
                code.append("-")
            }
            code.append(char)
            
            // Network name encoding (first 8 characters)
            if i < 8 {
                if i == 4 {
                    networkName.append("-")
                }
                networkName.append(char)
            }
            // Network key encoding (last 8 characters)
            else {
                if i == 12 {
                    networkSecret.append("-")
                }
                networkSecret.append(char)
            }
        }
        
        Logger.shared.debug("Generate room code: \(code)")
        return code
    }
    
    /// Verify that the room code is valid
    /// - Parameter roomCode: room code string (format: U/XXXX-XXXX-XXXX-XXXX)
    /// - Returns: Is it valid?
    static func validate(_ roomCode: String) -> Bool {
        parse(roomCode) != nil
    }
    
    /// Parse room code string
    /// Support sliding window search and character mapping (I -> 1, O -> 0)
    /// - Parameter code: room code string
    /// - Returns: Parsed room code string (normalized format), if invalid, returns nil
    static func parse(_ code: String) -> String? {
        // Step 1: Normalize input (convert to uppercase)
        let normalizedCode = code.uppercased()
        let codeChars = Array(normalizedCode)
        
        // Step 2: Length check
        // Room number format: U/XXXX-XXXX-XXXX-XXXX
        // Prefix: U/ = 2 characters
        // Body: XXXX-XXXX-XXXX-XXXX = 16 characters + 3 separators = 19 characters
        // Total: 21 characters
        let targetLength = 21
        guard codeChars.count >= targetLength else {
            return nil
        }
        
        // Step 3: Sliding window search
        for startIndex in 0...(codeChars.count - targetLength) {
            let window = Array(codeChars[startIndex..<(startIndex + targetLength)])
            
            // Step 4: Prefix verification
            guard window[0] == "U", window[1] == "/" else {
                continue
            }
            
            // Step 5: Decoding and verification
            // Skip the prefix "U/" (2 characters) and process the body
            // Main part structure: XXXX-XXXX-XXXX-XXXX
            // Window position: 0-1(U/), 2-5(Character), 6(Separator), 7-10(Character), 11(Separator), 12-15(Character), 16(Separator), 17-20(Character)
            // Separator position (window index): 6, 11, 16
            // Character position (window index): 2-5, 7-10, 12-15, 17-20
            let separatorPositions = [6, 11, 16]
            let charPositions = [2, 3, 4, 5, 7, 8, 9, 10, 12, 13, 14, 15, 17, 18, 19, 20]
            
            // Check delimiter
            var separatorsValid = true
            for sepPos in separatorPositions {
                if sepPos >= window.count || window[sepPos] != "-" {
                    separatorsValid = false
                    break
                }
            }
            
            guard separatorsValid else {
                continue  // Wrong separator position, try next window
            }
            
            // Extract characters and decode
            var charIndices = [Int]()
            var charsValid = true
            for charPos in charPositions {
                guard charPos < window.count else {
                    charsValid = false
                    break
                }
                
                guard let charIndex = lookupChar(window[charPos]) else {
                    charsValid = false
                    break
                }
                
                charIndices.append(charIndex)
            }
            
            guard charsValid && charIndices.count == 16 else {
                continue  // Invalid or insufficient number of characters, try next window
            }
            
            // Step 6: Mathematical verification (check if it is a multiple of 7)
            // Using the properties of modular arithmetic: (a * 34 + b) % 7 = ((a % 7) * (34 % 7) + b) % 7
            // 34 % 7 = 6
            var mod7Value = 0
            for charIndex in charIndices {
                mod7Value = (mod7Value * 6 + charIndex) % 7
            }
            
            if mod7Value == 0 {
                // Step 7: Recode (normalize)
                var normalizedRoomCode = "U/"
                for i in 0..<16 {
                    if i == 4 || i == 8 || i == 12 {
                        normalizedRoomCode.append("-")
                    }
                    normalizedRoomCode.append(chars[charIndices[i]])
                }
                return normalizedRoomCode
            }
        }
        
        return nil
    }
    
    /// Extract network name and key from room code
    /// - Parameter roomCode: room code (format: U/XXXX-XXXX-XXXX-XXXX)
    /// - Returns: (network name, network key), or nil if the format is invalid
    static func extractNetworkInfo(from roomCode: String) -> (networkName: String, networkSecret: String)? {
        guard let normalizedCode = parse(roomCode) else {
            return nil
        }
        
        let parts = normalizedCode.replacingOccurrences(of: "U/", with: "").split(separator: "-")
        guard parts.count == 4 else {
            return nil
        }
        
        let n1 = String(parts[0])  // XXXX
        let n2 = String(parts[1])  // XXXX
        let s1 = String(parts[2])  // XXXX
        let s2 = String(parts[3])  // XXXX
        
        let networkName = "scaffolding-mc-\(n1)-\(n2)"
        let networkSecret = "\(s1)-\(s2)"
        
        return (networkName, networkSecret)
    }
}
