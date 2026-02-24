import Foundation

/// player information model
/// Combining UserProfile and optional AuthCredential
/// Not stored directly, but loaded from UserProfileStore and AuthCredentialStore
struct Player: Identifiable, Equatable {
    /// User basic information
    var profile: UserProfile
    
    /// Authentication credentials (available only for online accounts)
    var credential: AuthCredential?
    
    // MARK: - Computed Properties
    
    /// Player unique identifier
    var id: String { profile.id }
    
    /// player name
    var name: String { profile.name }
    
    /// Player avatar path or URL
    var avatarName: String { profile.avatar }
    
    /// last play time
    var lastPlayed: Date {
        get { profile.lastPlayed }
        set { profile.lastPlayed = newValue }
    }
    
    /// Is it the currently selected player?
    var isCurrent: Bool {
        get { profile.isCurrent }
        set { profile.isCurrent = newValue }
    }
    
    /// Is it an online account?
    /// Prioritizes authentication credentials; when credentials have not yet been loaded from the Keychain,
    /// Approximately determine whether it is a genuine account by whether the avatar is a remote URL (http/https)
    var isOnlineAccount: Bool {
        if credential != nil {
            return true
        }
        return profile.avatar.hasPrefix("http://") || profile.avatar.hasPrefix("https://")
    }
    
    /// access token
    var authAccessToken: String { credential?.accessToken ?? "" }
    
    /// refresh token
    var authRefreshToken: String { credential?.refreshToken ?? "" }
    
    /// Xbox User ID
    var authXuid: String { credential?.xuid ?? "" }
    
    /// Token expiration time
    var expiresAt: Date? { credential?.expiresAt }
    
    /// Initialize player information
    /// - Parameters:
    ///   - profile: basic user information
    ///   - credential: authentication credentials (optional, offline account is nil)
    init(profile: UserProfile, credential: AuthCredential? = nil) {
        self.profile = profile
        self.credential = credential
    }
    
    /// Initialize player information (convenience method)
    /// - Parameters:
    ///   - name: player name
    ///   - uuid: player UUID, if nil, generate offline UUID
    ///   - avatar: avatar name or path
    ///   - credential: authentication credentials (optional)
    ///   - lastPlayed: last play time, default is current time
    ///   - isCurrent: whether the current player, default false
    /// - Throws: Throws an error if generation of player ID fails
    init(
        name: String,
        uuid: String? = nil,
        avatar: String? = nil,
        credential: AuthCredential? = nil,
        lastPlayed: Date = Date(),
        isCurrent: Bool = false
    ) throws {
        // Use UUID if provided, otherwise generate offline UUID
        let playerId: String
        if let providedUUID = uuid {
            playerId = providedUUID
        } else {
            playerId = try PlayerUtils.generateOfflineUUID(for: name)
        }
        
        // Confirm avatar
        let avatarName: String
        if let providedAvatar = avatar {
            avatarName = providedAvatar
        } else if credential != nil {
            // Online accounts require a profile picture
            avatarName = ""
        } else {
            // Use default avatar for offline accounts
            avatarName = PlayerUtils.avatarName(for: playerId) ?? "steve"
        }
        
        let profile = UserProfile(
            id: playerId,
            name: name,
            avatar: avatarName,
            lastPlayed: lastPlayed,
            isCurrent: isCurrent
        )
        
        self.profile = profile
        self.credential = credential
    }
}
