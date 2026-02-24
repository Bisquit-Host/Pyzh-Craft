import SwiftUI

struct ProjectLink: View {
    let text: String
    let url: String

    var body: some View {
        if let url = URL(string: url) {
            FilterChip(title: text, isSelected: false) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
