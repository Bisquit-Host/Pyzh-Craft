import SwiftUI

// MARK: - Keychain stores constants
private let aiSettingsAccount = "aiSettings"
private let aiApiKeyKeychainKey = "apiKey"

/// AI provider enumeration
enum AIProvider: String, CaseIterable, Identifiable {
    case openai,
         ollama
//    gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai:
            "OpenAI"
        case .ollama:
            "Ollama"
//        case .gemini:
//            "Google Gemini"
        }
    }

    var baseURL: String {
        switch self {
        case .openai:
            "https://api.openai.com"
        case .ollama:
            "http://localhost:11434"
//        case .gemini:
//            "https://generativelanguage.googleapis.com"
        }
    }

    /// API format type
    var apiFormat: APIFormat {
        switch self {
        case .openai:
            .openAI
        case .ollama:
            .ollama
//        case .gemini:
//            .gemini
        }
    }

    /// API path
    var apiPath: String {
        switch self {
        case .openai:
            "/v1/chat/completions"
        case .ollama:
            "/api/chat"
//        case .gemini:
//            "/v1/models/\(defaultModel):streamGenerateContent"
        }
    }
}

/// API format enum
enum APIFormat {
    case openAI,  // OpenAI format (compatible with DeepSeek, etc.)
         ollama
//    case gemini
}

/// AI Settings Manager
class AISettingsManager: ObservableObject {
    static let shared = AISettingsManager()

    @AppStorage("aiProvider")
    private var _selectedProviderRawValue: String = "openai"

    var selectedProvider: AIProvider {
        get {
            AIProvider(rawValue: _selectedProviderRawValue) ?? .openai
        } set {
            _selectedProviderRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    private var _cachedApiKey: String?

    /// AI API Key (secure storage using Keychain, with memory cache)
    var apiKey: String {
        get {
            // If the cache already exists, return directly
            if let cached = _cachedApiKey {
                return cached
            }

            // Read from Keychain and cache
            if let data = KeychainManager.load(account: aiSettingsAccount, key: aiApiKeyKeychainKey),
               let key = String(data: data, encoding: .utf8) {
                _cachedApiKey = key
                return key
            }

            // There is no data in the Keychain and the empty string is cached
            _cachedApiKey = ""
            return ""
        } set {
            // Update cache
            _cachedApiKey = newValue.isEmpty ? "" : newValue

            // Save to Keychain
            if newValue.isEmpty {
                // If empty, deletes the item in Keychain
                _ = KeychainManager.delete(account: aiSettingsAccount, key: aiApiKeyKeychainKey)
            } else {
                // Save to Keychain
                if let data = newValue.data(using: .utf8) {
                    _ = KeychainManager.save(data: data, account: aiSettingsAccount, key: aiApiKeyKeychainKey)
                }
            }
            objectWillChange.send()
        }
    }

    @AppStorage("aiOllamaBaseURL")
    var ollamaBaseURL: String = "http://localhost:11434" {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("aiOpenAIBaseURL")
    var openAIBaseURL: String = "" {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("aiModelOverride")
    var modelOverride: String = "" {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("aiAvatarURL")
    var aiAvatarURL: String = "https://mcskins.top/assets/snippets/download/skin.php?n=7050" {
        didSet {
            objectWillChange.send()
        }
    }

    /// Get the API URL of the current provider (excluding Gemini as Gemini requires special handling)
    func getAPIURL() -> String {
        if selectedProvider == .ollama {
            let url = ollamaBaseURL.isEmpty ? selectedProvider.baseURL : ollamaBaseURL
            return url + selectedProvider.apiPath
        } else if selectedProvider.apiFormat == .openAI {
            // OpenAI format supports custom URLs (can be used with compatible services such as DeepSeek)
            let url = openAIBaseURL.isEmpty ? selectedProvider.baseURL : openAIBaseURL
            return url + selectedProvider.apiPath
        } else {
            return selectedProvider.baseURL + selectedProvider.apiPath
        }
    }

    /// Get the model name of the current provider (required)
    func getModel() -> String {
        modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private init() {
        _ = apiKey
    }
}
