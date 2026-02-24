import SwiftUI

struct ProcessingView: View {
    let downloadedBytes: Int64
    let totalBytes: Int64
    
    init(downloadedBytes: Int64 = 0, totalBytes: Int64 = 0) {
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
    }
    
    private var progress: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(downloadedBytes) / Double(totalBytes)))
    }
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Always show circular progress bar
                CircularProgressView(progress: progress)
                    .frame(width: 54, height: 54)
                
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            VStack(spacing: 8) {
                Text("Processing Modpack...")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Text("Downloading modpack files and parsing configuration")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding()
    }
}

// MARK: - Circular Progress View
struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            // background ring
            Circle()
                .stroke(
                    Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
            
            // progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
        }
    }
}
