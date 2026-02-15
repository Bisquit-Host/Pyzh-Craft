import Foundation

/// User basic information model
/// Stored in plist file
struct UserProfile: Identifiable, Codable, Equatable {
    /// user unique identifier
    let id: String

    /// Username
    let name: String

    /// Avatar name or path
    let avatar: String

    /// last play time
    var lastPlayed: Date

    /// Is it the currently selected user?
    var isCurrent: Bool

    /// Initialize basic user information
    /// - Parameters:
    ///   - id: user’s unique identifier
    ///   - name: user name
    ///   - avatar: avatar name or path
    ///   - lastPlayed: last play time, default is current time
    ///   - isCurrent: whether it is the currently selected user, default false
    init(
        id: String,
        name: String,
        avatar: String,
        lastPlayed: Date = Date(),
        isCurrent: Bool = false
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.lastPlayed = lastPlayed
        self.isCurrent = isCurrent
    }
}
