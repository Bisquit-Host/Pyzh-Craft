import SwiftUI

/// message role
enum MessageRole: String, Codable {
    case user, assistant, system
}

/// Attachment type
enum MessageAttachmentType: Identifiable, Equatable {
    case image(URL),
         file(URL, String) // URL and file name
    
    var id: String {
        switch self {
        case .image(let url):
            "image_\(url.path)"
            
        case .file(let url, _):
            "file_\(url.path)"
        }
    }
}

/// Chat messages
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    let attachments: [MessageAttachmentType]
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String = "",
        timestamp: Date = Date(),
        attachments: [MessageAttachmentType] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachments = attachments
    }
}

/// chat status
@MainActor
class ChatState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isSending = false
    
    func addMessage(_ message: ChatMessage) {
        messages.append(message)
    }
    
    func updateLastMessage(_ content: String) {
        if let lastIndex = messages.indices.last {
            messages[lastIndex].content = content
        }
    }
    
    func clear() {
        messages.removeAll()
        isSending = false
    }
}
