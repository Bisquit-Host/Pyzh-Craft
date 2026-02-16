import SwiftUI
import UniformTypeIdentifiers

struct GameAdvancedSettingsView: View {
    @EnvironmentObject var gameRepository: GameRepository
    @StateObject private var selectedGameManager = SelectedGameManager.shared

    @State private var memoryRange: ClosedRange<Double> = Double(GameSettingsManager.shared.globalXms)...Double(GameSettingsManager.shared.globalXmx)
    @State private var selectedGarbageCollector: GarbageCollector = .g1gc
    @State private var optimizationPreset: OptimizationPreset = .balanced
    @State private var enableOptimizations: Bool = true
    @State private var enableAikarFlags: Bool = false
    @State private var enableMemoryOptimizations: Bool = true
    @State private var enableThreadOptimizations: Bool = true
    @State private var enableNetworkOptimizations: Bool = false
    @State private var customJvmArguments: String = ""
    @State private var environmentVariables: String = ""
    @State private var javaPath: String = ""
    @State private var showResetAlert = false
    @State private var showJavaPathPicker = false
    @State private var error: GlobalError?
    @State private var isLoadingSettings = false
    @State private var saveTask: Task<Void, Never>?

    private var currentGame: GameVersionInfo? {
        guard let gameId = selectedGameManager.selectedGameId else { return nil }
        return gameRepository.getGame(by: gameId)
    }

