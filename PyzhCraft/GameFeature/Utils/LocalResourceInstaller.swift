import UniformTypeIdentifiers
import SwiftUI

/// Tool class: responsible for importing local jar/zip files into the specified resource directory
enum LocalResourceInstaller {
    enum ResourceType {
        case mod, datapack, resourcepack

        var directoryName: String {
            switch self {
            case .mod: AppConstants.DirectoryNames.mods
            case .datapack: AppConstants.DirectoryNames.datapacks
            case .resourcepack: AppConstants.DirectoryNames.resourcepacks
            }
        }

        /// Supported file extensions - jar and zip are uniformly supported
        var allowedExtensions: [String] {
            ["jar", "zip"]
        }
    }

    /// Install local resource files to the specified directory
    /// - Parameters:
    ///   - fileURL: the local file selected by the user
    ///   - resourceType: resource type (mods/datapacks/resourcepacks)
    ///   - gameRoot: game root directory (such as .minecraft)
    /// - Throws: GlobalError
    static func install(fileURL: URL, resourceType: ResourceType, gameRoot: URL) throws {
        // Check extension
        guard let ext = fileURL.pathExtension.lowercased() as String?,
              resourceType.allowedExtensions.contains(ext) else {
            throw GlobalError.resource(
                chineseMessage: "不支持的文件类型。请导入 .jar 或 .zip 文件。",
                i18nKey: "Invalid file type",
                level: .notification
            )
        }

        // target directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gameRoot.path, isDirectory: &isDir), isDir.boolValue else {
            throw GlobalError.fileSystem(
                chineseMessage: "目标文件夹不存在。",
                i18nKey: "Destination Unavailable",
                level: .notification
            )
        }

        // Handle security scope
        let needsSecurity = fileURL.startAccessingSecurityScopedResource()
        defer { if needsSecurity { fileURL.stopAccessingSecurityScopedResource() } }
        if !needsSecurity {
            throw GlobalError.fileSystem(
                chineseMessage: "无法访问所选文件。",
                i18nKey: "Security Scope Failed",
                level: .notification
            )
        }

        // target file path
        let destURL = gameRoot.appendingPathComponent(fileURL.lastPathComponent)

        // If it already exists, remove it first
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }

        do {
            try FileManager.default.copyItem(at: fileURL, to: destURL)
        } catch {
            throw GlobalError.fileSystem(
                chineseMessage: "文件复制失败：\(error.localizedDescription)",
                i18nKey: "Copy Failed",
                level: .notification
            )
        }
    }
}

extension LocalResourceInstaller {
    struct ImportButton: View {
        let query: String
        let gameName: String
        let onResourceChanged: () -> Void

        @State private var showImporter = false
        @StateObject private var errorHandler = GlobalErrorHandler.shared

        var body: some View {
            VStack(spacing: 8) {
                Button {
                    showImporter = true
                } label: {
                    // Image(systemName: "square.and.arrow.down")
                    Text("Import")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .controlSize(.large)
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: {
                        var types: [UTType] = []
                        // Unified support for jar and zip files
                        if let jarType = UTType(filenameExtension: "jar") {
                            types.append(jarType)
                        }
                        types.append(.zip)
                        return types
                    }(),
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let fileURL = urls.first else { return }

                        // Check if query is a valid resource type
                        let validResourceTypes = ["mod", "datapack", "shader", "resourcepack"]
                        let queryLowercased = query.lowercased()

                        // If query is a modpack or an invalid resource type, show an error
                        if queryLowercased == "modpack" || !validResourceTypes.contains(queryLowercased) {
                            errorHandler.handle(GlobalError.configuration(
                                chineseMessage: "不支持导入此类型的资源",
                                i18nKey: "Resource Directory Not Found",
                                level: .notification
                            ))
                            return
                        }

                        let gameRootOpt = AppPaths.resourceDirectory(for: query, gameName: gameName)
                        guard let gameRoot = gameRootOpt else {
                            errorHandler.handle(GlobalError.fileSystem(
                                chineseMessage: "找不到游戏目录",
                                i18nKey: "Game Directory Not Found",
                                level: .notification
                            ))
                            return
                        }

                        // Simplified extension verification - unified support for jar and zip
                        let allowedExtensions = ["jar", "zip"]

                        do {
                            guard let ext = fileURL.pathExtension.lowercased() as String?, allowedExtensions.contains(ext) else {
                                throw GlobalError.resource(
                                    chineseMessage: "不支持的文件类型。请导入 .jar 或 .zip 文件。",
                                    i18nKey: "Invalid file type",
                                    level: .notification
                                )
                            }

                            try LocalResourceInstaller.install(
                                fileURL: fileURL,
                                resourceType: .mod, // Only used for allowedExtensions verification, manually verified
                                gameRoot: gameRoot
                            )
                            onResourceChanged()
                        } catch {
                            errorHandler.handle(error)
                        }
                    case .failure(let error):
                        errorHandler.handle(GlobalError.fileSystem(
                            chineseMessage: "文件选择失败：\(error.localizedDescription)",
                            i18nKey: "File Selection Failed",
                            level: .notification
                        ))
                    }
                }
            }
        }
    }
}
