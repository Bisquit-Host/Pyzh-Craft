import Foundation
import ZIPFoundation

/// Forge/NeoForge Processor executor
enum ProcessorExecutor {

    /// Execute a single processor
    /// - Parameters:
    ///   - processor: processor configuration
    ///   - librariesDir: library directory
    ///   - gameVersion: game version (for placeholder replacement)
    ///   - data: data field, used for placeholder replacement
    /// - Throws: GlobalError when processing fails
    static func executeProcessor(
        _ processor: Processor,
        librariesDir: URL,
        gameVersion: String,
        javaPath: String,
        data: [String: String]? = nil
    ) async throws {
        // 1. Verify and prepare JAR files
        let jarPath = try validateAndGetJarPath(
            processor.jar,
            librariesDir: librariesDir
        )

        // 2. Build classpath
        let classpath = try buildClasspath(
            processor.classpath,
            jarPath: jarPath,
            librariesDir: librariesDir
        )

        // 3. Get the main class
        let mainClass = try getMainClassFromJar(jarPath: jarPath)

        // 4. Build Java commands
        let command = buildJavaCommand(
            classpath: classpath,
            mainClass: mainClass,
            args: processor.args,
            gameVersion: gameVersion,
            librariesDir: librariesDir,
            data: data
        )

        // 5. Execute Java commands
        try await executeJavaCommand(command, javaPath: javaPath, workingDir: librariesDir)

        // 6. Process output files
        if let outputs = processor.outputs {
            try await processOutputs(outputs, workingDir: librariesDir)
        }
    }

    // MARK: - Private Helper Methods

    private static func validateAndGetJarPath(
        _ jar: String?,
        librariesDir: URL
    ) throws -> URL {
        guard let jar = jar else {
            throw GlobalError.validation(
                i18nKey: "Processor Missing JAR",
                level: .notification
            )
        }

        guard
            let relativePath = CommonService.mavenCoordinateToRelativePath(jar)
        else {
            throw GlobalError.validation(
                i18nKey: "Invalid Maven Coordinate",
                level: .notification
            )
        }

        let jarPath = librariesDir.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: jarPath.path) else {
            throw GlobalError.resource(
                i18nKey: "Processor Jar Not Found",
                level: .notification
            )
        }

