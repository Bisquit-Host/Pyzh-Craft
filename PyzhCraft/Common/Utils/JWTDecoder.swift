import Foundation

/// JWT decoder tool class
/// Parse the JWT and extract the expiration time
enum JWTDecoder {
    /// Parse JWT token and extract expiration time
    /// - Parameter jwt: JWT token string
    /// - Returns: expiration time, if parsing fails, nil is returned
    static func extractExpirationTime(from jwt: String) -> Date? {
        // JWT format: header.payload.signature
        let components = jwt.components(separatedBy: ".")
        
        // Make sure there are 3 parts
        guard components.count == 3 else {
            Logger.shared.warning("Invalid JWT format: not a standard 3-part format")
            return nil
        }
        
        // Parse the payload part (Part 2)
        let payload = components[1]
        
        // Add padding to ensure base64 decoding is correct
        let paddedPayload = addPadding(to: payload)
        
        guard let payloadData = Data(base64Encoded: paddedPayload) else {
            Logger.shared.warning("JWT payload base64 decoding failed")
            return nil
        }
        
        do {
            let payloadJSON = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
            
            // Extract exp field (expiration timestamp)
            if let exp = payloadJSON?["exp"] as? TimeInterval {
                let expirationDate = Date(timeIntervalSince1970: exp)
                Logger.shared.debug("Parse the expiration time from the JWT: \(expirationDate)")
                return expirationDate
            } else {
                Logger.shared.warning("exp field not found in JWT payload")
                return nil
            }
        } catch {
            Logger.shared.warning("JWT payload JSON parsing failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Parse the JWT token and extract all available information
    /// - Parameter jwt: JWT token string
    /// - Returns: Dictionary containing JWT information, nil is returned if parsing fails
    static func extractAllInfo(from jwt: String) -> [String: Any]? {
        let components = jwt.components(separatedBy: ".")
        
        guard components.count == 3 else {
            Logger.shared.warning("Invalid JWT format: not a standard 3-part format")
            return nil
        }
        
        let payload = components[1]
        let paddedPayload = addPadding(to: payload)
        
        guard let payloadData = Data(base64Encoded: paddedPayload) else {
            Logger.shared.warning("JWT payload base64 decoding failed")
            return nil
        }
        
        do {
            let payloadJSON = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
            return payloadJSON
        } catch {
            Logger.shared.warning("JWT payload JSON parsing failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Add necessary padding to base64 string
    /// - Parameter base64String: original base64 string
    /// - Returns: base64 string with added padding
    private static func addPadding(to base64String: String) -> String {
        var padded = base64String
        
        // Calculate the amount of padding that needs to be added
        let remainder = padded.count % 4
        if remainder > 0 {
            let paddingNeeded = 4 - remainder
            // Use string interpolation instead of string concatenation
            padded = "\(padded)\(String(repeating: "=", count: paddingNeeded))"
        }
        
        return padded
    }
    
    /// Check if JWT token is about to expire
    /// - Parameters:
    ///   - jwt: JWT token string
    ///   - bufferTime: buffering time (seconds), default 5 minutes
    /// - Returns: Whether it is about to expire
    static func isTokenExpiringSoon(_ jwt: String, bufferTime: TimeInterval = 300) -> Bool {
        guard let expirationTime = extractExpirationTime(from: jwt) else {
            // If the expiration time cannot be parsed, it is considered to have expired
            return true
        }
        
        let currentTime = Date()
        let expirationTimeWithBuffer = expirationTime.addingTimeInterval(-bufferTime)
        
        return currentTime >= expirationTimeWithBuffer
    }
}

// MARK: - Minecraft Token Constants
extension JWTDecoder {
    /// Default expiration time for Minecraft tokens (24 hours)
    /// Used when the expiration time cannot be parsed from the JWT
    static let defaultMinecraftTokenExpiration: TimeInterval = 24 * 60 * 60 // 24 hours
    
    /// Get the expiration time of Minecraft token
    /// Prefer parsing from JWT, using default value if failed
    /// - Parameter minecraftToken: Minecraft access token
    /// - Returns: Expiration time
    static func getMinecraftTokenExpiration(from minecraftToken: String) -> Date {
        if let expirationTime = extractExpirationTime(from: minecraftToken) {
            Logger.shared.debug("Minecraft token expiration time parsed using JWT: \(expirationTime)")
            return expirationTime
        } else {
            let defaultExpiration = Date().addingTimeInterval(defaultMinecraftTokenExpiration)
            Logger.shared.debug("Use the default Minecraft token expiration time: \(defaultExpiration)")
            return defaultExpiration
        }
    }
}
