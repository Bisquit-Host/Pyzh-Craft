import SwiftUI

// Path segment display control (Finder style icon)
struct PathBreadcrumbView: View {
    let path: String
    let maxVisible: Int = 3  // Maximum number of paragraphs to display (including first and last paragraphs)

    var body: some View {
        let components = path.split(separator: "/").map(String.init)
        let paths: [String] = {
            var result: [String] = []
            var current = path.hasPrefix("/") ? "/" : ""
            for comp in components {
                let separator = current == "/" ? "" : "/"
                current = "\(current)\(separator)\(comp)"
                result.append(current)
            }
            return result
        }()

        let count = components.count
        let showEllipsis = count > maxVisible
        let headCount = showEllipsis ? 1 : max(0, count - maxVisible)
        let tailCount = showEllipsis ? maxVisible - 1 : count
        let startTail = max(count - tailCount, headCount)

        func segmentView(idx: Int) -> some View {
            let icon: NSImage = {
                guard FileManager.default.fileExists(atPath: paths[idx]) else {
                    if #available(macOS 12, *) {
                        return NSWorkspace.shared.icon(for: .folder)
                    } else {
                        return NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(0))
                    }
                }
                return NSWorkspace.shared.icon(forFile: paths[idx])
            }()
            return HStack(spacing: 2) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .cornerRadius(3)
                Text(components[idx])
                    .font(.body)
            }
        }

        return HStack(spacing: 0) {
            // beginning
            ForEach(0..<headCount, id: \.self) { idx in
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                }

                segmentView(idx: idx)
            }
            // Ellipsis
            if showEllipsis {
                if headCount > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                }

                Text("…")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            // ending
            ForEach(startTail..<count, id: \.self) { idx in
                if idx > headCount || (showEllipsis && idx == startTail) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                }
                if idx == count - 1 {
                    segmentView(idx: idx)
                } else {
                    segmentView(idx: idx)
                }
            }
        }
    }
}
