import SwiftUI

// MARK: - Log information area view
struct LogSectionView: View {
    // MARK: - Properties
    let logs: [LogInfo]
    let isLoading: Bool
    
    // MARK: - Body
    var body: some View {
        GenericSectionView(
            title: "Logs",
            items: logs,
            isLoading: isLoading,
            iconName: "doc.text.fill"
        ) { log in
            logChip(for: log)
        }
    }
    
    // MARK: - Chip Builder
    private func logChip(for log: LogInfo) -> some View {
        FilterChip(
            title: log.name,
            action: {
                openLogInConsole(log: log)
            },
            iconName: log.isCrashLog ? "exclamationmark.triangle.fill" : "doc.text.fill",
            isLoading: false,
            customBackgroundColor: log.isCrashLog ? Color.red.opacity(0.1) : nil,
            customBorderColor: log.isCrashLog ? Color.red.opacity(0.3) : nil,
            maxTextWidth: 150,
            iconColor: log.isCrashLog ? .red : nil
        )
    }
    
    // MARK: - Actions
    /// Open the log file using the Console app
    private func openLogInConsole(log: LogInfo) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Console", log.path.path]
        
        do {
            try process.run()
        } catch {
            Logger.shared.error("Failed to open log file: \(error.localizedDescription)")
        }
    }
}
