import Foundation

/// Announcement response model
public struct AnnouncementResponse: Codable {
    public let success: Bool
    public let data: AnnouncementData?

    public init(success: Bool, data: AnnouncementData?) {
        self.success = success
        self.data = data
    }
}

/// Announcement data model
public struct AnnouncementData: Codable {
    public let title: String
    public let content: String
    public let author: String

    public init(title: String, content: String, author: String) {
        self.title = title
        self.content = content
        self.author = author
    }
}
