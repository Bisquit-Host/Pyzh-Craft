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
    
    private var currentGame: GameVersionInfo? {
        guard let gameId = selectedGameManager.selectedGameId else { return nil }
        return gameRepository.getGame(by: gameId)
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
    
    private let gcFlagMap: [(String, GarbageCollector)] = [
        ("-XX:+UseG1GC", .g1gc),
        ("-XX:+UseZGC", .zgc),
        ("-XX:+UseShenandoahGC", .shenandoah),
        ("-XX:+UseParallelGC", .parallel),
        ("-XX:+UseSerialGC", .serial),
    ]
    
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
    }
    
    private func parseExistingJvmArguments(_ arguments: String) {
        let args = arguments.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        if let (_, gc) = gcFlagMap.first(where: { args.contains($0.0) }), gc.isSupported(by: currentJavaVersion) {
            selectedGarbageCollector = gc
        } else {
            selectedGarbageCollector = availableGarbageCollectors.first ?? .g1gc
        }
        
        let managedArgs = Set(defaultManagedArguments(for: selectedGarbageCollector) + gcFlagMap.map(\.0))
        let extras = args.filter { !managedArgs.contains($0) }
        additionalJvmFlags = extras.joined(separator: " ")
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
