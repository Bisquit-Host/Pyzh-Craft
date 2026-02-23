import Foundation

/// Java Manager
class JavaManager {
    static let shared = JavaManager()

    private let fileManager = FileManager.default
    private let javaHomeExecutable = "/usr/libexec/java_home"

    struct DetectedJavaRuntime: Identifiable, Hashable {
        let path: String
        let majorVersion: Int
        let versionString: String

        var id: String { path }
    }

    private struct JavaInstallation {
        let path: String
        let majorVersion: Int
        let versionString: String
    }

    func getJavaExecutablePath(version: String) -> String {
        AppPaths.javaExecutablePath(version: version)
    }

    func findJavaExecutable(version: String, requiredMajorVersion: Int? = nil) -> String {
        let javaPath = getJavaExecutablePath(version: version)

        if canJavaRun(at: javaPath) {
            return javaPath
        }

        return findInstalledJavaExecutable(requiredMajorVersion: requiredMajorVersion) ?? ""
    }

    func canJavaRun(at javaPath: String) -> Bool {
        guard let resolvedPath = resolveJavaExecutablePath(from: javaPath) else {
            Logger.shared.warning("Java startup verification failed because the path does not exist: \(javaPath)")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
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
                Logger.shared.debug("Java startup verification successful: \(resolvedPath)")
                return true
            } else {
                Logger.shared.warning("Java startup verification failed, exit code: \(exitCode)")
                return false
            }
        } catch {
            Logger.shared.error("Java startup verification exception: \(error.localizedDescription)")
            return false
        }
    }

    // Check whether Java exists. If it does not exist, use the progress window to download it
    func ensureJavaExists(version: String, requiredMajorVersion: Int? = nil) async -> String {
        // Prefer existing and working Java
        let existingPath = findJavaExecutable(version: version, requiredMajorVersion: requiredMajorVersion)
        if !existingPath.isEmpty {
            Logger.shared.info("Java version \(version) already exists or an installed Java has been detected")
            return existingPath
        }

        // If not present, use the progress window to download the Java runtime
        Logger.shared.info("Java version \(version) does not exist, start downloading")
        await JavaDownloadManager.shared.downloadJavaRuntime(version: version)
        Logger.shared.info("Java version \(version) download completed")

        // After the download is complete try to get the Java path again
        let newPath = findJavaExecutable(version: version, requiredMajorVersion: requiredMajorVersion)
        if newPath.isEmpty {
            Logger.shared.error("Java version \(version) The available Java executable file cannot be found after the download is completed")
        }
        return newPath
    }

    func findDefaultJavaPath(for gameVersion: String) async -> String {
        do {
            // Query the cached version file to obtain the manifest
            let manifest = try await ModrinthService.fetchVersionInfo(from: gameVersion)
            let component = manifest.javaVersion.component
            let majorVersion = manifest.javaVersion.majorVersion

            return findJavaExecutable(version: component, requiredMajorVersion: majorVersion)
        } catch {
            Logger.shared.error("Failed to obtain game version information: \(error.localizedDescription)")
            return ""
        }
    }

    func listInstalledJavaRuntimes(requiredMajorVersion: Int? = nil, includeIncompatible: Bool = true) -> [DetectedJavaRuntime] {
        let installations = detectInstalledJavaInstallations()
        let filteredInstallations = installations.filter { installation in
            guard includeIncompatible == false else { return true }
            guard let requiredMajorVersion else { return true }
            return installation.majorVersion >= requiredMajorVersion
        }

        let sortedInstallations = filteredInstallations.sorted { lhs, rhs in
            if isPreferred(lhs, over: rhs, requiredMajorVersion: requiredMajorVersion) {
                return true
            }
            if isPreferred(rhs, over: lhs, requiredMajorVersion: requiredMajorVersion) {
                return false
            }
            return lhs.path < rhs.path
        }

        return sortedInstallations.map { installation in
            DetectedJavaRuntime(
                path: installation.path,
                majorVersion: installation.majorVersion,
                versionString: installation.versionString
            )
        }
    }

    private func findInstalledJavaExecutable(requiredMajorVersion: Int?) -> String? {
        let installations = detectInstalledJavaInstallations()
        guard !installations.isEmpty else {
            return nil
        }

        let compatibleInstallations = installations.filter { installation in
            guard let requiredMajorVersion else { return true }
            return installation.majorVersion >= requiredMajorVersion
        }

        guard !compatibleInstallations.isEmpty else {
            return nil
        }

        let selected = compatibleInstallations.max { lhs, rhs in
            isPreferred(rhs, over: lhs, requiredMajorVersion: requiredMajorVersion)
        }

        if let selected {
            Logger.shared.info("Detected installed Java: \(selected.path) (version: \(selected.versionString), major: \(selected.majorVersion))")
        }
        return selected?.path
    }

    private func isPreferred(_ candidate: JavaInstallation, over other: JavaInstallation, requiredMajorVersion: Int?) -> Bool {
        let candidateScore = score(for: candidate, requiredMajorVersion: requiredMajorVersion)
        let otherScore = score(for: other, requiredMajorVersion: requiredMajorVersion)
        if candidateScore != otherScore {
            return candidateScore > otherScore
        }

        let candidateVersionParts = extractNumericParts(candidate.versionString)
        let otherVersionParts = extractNumericParts(other.versionString)
        if candidateVersionParts != otherVersionParts {
            return candidateVersionParts.lexicographicallyPrecedes(otherVersionParts, by: >)
        }

        return candidate.path < other.path
    }

    private func score(for installation: JavaInstallation, requiredMajorVersion: Int?) -> Int {
        guard let requiredMajorVersion else {
            return installation.majorVersion * 1000
        }

        if installation.majorVersion == requiredMajorVersion {
            return 1_000_000
        }

        if installation.majorVersion > requiredMajorVersion {
            // Prefer closer compatible versions first (e.g. 17 over 21 when 17 is required)
            return 500_000 - (installation.majorVersion - requiredMajorVersion)
        }

        return Int.min
    }

    private func detectInstalledJavaInstallations() -> [JavaInstallation] {
        let candidates = collectJavaCandidates()
        var installations: [JavaInstallation] = []
        var seenPaths = Set<String>()

        for candidate in candidates {
            guard let resolvedPath = resolveJavaExecutablePath(from: candidate) else {
                continue
            }
            guard !seenPaths.contains(resolvedPath) else {
                continue
            }
            seenPaths.insert(resolvedPath)

            if let installation = probeJavaInstallation(at: resolvedPath) {
                installations.append(installation)
            }
        }

        return installations
    }

    private func collectJavaCandidates() -> [String] {
        var candidates: [String] = []
        let homeDirectory = NSHomeDirectory()

        let fixedCandidates = [
            "/usr/bin/java",
            "/Library/Internet Plug-Ins/JavaAppletPlugin.plugin/Contents/Home/bin/java",
            "/System/Library/Frameworks/JavaVM.framework/Versions/Current/Commands/java",
        ]
        candidates.append(contentsOf: fixedCandidates)

        if let javaHomeEnvironment = ProcessInfo.processInfo.environment["JAVA_HOME"], !javaHomeEnvironment.isEmpty {
            candidates.append((javaHomeEnvironment as NSString).appendingPathComponent("bin/java"))
        }

        if let defaultHome = resolveJavaHomePath(requiredMajorVersion: nil) {
            candidates.append((defaultHome as NSString).appendingPathComponent("bin/java"))
        }

        for home in listJavaHomePaths() {
            candidates.append((home as NSString).appendingPathComponent("bin/java"))
        }

        appendJVMDirectoryCandidates(rootPath: "/Library/Java/JavaVirtualMachines", to: &candidates)
        appendJVMDirectoryCandidates(rootPath: "/System/Library/Java/JavaVirtualMachines", to: &candidates)
        appendJVMDirectoryCandidates(rootPath: (homeDirectory as NSString).appendingPathComponent("Library/Java/JavaVirtualMachines"), to: &candidates)

        appendBinaryDirectoryCandidates(rootPath: (homeDirectory as NSString).appendingPathComponent(".sdkman/candidates/java"), to: &candidates)
        appendBinaryDirectoryCandidates(rootPath: (homeDirectory as NSString).appendingPathComponent(".asdf/installs/java"), to: &candidates)
        appendBinaryDirectoryCandidates(rootPath: (homeDirectory as NSString).appendingPathComponent(".jdks"), to: &candidates)
        appendBinaryDirectoryCandidates(rootPath: (homeDirectory as NSString).appendingPathComponent(".gradle/jdks"), to: &candidates)

        appendHomebrewCandidates(rootPath: "/opt/homebrew/opt", to: &candidates)
        appendHomebrewCandidates(rootPath: "/usr/local/opt", to: &candidates)

        candidates.append(contentsOf: locateJavaFromPath())
        return candidates
    }

    private func appendJVMDirectoryCandidates(rootPath: String, to candidates: inout [String]) {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: rootPath) else {
            return
        }

        for entry in entries {
            let basePath = (rootPath as NSString).appendingPathComponent(entry)
            candidates.append((basePath as NSString).appendingPathComponent("Contents/Home/bin/java"))
            candidates.append((basePath as NSString).appendingPathComponent("Contents/Home/jre/bin/java"))
            candidates.append((basePath as NSString).appendingPathComponent("Contents/Commands/java"))
            candidates.append((basePath as NSString).appendingPathComponent("bin/java"))
        }
    }

    private func appendBinaryDirectoryCandidates(rootPath: String, to candidates: inout [String]) {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: rootPath) else {
            return
        }

        for entry in entries {
            let basePath = (rootPath as NSString).appendingPathComponent(entry)
            candidates.append((basePath as NSString).appendingPathComponent("bin/java"))
            candidates.append((basePath as NSString).appendingPathComponent("Contents/Home/bin/java"))
        }
    }

    private func appendHomebrewCandidates(rootPath: String, to candidates: inout [String]) {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: rootPath) else {
            return
        }

        for entry in entries where entry.hasPrefix("openjdk") {
            let basePath = (rootPath as NSString).appendingPathComponent(entry)
            candidates.append((basePath as NSString).appendingPathComponent("bin/java"))
            candidates.append((basePath as NSString).appendingPathComponent("libexec/openjdk.jdk/Contents/Home/bin/java"))
        }
    }

    private func locateJavaFromPath() -> [String] {
        guard let result = runProcess(executablePath: "/usr/bin/which", arguments: ["-a", "java"]),
              result.status == 0 else {
            return []
        }

        return result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func resolveJavaExecutablePath(from path: String) -> String? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        var candidatePath = trimmedPath
        if candidatePath.hasPrefix("~") {
            candidatePath = (candidatePath as NSString).expandingTildeInPath
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: candidatePath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let binaryCandidates = [
                    (candidatePath as NSString).appendingPathComponent("bin/java"),
                    (candidatePath as NSString).appendingPathComponent("jre/bin/java"),
                    (candidatePath as NSString).appendingPathComponent("Contents/Home/bin/java"),
                ]
                for binaryCandidate in binaryCandidates {
                    if fileManager.isExecutableFile(atPath: binaryCandidate) {
                        return URL(fileURLWithPath: binaryCandidate).resolvingSymlinksInPath().path
                    }
                }
                return nil
            }

            guard fileManager.isExecutableFile(atPath: candidatePath) else {
                return nil
            }
            return URL(fileURLWithPath: candidatePath).resolvingSymlinksInPath().path
        }

        return nil
    }

    private func probeJavaInstallation(at javaPath: String) -> JavaInstallation? {
        guard let result = runProcess(executablePath: javaPath, arguments: ["-version"]),
              result.status == 0 else {
            return nil
        }

        let output = result.output
        guard let versionString = parseJavaVersionString(from: output),
              let majorVersion = parseJavaMajorVersion(from: versionString) else {
            Logger.shared.warning("Unable to parse Java version information: \(javaPath)")
            return nil
        }

        return JavaInstallation(path: javaPath, majorVersion: majorVersion, versionString: versionString)
    }

    private func parseJavaVersionString(from output: String) -> String? {
        let quotedPattern = #"version\s+"([^"]+)""#
        if let match = firstRegexMatch(in: output, pattern: quotedPattern) {
            return match
        }

        let fallbackPattern = #"(?:openjdk|java)\s+([0-9][^\s"]*)"#
        return firstRegexMatch(in: output, pattern: fallbackPattern)
    }

    private func parseJavaMajorVersion(from versionString: String) -> Int? {
        if versionString.hasPrefix("1.") {
            let remainder = versionString.dropFirst(2)
            let secondPart = remainder.prefix { $0.isNumber }
            return Int(secondPart)
        }

        let firstPart = versionString.prefix { $0.isNumber }
        return Int(firstPart)
    }

    private func firstRegexMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[capturedRange])
    }

    private func extractNumericParts(_ text: String) -> [Int] {
        text
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }

    private func resolveJavaHomePath(requiredMajorVersion: Int?) -> String? {
        var arguments: [String] = []
        if let requiredMajorVersion {
            arguments = ["-v", "\(requiredMajorVersion)+"]
        }

        guard let result = runProcess(executablePath: javaHomeExecutable, arguments: arguments),
              result.status == 0 else {
            return nil
        }

        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private func listJavaHomePaths() -> [String] {
        guard let result = runProcess(executablePath: javaHomeExecutable, arguments: ["-V"]) else {
            return []
        }

        let lines = result.output.split(whereSeparator: \.isNewline)
        return lines.compactMap { line -> String? in
            let trimmedLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let slashIndex = trimmedLine.firstIndex(of: "/") else {
                return nil
            }

            let path = String(trimmedLine[slashIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }
    }

    private func runProcess(executablePath: String, arguments: [String]) -> (output: String, status: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: outputData, as: UTF8.self)
            return (output, process.terminationStatus)
        } catch {
            return nil
        }
    }
}
