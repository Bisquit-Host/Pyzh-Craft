import SwiftUI

struct ThemeWindowIcon: View {
    let theme: ThemeMode

    var body: some View {
        Image(iconName)
            .resizable()
            .frame(width: 60, height: 40)
            .cornerRadius(6)
    }

    private var iconName: String {
        let isSystem26 = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
        switch theme {
        case .system:
            return isSystem26 ? "AppearanceAuto_Normal_Normal" : "AppearanceAuto_Normal"
        case .light:
            return isSystem26 ? "AppearanceLight_Normal_Normal" : "AppearanceLight_Normal"
        case .dark:
            return isSystem26 ? "AppearanceDark_Normal_Normal" : "AppearanceDark_Normal"
        }
    }
}
