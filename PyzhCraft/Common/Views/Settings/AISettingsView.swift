import SwiftUI

public struct AISettingsView: View {
    @StateObject private var aiSettings = AISettingsManager.shared
    @State private var showApiKey = false
    public var body: some View {
        Form {
            LabeledContent("settings.ai.api_type.label".localized()) {
                Picker("", selection: $aiSettings.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .if(
                    ProcessInfo.processInfo.operatingSystemVersion.majorVersion
                        < 26
                ) { view in
                    view.fixedSize()
                }
            }
            .labeledContentStyle(.custom)

            LabeledContent("settings.ai.api_key.label".localized()) {
                HStack {
                    Group {
                        if showApiKey {
                            TextField("".localized(), text: $aiSettings.apiKey)
                                .textFieldStyle(.roundedBorder).labelsHidden()
                        } else {
                            SecureField("".localized(), text: $aiSettings.apiKey)
                                .textFieldStyle(.roundedBorder).labelsHidden()
                        }
                    }
                    .frame(width: 300)
                    .focusable(false)
                    Button(action: {
                        showApiKey.toggle()
                    }, label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                    })
                    .buttonStyle(.plain)
                    .applyReplaceTransition()
                    InfoIconWithPopover(text: "settings.ai.api_key.description".localized())
                }
            }
            .labeledContentStyle(.custom)

            // Ollama address settings (only shown when Ollama is selected)
            if aiSettings.selectedProvider == .ollama {
                LabeledContent("settings.ai.ollama.url.label".localized()) {
                    TextField("http://localhost:11434", text: $aiSettings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(maxWidth: 300)
                        .fixedSize()
                        .focusable(false)
                }
                .labeledContentStyle(.custom)
            }

            // Custom interface address settings in OpenAI format (can be used with compatible services such as DeepSeek)
            if aiSettings.selectedProvider.apiFormat == .openAI {
                LabeledContent("settings.ai.api_url.label".localized()) {
                    HStack {
                        TextField(aiSettings.selectedProvider.baseURL, text: $aiSettings.openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 180)
                            .fixedSize()
                            .focusable(false)
                        InfoIconWithPopover(text: "settings.ai.api_url.description".localized())
                    }
                }
                .labeledContentStyle(.custom)
            }

            // Model settings (required)
            LabeledContent("settings.ai.model.label".localized()) {
                HStack {
                    TextField("settings.ai.model.placeholder".localized(), text: $aiSettings.modelOverride)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 180)
                        .fixedSize()
                        .focusable(false)
                    InfoIconWithPopover(text: "settings.ai.model.description".localized())
                }
            }
            .labeledContentStyle(.custom)

            // AI avatar settings
            LabeledContent("settings.ai.avatar.label".localized()) {
                VStack(alignment: .leading, spacing: 12) {
                    // Avatar preview
                    MinecraftSkinUtils(
                        type: .url,
                        src: aiSettings.aiAvatarURL,
                        size: 42
                    )
                    // URL input box
                    HStack {
                        TextField("settings.ai.avatar.placeholder".localized(), text: $aiSettings.aiAvatarURL)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(maxWidth: 300)
                            .fixedSize()
                            .focusable(false)
                        InfoIconWithPopover(text: "settings.ai.avatar.description".localized())
                    }
                }
            }
            .labeledContentStyle(.custom(alignment: .lastTextBaseline))
        }
    }
}

#Preview {
    AISettingsView()
}
