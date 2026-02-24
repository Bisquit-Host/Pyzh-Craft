import SwiftUI

/// AI chat attachment preview area view
struct AIChatAttachmentPreviewView: View {
    let attachments: [MessageAttachmentType]
    let onRemove: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                        AttachmentPreview(attachment: attachment) {
                            onRemove(index)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            
            Divider()
        }
    }
}
