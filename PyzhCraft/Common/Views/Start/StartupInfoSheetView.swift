import SwiftUI

/// Start information prompt Sheet view
struct StartupInfoSheetView: View {

    // MARK: - Properties
    @Environment(\.dismiss)
    private var dismiss

    let announcementData: AnnouncementData?

    // MARK: - Body
    var body: some View {
        CommonSheetView(
            header: {
                VStack(spacing: 12) {
                    // title
                    if let title = announcementData?.title {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
            },
            body: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // application icon
                        HStack {
                            Spacer()
                            if let appIcon = NSApplication.shared.applicationIconImage {
                                Image(nsImage: appIcon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 64, height: 64)
                            }
                            Spacer()
                        }
                        .padding(.bottom, 8)

                        // Main information content
                        if let announcementData = announcementData {
                            // Display announcement content obtained from API
                            Text(
                                String.localizedStringWithFormat(
                                    announcementData.content,
                                    Bundle.main.appName,
                                    Bundle.main.appName,
                                    Bundle.main.appName
                                )
                            )
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                            // Author information
                            if !announcementData.author.isEmpty {
                                Text(announcementData.author)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)  // Leave space for scrollbar
                }
            },
            footer: {
                HStack {
                    Spacer()

                    Button("startup.info.understand".localized()) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        )
        //        .frame(width: 600, height: 500)
        .onAppear {
            // Set window properties
            if let window = NSApplication.shared.windows.last {
                window.level = .floating
                window.center()
            }
        }
    }
}

// MARK: - Preview
#Preview {
    StartupInfoSheetView(announcementData: nil)
}
