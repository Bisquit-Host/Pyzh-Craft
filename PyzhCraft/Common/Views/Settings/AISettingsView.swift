import SwiftUI

public struct AISettingsView: View {
    @StateObject private var aiSettings = AISettingsManager.shared
    @State private var showApiKey = false
    public var body: some View {
        Form {
            LabeledContent("API Type") {
                Picker("", selection: $aiSettings.selectedProvider) {
                    ForEach(AIProvider.allCases) {
                        Text($0.displayName)
                            .tag($0)
                    }
                }
                .labelsHidden()
                
                .if(ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26) { view in
                    view.fixedSize()
                }
            }
            .labeledContentStyle(.custom)
            
            LabeledContent("API Key") {
                HStack {
                    Group {
                        if showApiKey {
                            TextField("", text: $aiSettings.apiKey)
                                .textFieldStyle(.roundedBorder).labelsHidden()
                        } else {
                            SecureField("", text: $aiSettings.apiKey)
                                .textFieldStyle(.roundedBorder).labelsHidden()
                        }
                    }
                    .frame(width: 300)
                    .focusable(false)
                    
                    Button {
                        showApiKey.toggle()
                    } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .applyReplaceTransition()
                    
                    InfoIconWithPopover(text: "API key is stored locally only and will not be shared")
                }
            }
            .labeledContentStyle(.custom)
            
            // Ollama address settings (only shown when Ollama is selected)
            if aiSettings.selectedProvider == .ollama {
                LabeledContent("Ollama URL") {
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
                LabeledContent("API URL") {
                    HStack {
                        TextField(aiSettings.selectedProvider.baseURL, text: $aiSettings.openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 180)
                            .fixedSize()
                            .focusable(false)
                        
                        InfoIconWithPopover(text: "Custom API URL (leave empty to use default address)")
                    }
                }
                .labeledContentStyle(.custom)
            }
            
            // Model settings (required)
            LabeledContent("Model Name") {
                HStack {
                    TextField("e.g.: gpt-4o, deepseek-chat", text: $aiSettings.modelOverride)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 180)
                        .fixedSize()
                        .focusable(false)
                    
                    InfoIconWithPopover(text: "The model name to use (required)")
                }
            }
            .labeledContentStyle(.custom)
            
            // AI avatar settings
            LabeledContent("AI Avatar") {
                VStack(alignment: .leading, spacing: 12) {
                    // Avatar preview
                    MinecraftSkinUtils(
                        type: .url,
                        src: aiSettings.aiAvatarURL,
                        size: 42
                    )
                    
                    // URL input box
                    HStack {
                        TextField("Enter MC skin URL (64x64)", text: $aiSettings.aiAvatarURL)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(maxWidth: 300)
                            .fixedSize()
                            .focusable(false)
                        
                        InfoIconWithPopover(text: "MC skin direct link, must be 64x64 pixels")
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
