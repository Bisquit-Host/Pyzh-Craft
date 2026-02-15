import Foundation

/// Authentication Credentials Model
/// Stored in Keychain
struct AuthCredential: Codable, Equatable {
    /// User ID (corresponds to UserProfile.id)
    let userId: String

    /// access token
    var accessToken: String

    /// refresh token
    var refreshToken: String

    /// Token expiration time
    var expiresAt: Date?

    /// Xbox User ID (XUID)
    var xuid: String

    /// Initialize authentication credentials
    /// - Parameters:
    ///   - userId: user ID
    ///   - accessToken: access token
    ///   - refreshToken: refresh token
    ///   - expiresAt: token expiration time, optional
    ///   - xuid: Xbox user ID, default is empty string
    init(
        userId: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date? = nil,
        xuid: String = ""
    ) {
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.xuid = xuid
    }
}
