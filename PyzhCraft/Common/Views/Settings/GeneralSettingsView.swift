import SwiftUI

public struct GeneralSettingsView: View {
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @EnvironmentObject private var gameRepository: GameRepository
    @EnvironmentObject private var sparkleUpdateService: SparkleUpdateService
    @State private var showDirectoryPicker = false
    @State private var showingRestartAlert = false
    @State private var previousLanguage = ""
    @State private var isCancellingLanguageChange = false
    @State private var selectedLanguage = LanguageManager.shared.selectedLanguage
    @State private var error: GlobalError?

    public init() {}

    public var body: some View {
        Form {
            LabeledContent("Select Language") {
                Picker("", selection: $selectedLanguage) {
                    ForEach(LanguageManager.shared.languages, id: \.1) { name, code in
                        Text(name).tag(code)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: selectedLanguage) { _, newValue in
                    if newValue != LanguageManager.shared.selectedLanguage {
                        showingRestartAlert = true
                    }
                }
                .confirmationDialog(
                    "Restart Required",
                    isPresented: $showingRestartAlert,
                    titleVisibility: .visible
                ) {
                    Button("Restart Application", role: .destructive) {
                        sparkleUpdateService.updateSparkleLanguage(selectedLanguage)
                        LanguageManager.shared.selectedLanguage = selectedLanguage
                        restartAppSafely()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel", role: .cancel) {
                        selectedLanguage = LanguageManager.shared.selectedLanguage
                    }
                } message: {
                    Text("Changing language requires restarting the application to take effect")
                }
            }.labeledContentStyle(.custom).padding(.bottom, 10)

            LabeledContent("Appearance") {
                ThemeSelectorView(selectedTheme: $themeManager.themeMode)
                    .fixedSize()
            }.labeledContentStyle(.custom)

            LabeledContent("Interface style") {
                Picker("", selection: $generalSettings.interfaceLayoutStyle) {
                    ForEach(InterfaceLayoutStyle.allCases, id: \.self) {
                        Text($0.localizedName)
                            .tag($0)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }.labeledContentStyle(.custom).padding(.bottom, 10)

            LabeledContent("Working Directory") {
                DirectorySettingRow(
                    title: "Working Directory",
                    path: generalSettings.launcherWorkingDirectory.isEmpty ? AppPaths.launcherSupportDirectory.path : generalSettings.launcherWorkingDirectory,
                    description: String(localized: "This path setting only affects the storage location of game saves, mods, shaders, and other resources."),
                    onChoose: { showDirectoryPicker = true },
                    onReset: {
                        resetWorkingDirectorySafely()
                    }
                ).fixedSize()
                    .fileImporter(isPresented: $showDirectoryPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                        handleDirectoryImport(result)
                    }
            }.labeledContentStyle(.custom(alignment: .firstTextBaseline))

            LabeledContent("Concurrent Downloads") {
                HStack {
                    Slider(
                        value: Binding(
                            get: {
                                Double(generalSettings.concurrentDownloads)
                            },
                            set: {
                                generalSettings.concurrentDownloads = Int(
                                    $0
                                )
                            }
                        ),
                        in: 1...64
                    ).controlSize(.mini)
                        .animation(.easeOut(duration: 0.5), value: generalSettings.concurrentDownloads)
                    Text("\(generalSettings.concurrentDownloads)").font(
                        .subheadline
                    )
                    .foregroundColor(.secondary)
                    .fixedSize()
                }.frame(width: 200)
                    .gridColumnAlignment(.leading)
                    .labelsHidden()
            }.labeledContentStyle(.custom)
            LabeledContent("GitHub Proxy") {
                VStack(alignment: .leading) {
                    HStack {
                        Toggle(
                            "",
                            isOn: $generalSettings.enableGitHubProxy
                        )
                        .labelsHidden()
                        Text("Enable")
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                    HStack(spacing: 8) {
                        TextField("", text: $generalSettings.gitProxyURL)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .focusable(false)
                            .disabled(!generalSettings.enableGitHubProxy)

                        Button("Reset to Default") {
                            generalSettings.gitProxyURL = "https://gh-proxy.com"
                        }
                        .disabled(!generalSettings.enableGitHubProxy)

                        InfoIconWithPopover(text: "When enabled, adds a proxy prefix to requests for github.com and raw.githubusercontent.com.")
                    }
                }
            }.labeledContentStyle(.custom(alignment: .firstTextBaseline)).padding(.top, 10)
        }
        .globalErrorHandler()
        .alert(
            "Validation Error",
            isPresented: .constant(error != nil && error?.level == .popup)
        ) {
            Button("Close") {
                error = nil
            }
        } message: {
            if let error {
                Text(error.localizedDescription)
            }
        }
    }

    private func resetWorkingDirectorySafely() {
        do {
            guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.appName) else {
                throw GlobalError.configuration(
                    i18nKey: "App Support Directory Not Found",
                    level: .popup
                )
            }

            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

            generalSettings.launcherWorkingDirectory = supportDir.path

            Logger.shared.info("Working directory has been reset to: \(supportDir.path)")
        } catch {
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
            self.error = globalError
        }
    }

    private func handleDirectoryImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
                    guard resourceValues.isDirectory == true, resourceValues.isReadable == true else {
                        throw GlobalError.fileSystem(
                            i18nKey: "Invalid Directory Selected",
                            level: .notification
                        )
                    }

                    generalSettings.launcherWorkingDirectory = url.path

                    Logger.shared.info("The working directory has been set to: \(url.path)")
                } catch {
                    let globalError = GlobalError.from(error)
                    GlobalErrorHandler.shared.handle(globalError)
                    self.error = globalError
                }
            }
        case .failure(let error):
            Logger.shared.error("Directory selection failed: \(error.localizedDescription)")
            let globalError = GlobalError.fileSystem(
                i18nKey: "Directory Selection Failed",
                level: .notification
            )
            GlobalErrorHandler.shared.handle(globalError)
            self.error = globalError
        }
    }

    private func restartAppSafely() {
        do {
            try restartApp()
        } catch {
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
            self.error = globalError
        }
    }
}

private func restartApp() throws {
    guard let appURL = Bundle.main.bundleURL as URL? else {
        throw GlobalError.configuration(
            i18nKey: "App Executable Not Found",
            level: .popup
        )
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = [appURL.path]

    try task.run()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    GeneralSettingsView()
}