    /// Whether to use custom JVM parameters (mutually exclusive with garbage collector and performance optimization)
    private var isUsingCustomArguments: Bool {
        !customJvmArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Get the Java version of the current game
    private var currentJavaVersion: Int {
        currentGame?.javaVersion ?? 8
    }

    /// Get available garbage collectors based on current Java version
    private var availableGarbageCollectors: [GarbageCollector] {
        GarbageCollector.allCases.filter { gc in
            gc.isSupported(by: currentJavaVersion)
        }
    }

    /// Get available optimization presets based on the currently selected garbage collector
    /// Maximum optimization is only available with G1GC
    private var availableOptimizationPresets: [OptimizationPreset] {
        if selectedGarbageCollector == .g1gc {
            // G1GC supports all optimization presets, including maximum optimization
            return OptimizationPreset.allCases
        } else {
            // Maximum optimization is not supported for non-G1GC (as Aikar Flags only apply to G1GC)
            return OptimizationPreset.allCases.filter { $0 != .maximum }
        }
    }

    var body: some View {
        Form {
            LabeledContent("Java Path") {
                DirectorySettingRow(
                    title: "Java Path",
                    path: javaPath.isEmpty ? (currentGame?.javaPath ?? "") : javaPath,
                    description: String(localized: "The path to the Java executable file. Click to choose or reset to the default path."),
                    onChoose: { showJavaPathPicker = true },
                    onReset: {
                        resetJavaPathSafely()
                    }
                ).fixedSize()
                    .fileImporter(
                        isPresented: $showJavaPathPicker,
                        allowedContentTypes: [.item],
                        allowsMultipleSelection: false
                    ) { result in
                        handleJavaPathSelection(result)
                    }
            }.labeledContentStyle(.custom(alignment: .firstTextBaseline))

            LabeledContent("Garbage Collector") {
                HStack {
                    Picker("", selection: $selectedGarbageCollector) {
                        ForEach(availableGarbageCollectors, id: \.self) { gc in
                            Text(gc.displayName).tag(gc)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(isUsingCustomArguments)  // Disabled when using custom parameters
                    .onChange(of: selectedGarbageCollector) { _, _ in
                        if !isUsingCustomArguments {
                            // If the selected garbage collector does not support the current Java version, automatically switches to a supported option
                            if !selectedGarbageCollector.isSupported(by: currentJavaVersion) {
                                selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
                            }
                            autoSave()
                        }
                    }
                    InfoIconWithPopover(text: selectedGarbageCollector.description)
                }
            }
            .labeledContentStyle(.custom(alignment: .firstTextBaseline))
            .opacity(isUsingCustomArguments ? 0.5 : 1.0)  // Reduce transparency when disabled

            LabeledContent("Performance Optimization") {
                HStack {
                    Picker("", selection: $optimizationPreset) {
                        // Maximum optimization is only available with G1GC
                        ForEach(availableOptimizationPresets, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(isUsingCustomArguments)  // Disabled when using custom parameters
                    .onChange(of: optimizationPreset) { _, newValue in
                        if !isUsingCustomArguments {
                            applyOptimizationPreset(newValue)
                            autoSave()
                        }
                    }
                    .onChange(of: selectedGarbageCollector) { _, _ in
                        // When the garbage collector changes, switch to balanced optimization if currently max-optimized but not G1GC
                        if optimizationPreset == .maximum && selectedGarbageCollector != .g1gc {
                            optimizationPreset = .balanced
                            applyOptimizationPreset(.balanced)
                            autoSave()
                        }
                    }
                    InfoIconWithPopover(text: optimizationPreset.description)
                }
            }
            .labeledContentStyle(.custom(alignment: .firstTextBaseline))
            .opacity(isUsingCustomArguments ? 0.5 : 1.0)  // Reduce transparency when disabled

            LabeledContent("Memory Settings") {
                HStack {
                    MiniRangeSlider(
                        range: $memoryRange,
                        bounds: 512...Double(GameSettingsManager.shared.maximumMemoryAllocation)
                    )
                    .frame(width: 200)
                    .controlSize(.mini)
                    .onChange(of: memoryRange) { _, _ in autoSave() }
                    Text("\(Int(memoryRange.lowerBound)) MB-\(Int(memoryRange.upperBound)) MB")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .labeledContentStyle(.custom)

            LabeledContent("Custom Parameters") {
                HStack {
                    TextField("", text: $customJvmArguments)
                        .focusable(false)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .frame(width: 200)
                        .onChange(of: customJvmArguments) { _, _ in autoSave() }
                    InfoIconWithPopover(text: String(localized: "Note: Custom parameters will override the optimization settings above"))
                }
            }
            .labeledContentStyle(.custom(alignment: .firstTextBaseline))

            LabeledContent {
                HStack {
                    TextField("", text: $environmentVariables, axis: .vertical)
                        .focusable(false)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .frame(width: 200)
                        .onChange(of: environmentVariables) { _, _ in autoSave() }
                    InfoIconWithPopover(text: String(localized: "For example: `JAVA_OPTS=-Dfile.encoding=UTF-8`"))
                }
            } label: {
                Text("Environment Variables")
            }
            .labeledContentStyle(.custom)
        }
        .onAppear { loadCurrentSettings() }
        .onChange(of: selectedGameManager.selectedGameId) { _, _ in loadCurrentSettings() }
        .globalErrorHandler()
        .alert(
            "Are you sure you want to restore default settings?",
            isPresented: $showResetAlert
        ) {
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Validation Error",
            isPresented: .constant(error != nil && error?.level == .popup)
        ) {
            Button("Close") {
                error = nil
            }
        } message: {
            if let error {
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - Private Methods

    private func loadCurrentSettings() {
        guard let game = currentGame else { return }
        isLoadingSettings = true
        defer { isLoadingSettings = false }

        let xms = game.xms == 0 ? GameSettingsManager.shared.globalXms : game.xms
        let xmx = game.xmx == 0 ? GameSettingsManager.shared.globalXmx : game.xmx
        memoryRange = Double(xms)...Double(xmx)
        environmentVariables = game.environmentVariables
        javaPath = game.javaPath

        let jvmArgs = game.jvmArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if jvmArgs.isEmpty {
            customJvmArguments = ""
            // Select default garbage collector based on Java version
            selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
            optimizationPreset = .balanced
            applyOptimizationPreset(.balanced)
        } else {
            customJvmArguments = parseExistingJvmArguments(jvmArgs) ? "" : jvmArgs
            // If the resolved garbage collector does not support the current Java version, automatically switch to a supported option
            if !selectedGarbageCollector.isSupported(by: currentJavaVersion) {
                selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
                applyOptimizationPreset(.balanced)
            }
        }
    }

    private func parseExistingJvmArguments(_ arguments: String) -> Bool {
        let args = arguments.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        let gcMap: [(String, GarbageCollector)] = [
            ("-XX:+UseG1GC", .g1gc),
            ("-XX:+UseZGC", .zgc),
            ("-XX:+UseShenandoahGC", .shenandoah),
            ("-XX:+UseParallelGC", .parallel),
            ("-XX:+UseSerialGC", .serial),
        ]

        guard let (_, gc) = gcMap.first(where: { args.contains($0.0) }) else {
            selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
            optimizationPreset = .balanced
            applyOptimizationPreset(.balanced)
            return false
        }

        // Verify that the garbage collector supports the current Java version
        if gc.isSupported(by: currentJavaVersion) {
            selectedGarbageCollector = gc
        } else {
            // If not supported, use the default supported garbage collector
            Logger.shared.warning("检测到不兼容的垃圾回收器 \(gc.displayName)（需要 Java \(gc.minimumJavaVersion)+，当前 Java \(currentJavaVersion)），自动切换到兼容选项")
            selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
            optimizationPreset = .balanced
            applyOptimizationPreset(.balanced)
            return false
        }
        // Parsing optimization options
        enableOptimizations = args.contains("-XX:+OptimizeStringConcat") ||
                             args.contains("-XX:+OmitStackTraceInFastThrow")
        enableMemoryOptimizations = args.contains("-XX:+UseCompressedOops") ||
                                   args.contains("-XX:+UseCompressedClassPointers") ||
                                   args.contains("-XX:+UseCompactObjectHeaders")
        enableThreadOptimizations = args.contains("-XX:+OmitStackTraceInFastThrow")

        if selectedGarbageCollector == .g1gc {
            enableAikarFlags = args.contains("-XX:+ParallelRefProcEnabled") &&
                              args.contains("-XX:MaxGCPauseMillis=200") &&
                              args.contains("-XX:+AlwaysPreTouch")
        } else {
            enableAikarFlags = false
        }

        enableNetworkOptimizations = args.contains("-Djava.net.preferIPv4Stack=true")
        updateOptimizationPreset()

        // Ensure maximum optimization is only available during G1GC
        if optimizationPreset == .maximum && selectedGarbageCollector != .g1gc {
            optimizationPreset = .balanced
            applyOptimizationPreset(.balanced)
        }
        return true
    }

    private func applyOptimizationPreset(_ preset: OptimizationPreset) {
        switch preset {
        case .disabled:
            enableOptimizations = false
            enableAikarFlags = false
            enableMemoryOptimizations = false
            enableThreadOptimizations = false
            enableNetworkOptimizations = false

        case .basic, .balanced:
            enableOptimizations = true
            enableAikarFlags = false
            enableMemoryOptimizations = true
            enableThreadOptimizations = true
            enableNetworkOptimizations = false

        case .maximum:
            enableOptimizations = true
            enableAikarFlags = true
            enableMemoryOptimizations = true
            enableThreadOptimizations = true
            enableNetworkOptimizations = true
        }
    }

    private func updateOptimizationPreset() {
        if !enableOptimizations {
            optimizationPreset = .disabled
        } else if enableAikarFlags && enableNetworkOptimizations {
            optimizationPreset = .maximum
        } else if enableMemoryOptimizations && enableThreadOptimizations {
            optimizationPreset = .balanced
        } else {
            optimizationPreset = .basic
        }
    }

    private func generateJvmArguments() -> String {
        let trimmed = customJvmArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return customJvmArguments
        }

        // Make sure the selected garbage collector supports the current Java version
        let gc = selectedGarbageCollector.isSupported(by: currentJavaVersion)
            ? selectedGarbageCollector
            : (availableGarbageCollectors.first ?? .g1gc)

        var arguments: [String] = []
        arguments.append(contentsOf: gc.arguments)

        if gc == .g1gc {
            arguments.append(contentsOf: [
                "-XX:+ParallelRefProcEnabled",
                "-XX:MaxGCPauseMillis=200",
            ])

            if enableAikarFlags {
                arguments.append(contentsOf: [
                    "-XX:+UnlockExperimentalVMOptions",
                    "-XX:+DisableExplicitGC",
                    "-XX:+AlwaysPreTouch",
                    "-XX:G1NewSizePercent=30",
                    "-XX:G1MaxNewSizePercent=40",
                    "-XX:G1HeapRegionSize=8M",
                    "-XX:G1ReservePercent=20",
                    "-XX:G1HeapWastePercent=5",
                    "-XX:G1MixedGCCountTarget=4",
                    "-XX:InitiatingHeapOccupancyPercent=15",
                    "-XX:G1MixedGCLiveThresholdPercent=90",
                    "-XX:G1RSetUpdatingPauseTimePercent=5",
                    "-XX:SurvivorRatio=32",
                    "-XX:MaxTenuringThreshold=1",
                ])
            }
        }

        if enableOptimizations {
            arguments.append(contentsOf: [
                "-XX:+OptimizeStringConcat",
                "-XX:+OmitStackTraceInFastThrow",
            ])
        }

        // Memory optimization parameters
        // Java 8-14: UseCompressedOops and UseCompressedClassPointers bindings
        // Java 15-24: Explicitly specify Oops + ClassPointers
        // Java 25+: additionally enable CompactObjectHeaders
        if enableMemoryOptimizations {
            if currentJavaVersion < 15 {
                arguments.append("-XX:+UseCompressedOops")
            } else if currentJavaVersion < 25 {
                arguments.append(contentsOf: [
                    "-XX:+UseCompressedOops",
                    "-XX:+UseCompressedClassPointers",
                ])
            } else {
                arguments.append(contentsOf: [
                    "-XX:+UseCompressedOops",
                    "-XX:+UseCompressedClassPointers",
                    "-XX:+UseCompactObjectHeaders",
                ])
            }
        }

        if enableNetworkOptimizations {
            arguments.append("-Djava.net.preferIPv4Stack=true")
        }

        return arguments.joined(separator: " ")
    }

    private func autoSave() {
        // If settings are loading, auto-save is not triggered
        guard !isLoadingSettings, currentGame != nil else { return }

        // Cancel previous save task
        saveTask?.cancel()

        // Use anti-shake mechanism, save after delaying 0.5 seconds
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            guard !Task.isCancelled else { return }

            do {
                guard let game = currentGame else { return }
                let xms = Int(memoryRange.lowerBound)
                let xmx = Int(memoryRange.upperBound)

                guard xms > 0 && xmx > 0 else { return }
                guard xms <= xmx else { return }

                var updatedGame = game
                updatedGame.xms = xms
                updatedGame.xmx = xmx
                updatedGame.jvmArguments = generateJvmArguments()
                updatedGame.environmentVariables = environmentVariables
                updatedGame.javaPath = javaPath

                try await gameRepository.updateGame(updatedGame)
                Logger.shared.debug("自动保存游戏设置: \(game.gameName)")
            } catch {
                let globalError = error as? GlobalError ?? GlobalError.unknown(i18nKey: "Failed to save settings",
                    level: .notification
                )
                Logger.shared.error("自动保存游戏设置失败: \(globalError.chineseMessage)")
                await MainActor.run { self.error = globalError }
            }
        }
    }

    private func resetToDefaults() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }

        memoryRange = Double(GameSettingsManager.shared.globalXms)...Double(GameSettingsManager.shared.globalXmx)
        // Select default garbage collector based on Java version
        selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
        optimizationPreset = .balanced
        applyOptimizationPreset(.balanced)
        customJvmArguments = ""
        environmentVariables = ""
        resetJavaPathSafely()
        autoSave()
    }

    /// Safely reset Java paths
    private func resetJavaPathSafely() {
        guard let game = currentGame else { return }

        Task {
            let defaultPath = await JavaManager.shared.findDefaultJavaPath(for: game.gameVersion)
            await MainActor.run {
                javaPath = defaultPath
                autoSave()
            }
        }
    }

    /// Handling Java path selection results
    private func handleJavaPathSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                // Verify that the file exists and is executable
                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: url.path) else {
                    error = GlobalError.fileSystem(i18nKey: "File Not Found",
                        level: .notification
                    )
                    return
                }

                // Verify if it is an executable file (verified through JavaManager)
                if JavaManager.shared.canJavaRun(at: url.path) {
                    javaPath = url.path
                    autoSave()
                    Logger.shared.info("Java路径已设置为: \(url.path)")
                } else {
                    error = GlobalError.validation(i18nKey: "The selected file is not a valid Java executable",
                        level: .popup
                    )
                }
            }
        case .failure(let error):
            let globalError = GlobalError.fileSystem(i18nKey: "Java Path Selection Failed",
                level: .notification
            )
            self.error = globalError
        }
    }
}

// MARK: - Garbage Collector Enum

enum GarbageCollector: String, CaseIterable {
    case g1gc, zgc, shenandoah, parallel, serial

    /// Minimum Java version required for garbage collector
    var minimumJavaVersion: Int {
        switch self {
        case .g1gc: 7      // Java 7+ (G1GC is available in Java 7u4+)
        case .parallel: 1   // Java 1.0+ (all versions supported)
        case .serial: 1     // Java 1.0+ (all versions supported)
        case .zgc: 11      // Java 11+ (ZGC was introduced in Java 11)
        case .shenandoah: 12 // Java 12+ (Shenandoah was introduced in Java 12)
        }
    }

    /// Checks whether the garbage collector supports the specified Java version
    /// - Parameter javaVersion: Java major version number (such as 8, 11, 17)
    /// - Returns: Whether supported
    func isSupported(by javaVersion: Int) -> Bool {
        javaVersion >= minimumJavaVersion
    }

    var displayName: String {
        switch self {
        case .g1gc: String(localized: "G1GC (recommended)")
        case .zgc: String(localized: "ZGC (Low Latency)")
        case .shenandoah: String(localized: "Shenandoah (Low Pause)")
        case .parallel: String(localized: "ParallelGC (High Throughput)")
        case .serial: String(localized: "SerialGC (Single Thread)")
        }
    }

    var description: String {
        switch self {
        case .g1gc: String(localized: "G1 garbage collector, balancing performance and latency, suitable for most scenarios")
        case .zgc: String(localized: "ZGC garbage collector, extremely low latency, suitable for scenarios with extremely high response time requirements")
        case .shenandoah:
            String(localized: "Shenandoah garbage collector, low pause time, suitable for scenarios requiring stable performance")
        case .parallel: String(localized: "Parallel garbage collector, high throughput, suitable for background processing tasks")
        case .serial: String(localized: "Serial garbage collector, single-threaded, suitable for small memory applications")
        }
    }

    var arguments: [String] {
        switch self {
        case .g1gc: ["-XX:+UseG1GC"]
        case .zgc: ["-XX:+UseZGC"]
        case .shenandoah: ["-XX:+UseShenandoahGC"]
        case .parallel: ["-XX:+UseParallelGC"]
        case .serial: ["-XX:+UseSerialGC"]
        }
    }
}

// MARK: - Optimization Preset Enum

enum OptimizationPreset: String, CaseIterable {
    case disabled, basic, balanced, maximum

    var displayName: String {
        switch self {
        case .disabled: String(localized: "None")
        case .basic: String(localized: "Basic")
        case .balanced:
            String(localized: "Balanced")
        case .maximum:
            String(localized: "Maximum")
        }
    }

    var description: String {
        switch self {
        case .disabled:
            String(localized: "No JVM optimizations enabled")
        case .basic:
            String(localized: "Basic JVM optimizations for improved performance")
        case .balanced:
            String(localized: "Balanced optimizations for good performance and stability (recommended)")
        case .maximum:
            String(localized: "Maximum optimizations including Aikar flags for best performance")
        }
    }
}
