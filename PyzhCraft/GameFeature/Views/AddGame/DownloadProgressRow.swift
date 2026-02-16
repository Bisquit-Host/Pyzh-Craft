import SwiftUI

struct DownloadProgressRow: View {
    let title: LocalizedStringKey
    let progress: Double
    let currentFile: String
    let completed: Int
    let total: Int
    let version: String?
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .font(.headline)
                
                if let version = version, !version.isEmpty {
                    Text(version)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("Progress: \(Int32(progress * 100))%")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress).animation(
                .easeOut(duration: 0.5),
                value: progress
            )
            
            HStack {
                Text("Current Step: \(currentFile)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text("Files: \(Int32(completed))/\(Int32(total))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
