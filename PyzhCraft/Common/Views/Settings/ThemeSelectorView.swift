import SwiftUI

struct ThemeSelectorView: View {
    @Binding var selectedTheme: ThemeMode

    var body: some View {
        HStack(spacing: 16) {
            ForEach(ThemeMode.allCases, id: \.self) { theme in
                ThemeOptionView(theme: theme, isSelected: selectedTheme == theme) {
                    selectedTheme = theme
                }
            }
        }
    }
}
