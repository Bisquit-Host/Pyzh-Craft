import SwiftUI

public struct GameSettingsView: View {
    @StateObject private var cacheManager = CacheManager()
    
    @StateObject private var gameSettings = GameSettingsManager.shared
    
    // memory range
    @State private var globalMemoryRange: ClosedRange<Double> = 512...4096
    
    /// Compute cached information securely
    private func calculateCacheInfoSafely() {
        cacheManager.calculateMetaCacheInfo()
    }
    
    public var body: some View {
        Form {
            LabeledContent("Default API Source") {
                Picker("", selection: $gameSettings.defaultAPISource) {
                    ForEach(DataSource.allCases, id: \.self) {
                        Text($0.localizedNameKey)
                            .tag($0)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .labeledContentStyle(.custom(alignment: .firstTextBaseline)).padding(.bottom, 10)
            
            LabeledContent("Game Versions") {
                HStack {
                    Toggle("", isOn: $gameSettings.includeSnapshotsForGameVersions)
                        .labelsHidden()
                    
                    Text("Include Snapshot Versions")
                        .font(.callout)
                        .foregroundColor(.primary)
                }
            }
            .labeledContentStyle(.custom)
            .padding(.bottom, 10)
            
            LabeledContent("AI Crash Analysis") {
                HStack {
                    Toggle("", isOn: $gameSettings.enableAICrashAnalysis)
                        .labelsHidden()
                    
                    Text("This option controls whether to enable AI analysis when the game crashes")
                        .font(.callout)
                        .foregroundColor(.primary)
                }
            }
            .labeledContentStyle(.custom)
            .padding(.bottom, 10)
            
            LabeledContent {
                HStack {
                    MiniRangeSlider(
                        range: $globalMemoryRange,
                        bounds:
                            512...Double(gameSettings.maximumMemoryAllocation)
                    )
                    .frame(width: 200)
                    .controlSize(.mini)
                    .onChange(of: globalMemoryRange) { _, newValue in
                        gameSettings.globalXms = Int(newValue.lowerBound)
                        gameSettings.globalXmx = Int(newValue.upperBound)
                    }
                    .onAppear {
                        globalMemoryRange =
                        Double(
                            gameSettings.globalXms
                        )...Double(gameSettings.globalXmx)
                    }
                    
                    Text("\(Int(globalMemoryRange.lowerBound)) MB-\(Int(globalMemoryRange.upperBound)) MB")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    InfoIconWithPopover(
                        text: "Set the minimum and maximum memory allocation for Minecraft. The minimum value (Xms) is the initial memory allocated when the game starts, and the maximum value (Xmx) is the maximum memory the game can use."
                    )
                }
            } label: {
                Text("Global Memory Allocation")
            }
            .labeledContentStyle(.custom).padding(.bottom, 10)
            
            LabeledContent("Game Resources") {
                HStack {
                    Label(
                        "\(cacheManager.cacheInfo.fileCount)",
                        systemImage: "text.document"
                    )
                    .font(.callout)
                    
                    Divider().frame(height: 16)
                    
                    Label(
                        cacheManager.cacheInfo.formattedSize,
                        systemImage: "externaldrive"
                    )
                    .font(.callout)
                }
                .foregroundStyle(.primary)
            }
            .labeledContentStyle(.custom)
        }
        .onAppear {
            calculateCacheInfoSafely()
        }
    }
}

#Preview {
    GameSettingsView()
}
