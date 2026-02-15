import Foundation

/// Java Manager
class JavaManager {
    static let shared = JavaManager()

    private let fileManager = FileManager.default

    func getJavaExecutablePath(version: String) -> String {
        AppPaths.javaExecutablePath(version: version)
    }

    func findJavaExecutable(version: String) -> String {
        let javaPath = getJavaExecutablePath(version: version)

        // Check if the file exists
        guard fileManager.fileExists(atPath: javaPath) else {
            return ""
        }

        // Verify whether Java can start normally
        guard canJavaRun(at: javaPath) else {
            return ""
        }

        return javaPath
    }

    func canJavaRun(at javaPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaPath)
        process.arguments = ["-version"]

        // Set up an output pipe to capture output
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let exitCode = process.terminationStatus
            if exitCode == 0 {
                Logger.shared.debug("Java启动验证成功: \(javaPath)")
                return true
            } else {
                Logger.shared.warning("Java启动验证失败，退出码: \(exitCode)")
                return false
            }
        } catch {
            Logger.shared.error("Java启动验证异常: \(error.localizedDescription)")
            return false
        }
    }

    // Check whether Java exists. If it does not exist, use the progress window to download it
    func ensureJavaExists(version: String) async -> String {
        // Prefer existing and working Java
        let existingPath = findJavaExecutable(version: version)
        if !existingPath.isEmpty {
            Logger.shared.info("Java版本 \(version) 已存在")
            return existingPath
        }

        // If not present, use the progress window to download the Java runtime
        Logger.shared.info("Java版本 \(version) 不存在，开始下载...")
        await JavaDownloadManager.shared.downloadJavaRuntime(version: version)
        Logger.shared.info("Java版本 \(version) 下载完成")

        // After the download is complete try to get the Java path again
        let newPath = findJavaExecutable(version: version)
        if newPath.isEmpty {
            Logger.shared.error("Java版本 \(version) 下载完成后仍无法找到可用的Java可执行文件")
        }
        return newPath
    }

    func findDefaultJavaPath(for gameVersion: String) async -> String {
        do {
            // Query the cached version file to obtain the manifest
            let manifest = try await ModrinthService.fetchVersionInfo(from: gameVersion)
            let component = manifest.javaVersion.component

            // Use component to splice Java paths (without verification)
            return getJavaExecutablePath(version: component)
        } catch {
            Logger.shared.error("获取游戏版本信息失败: \(error.localizedDescription)")
            return ""
        }
    }
}
