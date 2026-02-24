import SwiftUI
import UniformTypeIdentifiers

struct GameAdvancedSettingsView: View {
    @EnvironmentObject var gameRepository: GameRepository
    @StateObject private var selectedGameManager = SelectedGameManager.shared
    
    @State private var memoryRange: ClosedRange<Double> = Double(GameSettingsManager.shared.globalXms)...Double(GameSettingsManager.shared.globalXmx)
    @State private var selectedGarbageCollector: GarbageCollector = .g1gc
    @State private var additionalJvmFlags = ""
    @State private var environmentVariables = ""
    @State private var javaPath = ""
    @State private var showResetAlert = false
    @State private var showJavaPathPicker = false
    @State private var error: GlobalError?
    @State private var isLoadingSettings = false
    @State private var saveTask: Task<Void, Never>?
    @State private var detectedJavaRuntimes: [JavaManager.DetectedJavaRuntime] = []
    @State private var selectedDetectedJavaPath = ""
    @State private var isLoadingDetectedJavaRuntimes = false
    
    private var currentGame: GameVersionInfo? {
        guard let gameId = selectedGameManager.selectedGameId else { return nil }
        return gameRepository.getGame(by: gameId)
    }
    
    /// Get the Java version of the current game
    private var currentJavaVersion: Int {
        currentGame?.javaVersion ?? 8
    }
    
    /// Effective Java path (user-set or game default)
    private var effectiveJavaPath: String {
        javaPath.isEmpty ? (currentGame?.javaPath ?? "") : javaPath
    }
    
    /// Get available garbage collectors based on current Java version
    private var availableGarbageCollectors: [GarbageCollector] {
        GarbageCollector.allCases.filter { gc in
            gc.isSupported(by: currentJavaVersion)
        }
    }
    
    private let gcFlagMap: [(String, GarbageCollector)] = [
        ("-XX:+UseG1GC", .g1gc),
        ("-XX:+UseZGC", .zgc),
        ("-XX:+UseShenandoahGC", .shenandoah),
        ("-XX:+UseParallelGC", .parallel),
        ("-XX:+UseSerialGC", .serial),
    ]
    
    /// Legacy G1 tuning flags from the removed "maximum" preset.
    private let legacyManagedG1Flags: Set<String> = [
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
    ]
    
