import SwiftUI

/// window identifier enum
enum WindowID: String {
    case contributors, acknowledgements, aiChat, javaDownload, skinPreview, serverSettings
}

extension WindowID: CaseIterable {}