        return jarPath
    }

    private static func buildClasspath(
        _ processorClasspath: [String]?,
        jarPath: URL,
        librariesDir: URL
    ) throws -> [String] {
        var classpath: [String] = []

        if let processorClasspath = processorClasspath {
            for cp in processorClasspath {
                let cpPath =
                    cp.contains(":")
                    ? try getMavenPath(cp, librariesDir: librariesDir)
                    : librariesDir.appendingPathComponent(cp)

                if FileManager.default.fileExists(atPath: cpPath.path) {
                    classpath.append(cpPath.path)
                } else {
                    Logger.shared.warning("classpath文件不存在: \(cpPath.path)")
                }
            }
        }

        classpath.append(jarPath.path)

        return classpath
    }

    private static func getMavenPath(
        _ coordinate: String,
        librariesDir: URL
    ) throws -> URL {
        // Use methods that support the @ symbol to handle Maven coordinates
        let relativePath: String

        if coordinate.contains("@") {
            // For coordinates containing the @ symbol (such as org.ow2.asm:asm:9.3@jar), special handling is used
            relativePath = CommonService.parseMavenCoordinateWithAtSymbol(
                coordinate
            )
        } else {
            // For standard coordinates, use the original method
            guard
                let path = CommonService.mavenCoordinateToRelativePath(
                    coordinate
                )
            else {
                throw GlobalError.validation(
                    i18nKey: "Invalid Maven Coordinate",
                    level: .notification
                )
            }
            relativePath = path
        }

        return librariesDir.appendingPathComponent(relativePath)
    }

    private static func buildJavaCommand(
        classpath: [String],
        mainClass: String,
        args: [String]?,
        gameVersion: String,
        librariesDir: URL,
        data: [String: String]?
    ) -> [String] {
        var command = ["-cp", classpath.joined(separator: ":")]
        command.append(mainClass)

        if let args = args {
            let processedArgs: [String] = args.compactMap { arg in
                guard let extractedValue = CommonFileManager.extractClientValue(from: arg) else {
                    Logger.shared.warning("无法提取客户端值: \(arg)")
                    return nil
                }
                return processPlaceholders(
                    extractedValue,
                    gameVersion: gameVersion,
                    librariesDir: librariesDir,
                    data: data
                )
            }
            command.append(contentsOf: processedArgs)
        }

        return command
    }

    private static func processPlaceholders(
        _ arg: String,
        gameVersion: String,
        librariesDir: URL,
        data: [String: String]?
    ) -> String {
        // Quick check: if the string does not contain any placeholders, just return
        guard arg.contains("{") else {
            return arg
        }

        // Use NSMutableString to avoid creating lots of temporary strings in loops
        let processedArg = NSMutableString(string: arg)

        // Basic placeholder replacement
        let basicReplacements = [
            AppConstants.ProcessorPlaceholders.side: AppConstants.EnvironmentTypes.client,
            AppConstants.ProcessorPlaceholders.version: gameVersion,
            AppConstants.ProcessorPlaceholders.versionName: gameVersion,
            AppConstants.ProcessorPlaceholders.libraryDir: librariesDir.path,
            AppConstants.ProcessorPlaceholders.workingDir: librariesDir.path,
        ]

        for (placeholder, value) in basicReplacements where processedArg.range(of: placeholder).location != NSNotFound {
            // First check whether it contains placeholders to avoid unnecessary replacement operations
            processedArg.replaceOccurrences(
                of: placeholder,
                with: value,
                options: [],
                range: NSRange(location: 0, length: processedArg.length)
            )
        }

        // Handling placeholder replacement for data fields
        if let data = data {
            for (key, value) in data {
                let placeholder = "{\(key)}"
                // First check whether it contains placeholders to avoid unnecessary processing
                if processedArg.range(of: placeholder).location != NSNotFound {
                    let replacementValue =
                        value.contains(":") && !value.hasPrefix("/")
                    ? (
                        CommonFileManager.extractClientValue(from: value).map {
                            librariesDir.appendingPathComponent($0).path
                        } ?? value) : value

                    processedArg.replaceOccurrences(
                        of: placeholder,
                        with: replacementValue,
                        options: [],
                        range: NSRange(location: 0, length: processedArg.length)
                    )
                }
            }
        }

        return processedArg as String
    }

    private static func executeJavaCommand(
        _ command: [String],
        javaPath: String,
        workingDir: URL
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaPath)
        process.arguments = command
        process.currentDirectoryURL = workingDir

        // Set environment variables
        var environment = ProcessInfo.processInfo.environment
        environment["LIBRARY_DIR"] = workingDir.path
        process.environment = environment

        // capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            // Read output in real time
            setupOutputHandlers(outputPipe: outputPipe, errorPipe: errorPipe)

            process.waitUntilExit()

            // Clean up handlers
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            if process.terminationStatus != 0 {
                throw GlobalError.download(
                    i18nKey: "Processor Execution Failed (Exit Code: %d)",
                    level: .notification
                )
            }
        } catch {
            throw GlobalError.download(
                i18nKey: "Processor Start Failed",
                level: .notification
            )
        }
    }

    private static func setupOutputHandlers(outputPipe: Pipe, errorPipe: Pipe) {
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, String(data: data, encoding: .utf8) != nil {
                // Output data has been read to prevent pipe blocking
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, String(data: data, encoding: .utf8) != nil {
                // Error output data has been read to prevent pipe blocking
            }
        }
    }

    private static func processOutputs(
        _ outputs: [String: String],
        workingDir: URL
    ) async throws {
        let fileManager = FileManager.default

        for (source, destination) in outputs {
            let sourceURL = workingDir.appendingPathComponent(source)
            let destURL = workingDir.appendingPathComponent(destination)

            // Make sure the target directory exists
            try fileManager.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Move or copy files
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.moveItem(at: sourceURL, to: destURL)
            }
        }
    }

    private static func getMainClassFromJar(jarPath: URL) throws -> String {
        let archive: Archive
        do {
            archive = try Archive(url: jarPath, accessMode: .read)
        } catch {
            throw GlobalError.download(
                i18nKey: "Failed to Open JAR File: %@",
                level: .notification
            )
        }

        guard let manifestEntry = archive["META-INF/MANIFEST.MF"] else {
            throw GlobalError.download(
                i18nKey: "Failed to get main class from processor JAR file: %@",
                level: .notification
            )
        }

        var manifestData = Data()
        _ = try archive.extract(manifestEntry) { data in
            manifestData.append(data)
        }

        guard let manifestContent = String(data: manifestData, encoding: .utf8)
        else {
            throw GlobalError.download(
                i18nKey: "Manifest Parse Failed",
                level: .notification
            )
        }

        // Parse MANIFEST.MF to find Main-Class
        let lines = manifestContent.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("Main-Class:") {
                let mainClass = trimmedLine.dropFirst("Main-Class:".count)
                    .trimmingCharacters(in: .whitespaces)
                return mainClass
            }
        }

        throw GlobalError.download(
            i18nKey: "Failed to get main class from processor JAR file: %@",
            level: .notification
        )
    }
}
