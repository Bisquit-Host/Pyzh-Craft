import SwiftUI

/// Litematica projection details view
struct LitematicaDetailSheetView: View {
    // MARK: - Properties
    let filePath: URL
    let gameName: String
    @Environment(\.dismiss)
    private var dismiss

    @State private var metadata: LitematicMetadata?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false

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
        HStack {
            Text("Schematic Details")
                .font(.headline)
            Spacer()
            ShareLink(item: filePath) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
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
            Text("Unable to load schematic information")
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

    func metadataContentView(metadata: LitematicMetadata) -> some View {
        ScrollView {
            VStack {
                HStack {
                    // Basic information
                    infoSection(title: "Basic") {
                        infoRow(label: "Name", value: metadata.name)
                        infoRow(label: "Author", value: metadata.author.isEmpty ? String(localized: "Unknown") : metadata.author)
                        if !metadata.description.isEmpty {
                            infoRow(label: "Description", value: metadata.description, isMultiline: true)
                        }
                    }

                    // time information
                    infoSection(title: "Time") {
                        VStack(alignment: .leading, spacing: 12) {
                            infoRow(label: "Created", value: formatTimestamp(metadata.timeCreated))
                            infoRow(label: "Modified", value: formatTimestamp(metadata.timeModified))
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 20)

                // size information
                infoSection(title: "Size") {
                    VStack(alignment: .leading, spacing: 12) {
                        let hasSize = metadata.enclosingSize.x > 0 || metadata.enclosingSize.y > 0 || metadata.enclosingSize.z > 0
                        if hasSize {
                            infoRow(
                                label: "Enclosing Size",
                                value: "\(metadata.enclosingSize.x) × \(metadata.enclosingSize.y) × \(metadata.enclosingSize.z)"
                            )
                        } else {
                            infoRow(label: "Enclosing Size", value: String(localized: "Unknown"))
                        }

                        if metadata.totalVolume > 0 {
                            infoRow(label: "Total Volume", value: formatNumber(Int(metadata.totalVolume)))
                        } else {
                            infoRow(label: "Total Volume", value: String(localized: "Unknown"))
                        }

                        if metadata.totalBlocks > 0 {
                            infoRow(label: "Total Blocks", value: formatNumber(Int(metadata.totalBlocks)))
                        } else {
                            infoRow(label: "Total Blocks", value: String(localized: "Unknown"))
                        }

                        infoRow(label: "Regions", value: "\(metadata.regionCount)")
                    }
                }
            }
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
                Text(filePath.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle) // Optional: Omit the middle, long paths look better
            } icon: {
                Image(systemName: "square.stack.3d.up")
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
            Logger.shared.debug("开始加载投影详细信息: \(filePath.lastPathComponent)")
            let loadedMetadata = try await LitematicaService.shared.loadFullMetadata(filePath: filePath)
            
            await MainActor.run {
                if let metadata = loadedMetadata {
                    Logger.shared.debug("成功加载投影元数据: \(metadata.name)")
                    self.metadata = metadata
                } else {
                    Logger.shared.warning("投影元数据为nil: \(filePath.lastPathComponent)")
                    self.errorMessage = String(localized: "Unable to parse schematic metadata. The file may be corrupted or in an unsupported format.")
                }
                
                self.isLoading = false
            }
        } catch {
            Logger.shared.error("加载投影详细信息失败: \(error.localizedDescription)")
            
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = String(format: String(localized: "Failed to load schematic information: \(error.localizedDescription)"))
                self.showError = true
            }
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatTimestamp(_ timestamp: Int64) -> String {
        guard timestamp > 0 else {
            return String(localized: "Unknown")
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - Preview Helper
struct MetadataContentViewPreview: View {
    let metadata: LitematicMetadata

    var body: some View {
        let sheetView = LitematicaDetailSheetView(filePath: URL(fileURLWithPath: "/tmp/test.litematic"), gameName: "Test Game")
        return sheetView.metadataContentView(metadata: metadata)
    }
}
