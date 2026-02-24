import SwiftUI
import UniformTypeIdentifiers

/// AI Chat Attachment Manager
class AIChatAttachmentManager: ObservableObject {
    @Published var pendingAttachments: [MessageAttachmentType] = []
    
    /// Handle file selection
    func handleFileSelection(_ urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Filter out image types and only allow non-image files
            let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
            if isImage {
                continue
            }
            // Only add non-image files
            let attachment: MessageAttachmentType = .file(url, url.lastPathComponent)
            pendingAttachments.append(attachment)
        }
    }
    
    /// Remove attachment
    func removeAttachment(at index: Int) {
        guard index < pendingAttachments.count else { return }
        pendingAttachments.remove(at: index)
    }
    
    /// Clear all attachments
    func clearAll() {
        pendingAttachments.removeAll()
    }
}
