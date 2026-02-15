import SwiftUI
import SkinRenderKit

/// Skin preview data
struct SkinPreviewData {
    let skinImage: NSImage?
    let skinPath: String?
    let capeImage: NSImage?
    let playerModel: PlayerModel
}

/// Window data storage, used to transfer data between windows
@MainActor
class WindowDataStore: ObservableObject {
    static let shared = WindowDataStore()

    private init() {}

    // AI Chat window data
    @Published var aiChatState: ChatState?

    // Skin Preview window data
    @Published var skinPreviewData: SkinPreviewData?

    /// Clear the data of the specified window
    func cleanup(for windowID: WindowID) {
        switch windowID {
        case .aiChat:
            // Clean AI Chat data
            if let chatState = aiChatState {
                chatState.clear()
            }
            aiChatState = nil
        case .skinPreview:
            // Clean Skin Preview data
            skinPreviewData = nil
        default:
            // Other windows do not need to clean up WindowDataStore
            break
        }
    }
}
