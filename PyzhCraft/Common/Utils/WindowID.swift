import SwiftUI

/// 窗口标识符枚举
enum WindowID: String {
    case contributors, acknowledgements, aiChat, javaDownload, skinPreview
}

extension WindowID: CaseIterable {}
