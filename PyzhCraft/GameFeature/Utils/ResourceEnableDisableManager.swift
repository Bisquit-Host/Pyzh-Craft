import Foundation

/// Resource enable/disable state manager
/// Responsible for managing the enabled and disabled status of local resources (via the .disable suffix)
enum ResourceEnableDisableManager {
    /// Check if the resource is disabled
    /// - Parameter fileName: file name
    /// - Returns: Whether it is disabled
    static func isDisabled(fileName: String?) -> Bool {
        guard let fileName = fileName else { return false }
        return fileName.hasSuffix(".disable")
    }

    /// Toggle the enabled/disabled state of a resource
    /// - Parameters:
    ///   - fileName: current file name
    ///   - resourceDir: resource directory
    /// - Returns: new file name, or nil if the operation fails
    /// - Throws: File operation error
    static func toggleDisableState(
        fileName: String,
        resourceDir: URL
    ) throws -> String {
        let fileManager = FileManager.default
        let currentURL = resourceDir.appendingPathComponent(fileName)
        let targetFileName: String

        let isCurrentlyDisabled = fileName.hasSuffix(".disable")
        if isCurrentlyDisabled {
            guard fileName.hasSuffix(".disable") else {
                throw GlobalError.resource(
                    chineseMessage: "启用资源失败：文件后缀不包含 .disable",
                    i18nKey: "Failed to enable resource: File suffix does not contain .disable",
                    level: .notification
                )
            }
            targetFileName = String(fileName.dropLast(".disable".count))
        } else {
            targetFileName = fileName + ".disable"
        }

        let targetURL = resourceDir.appendingPathComponent(targetFileName)
        try fileManager.moveItem(at: currentURL, to: targetURL)

        return targetFileName
    }
}