    var body: some View {
        Form {
            LabeledContent("Java Executable") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Picker("", selection: $selectedDetectedJavaPath) {
                            Text("Select Java Runtime")
                                .tag("")
                            ForEach(detectedJavaRuntimes) { runtime in
                                Text(detectedJavaLabel(runtime))
                                    .tag(runtime.path)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: selectedDetectedJavaPath) { _, newValue in
                            guard !newValue.isEmpty else { return }
                            guard javaPath != newValue else { return }
                            javaPath = newValue
                            autoSave()
                        }
                        
                        Button {
                            loadDetectedJavaRuntimes()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh installed Java list")
                        
                        if isLoadingDetectedJavaRuntimes {
                            ProgressView()
                                .controlSize(.small)
                        }
                        
                        Button("Browse\u{2026}") {
                            showJavaPathPicker = true
                        }
                        .help("Choose a Java executable manually")
                        
                        Button("Reset") {
                            resetJavaPathSafely()
                        }
                        .help("Reset to default Java for this version")
                    }
                    
                    if !effectiveJavaPath.isEmpty {
                        PathBreadcrumbView(path: effectiveJavaPath)
                            .help(effectiveJavaPath)
                    }
                }
                .fileImporter(
                    isPresented: $showJavaPathPicker,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: false
                ) { result in
                    handleJavaPathSelection(result)
                }
            }
            .labeledContentStyle(.custom(alignment: .firstTextBaseline))
            
            LabeledContent("Garbage Collector") {
                HStack {
                    Picker("", selection: $selectedGarbageCollector) {
                        ForEach(availableGarbageCollectors, id: \.self) {
                            Text($0.displayName)
                                .tag($0)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: selectedGarbageCollector) { _, _ in
                        // If the selected garbage collector does not support the current Java version, automatically switches to a supported option
                        if !selectedGarbageCollector.isSupported(by: currentJavaVersion) {
                            selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
                        }
                        sanitizeAdditionalFlags(for: selectedGarbageCollector)
                        autoSave()
                    }
                    InfoIconWithPopover(text: selectedGarbageCollector.description)
                }
            }
            .labeledContentStyle(.custom(alignment: .firstTextBaseline))
            
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
            
            LabeledContent("Additional Flags") {
                HStack {
                    TextField("", text: $additionalJvmFlags, axis: .vertical)
                        .focusable(false)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .frame(width: 200)
                        .onChange(of: additionalJvmFlags) {
                            autoSave()
                        }
                    
                    InfoIconWithPopover(text: "These flags are appended to the generated JVM arguments")
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
                    
                    InfoIconWithPopover(text: "For example: `JAVA_OPTS=-Dfile.encoding=UTF-8`")
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
        selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
        additionalJvmFlags = ""
        
        let jvmArgs = game.jvmArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if !jvmArgs.isEmpty {
            parseExistingJvmArguments(jvmArgs)
        }
        
        syncSelectedDetectedJavaPath()
        loadDetectedJavaRuntimes()
    }
    
    private func loadDetectedJavaRuntimes() {
        let requiredJavaVersion = currentJavaVersion
        isLoadingDetectedJavaRuntimes = true
        
        Task {
            let runtimes = await Task.detached(priority: .userInitiated) {
                JavaManager.shared.listInstalledJavaRuntimes(
                    requiredMajorVersion: requiredJavaVersion,
                    includeIncompatible: true
                )
            }.value
            
            await MainActor.run {
                detectedJavaRuntimes = runtimes
                isLoadingDetectedJavaRuntimes = false
                syncSelectedDetectedJavaPath()
            }
        }
    }
    
    private func detectedJavaLabel(_ runtime: JavaManager.DetectedJavaRuntime) -> String {
        let version = "Java \(runtime.majorVersion) (\(runtime.versionString))"
        
        // Extract JVM name from standard macOS path (e.g. "temurin-21" from ".../JavaVirtualMachines/temurin-21.jdk/...")
        let components = runtime.path.split(separator: "/").map(String.init)
        let shortName: String
        if let jvmIdx = components.firstIndex(of: "JavaVirtualMachines"),
           jvmIdx + 1 < components.count {
            shortName = components[jvmIdx + 1]
                .replacingOccurrences(of: ".jdk", with: "")
                .replacingOccurrences(of: ".jre", with: "")
        } else {
            shortName = runtime.path
        }
        
        let suffix = runtime.majorVersion < currentJavaVersion
        ? " (incompatible)"
        : ""
        
        return "\(version) — \(shortName)\(suffix)"
    }
    
    private func syncSelectedDetectedJavaPath() {
        selectedDetectedJavaPath = detectedJavaRuntimes.contains(where: { $0.path == javaPath })
        ? javaPath
        : ""
    }
    
    private func parseExistingJvmArguments(_ arguments: String) {
        let args = arguments.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        if let (_, gc) = gcFlagMap.first(where: { args.contains($0.0) }), gc.isSupported(by: currentJavaVersion) {
            selectedGarbageCollector = gc
        } else {
            selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
        }
        
        let managedArgs = Set(defaultManagedArguments(for: selectedGarbageCollector) + gcFlagMap.map(\.0))
            .union(legacyManagedG1Flags)
        let extras = args.filter { !managedArgs.contains($0) }
        additionalJvmFlags = extras.joined(separator: " ")
    }
    
    private func sanitizeAdditionalFlags(for gc: GarbageCollector) {
        guard gc != .g1gc else { return }
        
        let filtered = additionalJvmFlags
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !legacyManagedG1Flags.contains($0) }
        additionalJvmFlags = filtered.joined(separator: " ")
    }
    
    private func generateJvmArguments() -> String {
        // Make sure the selected garbage collector supports the current Java version
        let gc = selectedGarbageCollector.isSupported(by: currentJavaVersion)
        ? selectedGarbageCollector
        : (availableGarbageCollectors.first ?? .g1gc)
        
        var arguments: [String] = []
        arguments.append(contentsOf: gc.arguments)
        
        arguments.append(contentsOf: defaultManagedArguments(for: gc))
        
        let extras = additionalJvmFlags
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        if !extras.isEmpty {
            arguments.append(contentsOf: extras)
        }
        
        return arguments.joined(separator: " ")
    }
    
    private func defaultManagedArguments(for gc: GarbageCollector) -> [String] {
        var arguments: [String] = []
        
        if gc == .g1gc {
            arguments.append(contentsOf: [
                "-XX:+ParallelRefProcEnabled",
                "-XX:MaxGCPauseMillis=200",
            ])
        }
        
        arguments.append(contentsOf: [
            "-XX:+OptimizeStringConcat",
            "-XX:+OmitStackTraceInFastThrow",
        ])
        
        // Memory optimization parameters
        // Java 8-14: UseCompressedOops only
        // Java 15-24: Oops + ClassPointers
        // Java 25+: Oops + ClassPointers + CompactObjectHeaders
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
        
        return arguments
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
                Logger.shared.debug("Auto-save game settings: \(game.gameName)")
            } catch {
                let globalError = error as? GlobalError ?? GlobalError.unknown(
                    i18nKey: "Failed to save settings",
                    level: .notification
                )
                Logger.shared.error("Auto-save game settings failed: \(globalError.chineseMessage)")
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
        additionalJvmFlags = ""
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
                syncSelectedDetectedJavaPath()
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
                    error = GlobalError.fileSystem(
                        i18nKey: "File Not Found",
                        level: .notification
                    )
                    return
                }
                
                // Verify if it is an executable file (verified through JavaManager)
                if JavaManager.shared.canJavaRun(at: url.path) {
                    javaPath = url.path
                    syncSelectedDetectedJavaPath()
                    autoSave()
                    Logger.shared.info("Java path has been set to: \(url.path)")
                } else {
                    error = GlobalError.validation(
                        i18nKey: "The selected file is not a valid Java executable",
                        level: .popup
                    )
                }
            }
            
        case .failure(let error):
            Logger.shared.error("Java path selection failed: \(error.localizedDescription)")
            
            let globalError = GlobalError.fileSystem(
                i18nKey: "Java Path Selection Failed",
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
    
    var displayName: LocalizedStringKey {
        switch self {
        case .g1gc: "G1GC (Balanced)"
        case .zgc: "ZGC (Ultra-low pause)"
        case .shenandoah: "Shenandoah (Low pause)"
        case .parallel: "ParallelGC (Throughput-first)"
        case .serial: "SerialGC (Small heaps)"
        }
    }
    
    var description: LocalizedStringKey {
        switch self {
        case .g1gc: "G1 garbage collector, balancing performance and latency, suitable for most scenarios"
        case .zgc: "ZGC garbage collector, extremely low latency, suitable for scenarios with extremely high response time requirements"
        case .shenandoah: "Shenandoah garbage collector, low pause time, suitable for scenarios requiring stable performance"
        case .parallel: "Parallel garbage collector, high throughput, suitable for background processing tasks"
        case .serial: "Serial garbage collector, single-threaded, suitable for small memory applications"
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
