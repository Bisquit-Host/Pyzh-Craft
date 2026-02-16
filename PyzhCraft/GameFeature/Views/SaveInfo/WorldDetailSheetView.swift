import SwiftUI

private enum WorldDetailLoadError: Error {
    case levelDatNotFound, invalidStructure
}

/// World details view (read level.dat)
struct WorldDetailSheetView: View {
    // MARK: - Properties
    let world: WorldInfo
    let gameName: String
    @Environment(\.dismiss)
    private var dismiss

    @State private var metadata: WorldDetailMetadata?
    @State private var rawDataTag: [String: Any]? // Original Data tag, display as much data as possible
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showRawData = false // Control whether raw data is displayed

    // MARK: - Body
    var body: some View {
        CommonSheetView(
            header: { headerView },
            body: { bodyView },
            footer: { footerView }
        )
        .frame(minWidth: 500, minHeight: 400)
        .task {
            await loadMetadata()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        Text(world.name)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Body View
    private var bodyView: some View {
        Group {
            if isLoading {
                loadingView
            } else if let metadata = metadata {
                metadataContentView(metadata: metadata)
            } else {
                errorView
            }
        }
    }

    private var loadingView: some View {
        VStack {
            ProgressView().controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Failed to load world information")
                .font(.headline)
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func metadataContentView(metadata: WorldDetailMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 24) {
                    // Basic information
                    infoSection(title: "Basic Information") {
                        infoRow(label: "World Name", value: metadata.levelName)
                        infoRow(label: "Save Folder", value: metadata.folderName)
                        if let versionName = metadata.versionName {
                            infoRow(label: "Game Version", value: versionName)
                        }
                        if let versionId = metadata.versionId {
                            infoRow(label: "Version ID", value: "\(versionId)")
                        }
                        if let dataVersion = metadata.dataVersion {
                            infoRow(label: "Data Version", value: "\(dataVersion)")
                        }
                    }

                    // game settings
                    infoSection(title: "Game Settings") {
                        infoRow(label: "Game Mode", value: metadata.gameMode)
                        infoRow(label: "Difficulty", value: metadata.difficulty)
                        infoRow(label: "Hardcore Mode", value: metadata.hardcore ? String(localized: "Yes") : String(localized: "No"))
                        infoRow(label: "Allow Cheats", value: metadata.cheats ? String(localized: "Yes") : String(localized: "No"))
                        if let seed = metadata.seed {
                            infoRow(label: "World Seed", value: "\(seed)")
                        }
                    }
                }

                // Other information
                infoSection(title: "Other Information") {
                    if let lastPlayed = metadata.lastPlayed {
                        infoRow(label: "Last Played", value: formatDate(lastPlayed))
                    }
                    if let spawn = metadata.spawn {
                        infoRow(label: "Spawn Point", value: spawn)
                    }
                    if let time = metadata.time {
                        infoRow(label: "Time", value: "\(time)")
                    }
                    if let dayTime = metadata.dayTime {
                        infoRow(label: "DayTime", value: "\(dayTime)")
                    }
                    if let weather = metadata.weather {
                        infoRow(label: "Weather", value: weather)
                    }
                    if let border = metadata.worldBorder {
                        infoRow(label: "World Border", value: border, isMultiline: true)
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    Text("World Path" + ":")
                        .font(.headline)
                    
                    Button {
                        // Open file location in Finder
                        NSWorkspace.shared.selectFile(metadata.path.path, inFileViewerRootedAtPath: "")
                    } label: {
                        PathBreadcrumbView(path: metadata.path.path)
                            .frame(maxWidth: .infinity, alignment: .leading).font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Raw data toggle button
                if let raw = rawDataTag {
                    let displayedKeys: Set<String> = [
                        "LevelName", "Version", "DataVersion",
                        "GameType", "Difficulty", "hardcore", "allowCommands", "GameRules",
                        "LastPlayed", "RandomSeed", "SpawnX", "SpawnY", "SpawnZ",
                        "Time", "DayTime", "raining", "thundering", "WorldBorder",
                    ]

                    let filteredRaw = raw.filter { !displayedKeys.contains($0.key) }

                    if !filteredRaw.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation {
                                    showRawData.toggle()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: showRawData ? "chevron.down" : "chevron.right")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Show Detailed Information")
                                        .font(.headline)
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            if showRawData {
                                NBTStructureView(data: filteredRaw)
//                                infoSection(title: "Detailed Information") {
//
//                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func infoSection<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.bottom, 10)
            content()
        }
    }

    private func infoRow(label: LocalizedStringKey, value: String, isMultiline: Bool = false) -> some View {
        HStack(alignment: isMultiline ? .top : .center, spacing: 12) {
            HStack(spacing: 0) {
                Text(label)
                Text(":")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            if isMultiline {
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer View
    private var footerView: some View {
        HStack {
            Label {
                Text(gameName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "gamecontroller")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: 300, alignment: .leading)

            Spacer()

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Helper Methods
    private func loadMetadata() async {
        isLoading = true
        errorMessage = nil

        do {
            let levelDatPath = world.path.appendingPathComponent("level.dat")
            let worldGenSettingsPath = world.path
                .appendingPathComponent("data", isDirectory: true)
                .appendingPathComponent("minecraft", isDirectory: true)
                .appendingPathComponent("world_gen_settings.dat")
            let pathForBackground = levelDatPath

        let (dataTag, seedOverride): ([String: Any], Int64?) = try await Task.detached(priority: .userInitiated) {
                guard FileManager.default.fileExists(atPath: pathForBackground.path) else {
                    throw WorldDetailLoadError.levelDatNotFound
                }
                let data = try Data(contentsOf: pathForBackground)
                let parser = NBTParser(data: data)
                let nbtData = try parser.parse()
                guard let tag = nbtData["Data"] as? [String: Any] else {
                    throw WorldDetailLoadError.invalidStructure
                }

                // 26+ new version archive: seed split to data/minecraft/world_gen_settings.dat
                var seed: Int64?
                if FileManager.default.fileExists(atPath: worldGenSettingsPath.path) {
                    do {
                        let wgsData = try Data(contentsOf: worldGenSettingsPath)
                        let wgsParser = NBTParser(data: wgsData)
                        let wgsNBT = try wgsParser.parse()
                        if let dataTag = wgsNBT["data"] as? [String: Any],
                           let s = WorldNBTMapper.readInt64(dataTag["seed"]) {
                            seed = s
                        }
                    } catch {
                        // Reading failure does not affect the display of level.dat
                    }
                }

                return (tag, seed)
        }.value

            let metadata = parseWorldDetail(from: dataTag, folderName: world.name, path: world.path, seedOverride: seedOverride)
            await MainActor.run {
                self.rawDataTag = dataTag
                self.metadata = metadata
                self.isLoading = false
            }
        } catch WorldDetailLoadError.levelDatNotFound {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = String(localized: "level.dat file not found")
                self.showError = true
            }
        } catch WorldDetailLoadError.invalidStructure {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = String(localized: "level.dat structure is invalid (missing Data tag)")
                self.showError = true
            }
        } catch {
            Logger.shared.error("加载世界详细信息失败: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = String(format: String(localized: "Failed to load world information: \(error.localizedDescription)"))
                self.showError = true
            }
        }
    }

    private func parseWorldDetail(from dataTag: [String: Any], folderName: String, path: URL, seedOverride: Int64?) -> WorldDetailMetadata {
        let levelName = (dataTag["LevelName"] as? String) ?? folderName

        // LastPlayed is a millisecond timestamp (Long), compatible with Int/Int64 and other types
        var lastPlayedDate: Date?
        if let ts = WorldNBTMapper.readInt64(dataTag["LastPlayed"]) {
            lastPlayedDate = Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
        }

        // GameType: 0 Survival, 1 Creation, 2 Adventure, 3 Spectator
        var gameMode = String(localized: "Unknown")
        if let gt = WorldNBTMapper.readInt64(dataTag["GameType"]) {
            gameMode = WorldNBTMapper.mapGameMode(Int(gt))
        }

        // Difficulty: The old version is a numerical value, the new version (26+) is usually the difficulty_settings.difficulty string
        var difficulty = String(localized: "Unknown")
        if let diff = WorldNBTMapper.readInt64(dataTag["Difficulty"]) {
            difficulty = WorldNBTMapper.mapDifficulty(Int(diff))
        } else if let ds = dataTag["difficulty_settings"] as? [String: Any],
                  let diffStr = ds["difficulty"] as? String {
            difficulty = WorldNBTMapper.mapDifficultyString(diffStr)
        }

        // The limit/cheating flag may be byte or bool in the new version, here it is unified as "non-0 means true"
        let hardcore: Bool = {
            if let ds = dataTag["difficulty_settings"] as? [String: Any] {
                return WorldNBTMapper.readBoolFlag(ds["hardcore"])
            }
            return WorldNBTMapper.readBoolFlag(dataTag["hardcore"])
        }()
        let cheats: Bool = WorldNBTMapper.readBoolFlag(dataTag["allowCommands"])

        var versionName: String?
        var versionId: Int?
        if let versionTag = dataTag["Version"] as? [String: Any] {
            versionName = versionTag["Name"] as? String
            if let id = versionTag["Id"] as? Int {
                versionId = id
            } else if let id32 = versionTag["Id"] as? Int32 {
                versionId = Int(id32)
            }
        }

        var dataVersion: Int?
        if let dv = dataTag["DataVersion"] as? Int {
            dataVersion = dv
        } else if let dv32 = dataTag["DataVersion"] as? Int32 {
            dataVersion = Int(dv32)
        }

        // Seed: 26+ first world_gen_settings.dat, followed by level.dat of RandomSeed / WorldGenSettings.seed
        var seed: Int64? = seedOverride
        if seed == nil {
            seed = WorldNBTMapper.readSeed(from: dataTag, worldPath: path)
        }

        var spawn: String?
        if let x = WorldNBTMapper.readInt64(dataTag["SpawnX"]),
           let y = WorldNBTMapper.readInt64(dataTag["SpawnY"]),
           let z = WorldNBTMapper.readInt64(dataTag["SpawnZ"]) {
            spawn = "\(x), \(y), \(z)"
        } else if let spawnTag = dataTag["spawn"] as? [String: Any],
                  let pos = spawnTag["pos"] as? [Any],
                  pos.count >= 3,
                  let x = WorldNBTMapper.readInt64(pos[0]),
                  let y = WorldNBTMapper.readInt64(pos[1]),
                  let z = WorldNBTMapper.readInt64(pos[2]) {
            // 26+ new version archive: spawn.pos = [x, y, z], and may also include dimension/yaw/pitch
            if let dim = spawnTag["dimension"] as? String, !dim.isEmpty {
                spawn = "\(x), \(y), \(z) (\(dim))"
            } else {
                spawn = "\(x), \(y), \(z)"
            }
        }

        let time = WorldNBTMapper.readInt64(dataTag["Time"])
        let dayTime = WorldNBTMapper.readInt64(dataTag["DayTime"])

        var weather: String?
        if let rainingFlag = dataTag["raining"] {
            let raining = WorldNBTMapper.readBoolFlag(rainingFlag)
            weather = raining ? String(localized: "Rain") : String(localized: "Clear")
        }
        if let thunderingFlag = dataTag["thundering"] {
            let thundering = WorldNBTMapper.readBoolFlag(thunderingFlag)
            let t = thundering ? String(localized: "Thunderstorm") : nil
            if let t {
                weather = weather.map { "\($0), \(t)" } ?? t
            }
        }

        var worldBorder: String?
        if let wb = dataTag["WorldBorder"] as? [String: Any] {
            worldBorder = flattenNBTDictionary(wb, prefix: "").map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
        }

        var gameRules: [String]?
        if let gr = dataTag["GameRules"] as? [String: Any] {
            gameRules = flattenNBTDictionary(gr, prefix: "").map { "\($0.key)=\($0.value)" }.sorted()
        }

        return WorldDetailMetadata(
            levelName: levelName,
            folderName: folderName,
            path: path,
            lastPlayed: lastPlayedDate,
            gameMode: gameMode,
            difficulty: difficulty,
            hardcore: hardcore,
            cheats: cheats,
            versionName: versionName,
            versionId: versionId,
            dataVersion: dataVersion,
            seed: seed,
            spawn: spawn,
            time: time,
            dayTime: dayTime,
            weather: weather,
            worldBorder: worldBorder,
            gameRules: gameRules
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    private func flattenNBTDictionary(_ dict: [String: Any], prefix: String = "") -> [String: String] {
        var result: [String: String] = [:]
        for (k, v) in dict {
            let key = prefix.isEmpty ? k : "\(prefix).\(k)"
            if let sub = v as? [String: Any] {
                let nested = flattenNBTDictionary(sub, prefix: key)
                for (nk, nv) in nested { result[nk] = nv }
            } else if let arr = v as? [Any] {
                result[key] = arr.map { stringifyNBTValue($0) }.joined(separator: ", ")
            } else {
                result[key] = stringifyNBTValue(v)
            }
        }
        return result
    }

    private func stringifyNBTValue(_ value: Any) -> String {
        if let v = value as? String { return v }
        if let v = value as? Bool { return v ? "true" : "false" }
        if let v = value as? Int8 { return "\(v)" }
        if let v = value as? Int16 { return "\(v)" }
        if let v = value as? Int32 { return "\(v)" }
        if let v = value as? Int64 { return "\(v)" }
        if let v = value as? Int { return "\(v)" }
        if let v = value as? Double { return "\(v)" }
        if let v = value as? Float { return "\(v)" }
        if let v = value as? Data { return "Data(\(v.count) bytes)" }
        if let v = value as? URL { return v.path }
        return String(describing: value)
    }
}

// MARK: - NBT structural view (maintains original nested structure)
struct NBTStructureView: View {
    let data: [String: Any]
    @State private var expandedKeys: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(data.keys.sorted()), id: \.self) { key in
                if let value = data[key] {
                    NBTEntryView(
                        key: key,
                        value: value,
                        expandedKeys: $expandedKeys,
                        indentLevel: 0,
                        fullKey: key
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct NBTEntryView: View {
    let key: String
    let value: Any
    @Binding var expandedKeys: Set<String>
    let indentLevel: Int
    let fullKey: String
    private let indentWidth: CGFloat = 20
    @State private var isHovered = false

    init(key: String, value: Any, expandedKeys: Binding<Set<String>>, indentLevel: Int, fullKey: String? = nil) {
        self.key = key
        self.value = value
        self._expandedKeys = expandedKeys
        self.indentLevel = indentLevel
        self.fullKey = fullKey ?? key
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let dict = value as? [String: Any] {
                // dictionary type
                NBTDisclosureButton(
                    isExpanded: expandedKeys.contains(fullKey),
                    label: key,
                    suffix: "{\(dict.count)}",
                    indentLevel: indentLevel,
                    isHovered: $isHovered
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedKeys.contains(fullKey) {
                            expandedKeys.remove(fullKey)
                        } else {
                            expandedKeys.insert(fullKey)
                        }
                    }
                }

                if expandedKeys.contains(fullKey) {
                    ForEach(Array(dict.keys.sorted()), id: \.self) { subKey in
                        if let subValue = dict[subKey] {
                            Self(
                                key: subKey,
                                value: subValue,
                                expandedKeys: $expandedKeys,
                                indentLevel: indentLevel + 1,
                                fullKey: "\(fullKey).\(subKey)"
                            )
                        }
                    }
                }
            } else if let array = value as? [Any] {
                // array type
                NBTDisclosureButton(
                    isExpanded: expandedKeys.contains(fullKey),
                    label: key,
                    suffix: "[\(array.count)]",
                    indentLevel: indentLevel,
                    isHovered: $isHovered
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedKeys.contains(fullKey) {
                            expandedKeys.remove(fullKey)
                        } else {
                            expandedKeys.insert(fullKey)
                        }
                    }
                }

                if expandedKeys.contains(fullKey) {
                    ForEach(Array(array.enumerated()), id: \.offset) { index, item in
                        let arrayItemKey = "\(fullKey)[\(index)]"
                        if let itemDict = item as? [String: Any] {
                            Self(
                                key: "[\(index)]",
                                value: itemDict,
                                expandedKeys: $expandedKeys,
                                indentLevel: indentLevel + 1,
                                fullKey: arrayItemKey
                            )
                        } else {
                            NBTValueRow(
                                label: "[\(index)]",
                                value: formatNBTValue(item),
                                indentLevel: indentLevel + 1
                            )
                        }
                    }
                }
            } else {
                // basic type
                NBTValueRow(
                    label: key,
                    value: formatNBTValue(value),
                    indentLevel: indentLevel
                )
            }
        }
    }

    private func formatNBTValue(_ value: Any) -> String {
        if let v = value as? String { return "\"\(v)\"" }
        if let v = value as? Bool { return v ? "true" : "false" }
        if let v = value as? Int8 { return "\(v)b" }
        if let v = value as? Int16 { return "\(v)s" }
        if let v = value as? Int32 { return "\(v)" }
        if let v = value as? Int64 { return "\(v)L" }
        if let v = value as? Int { return "\(v)" }
        if let v = value as? Double { return "\(v)d" }
        if let v = value as? Float { return "\(v)f" }
        if let v = value as? Data { return "Data(\(v.count) bytes)" }
        if let v = value as? URL { return v.path }
        return String(describing: value)
    }
}

// MARK: - macOS style components
struct NBTDisclosureButton: View {
    let isExpanded: Bool
    let label: String
    let suffix: String
    let indentLevel: Int
    @Binding var isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 14, alignment: .leading)
                    .contentShape(Rectangle())

                Text(label)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(suffix)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .padding(.leading, CGFloat(indentLevel) * 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct NBTValueRow: View {
    let label: String
    let value: String
    let indentLevel: Int
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label + ":")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(indentLevel) * 20 + 14)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
