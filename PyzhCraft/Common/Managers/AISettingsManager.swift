import SwiftUI

// MARK: - Keychain stores constants
private let aiSettingsAccount = "aiSettings"
private let aiApiKeyKeychainKey = "apiKey"

private struct OpenAIModelListResponse: Decodable {
    struct OpenAIModel: Decodable {
        let id: String
    }
    
    let data: [OpenAIModel]
}

private struct OllamaTagsResponse: Decodable {
    struct OllamaModel: Decodable {
        let name: String
    }
    
    let models: [OllamaModel]
}

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
    private var _selectedProviderRawValue = "openai"
    
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
    var ollamaBaseURL = "http://localhost:11434" {
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("aiOpenAIBaseURL")
    var openAIBaseURL = "" {
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("aiAvatarURL")
    var aiAvatarURL = "https://mcskins.top/assets/snippets/download/skin.php?n=7050" {
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
    
    /// Provider default model
    private func defaultModel(for provider: AIProvider) -> String {
        switch provider {
        case .openai:
            "gpt-4o-mini"
        case .ollama:
            "llama3.2"
        }
    }
    
    /// Models shown in chat picker when remote fetch is unavailable
    private func fallbackModels(for provider: AIProvider) -> [String] {
        switch provider {
        case .openai:
            ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "deepseek-chat"]
        case .ollama:
            ["llama3.2", "llama3.1", "qwen2.5", "mistral"]
        }
    }
    
    /// Effective default model shown in chat
    func getDefaultModel() -> String {
        defaultModel(for: selectedProvider)
    }
    
    /// Model options shown in chat picker
    func fetchModelOptions() async -> [String] {
        let fetchedModels = await fetchProviderModels()
        let baseModels = fetchedModels.isEmpty ? fallbackModels(for: selectedProvider) : fetchedModels
        
        return baseModels
    }
    
    /// Get model name with fallback order: chat override -> provider default
    func getModel(chatOverride: String = "") -> String {
        let chatModel = chatOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chatModel.isEmpty {
            return chatModel
        }

        return defaultModel(for: selectedProvider)
    }
    
    private func fetchProviderModels() async -> [String] {
        switch selectedProvider {
        case .openai:
            await fetchOpenAIModels()
        case .ollama:
            await fetchOllamaModels()
        }
    }
    
    private func fetchOpenAIModels() async -> [String] {
        let baseURL = openAIBaseURL.isEmpty ? selectedProvider.baseURL : openAIBaseURL
        guard let url = URL(string: baseURL + "/v1/models") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            
            let result = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
            return normalizeModels(result.data.map(\.id))
        } catch {
            Logger.shared.error("Failed to fetch OpenAI model list: \(error.localizedDescription)")
            return []
        }
    }
    
    private func fetchOllamaModels() async -> [String] {
        let baseURL = ollamaBaseURL.isEmpty ? selectedProvider.baseURL : ollamaBaseURL
        guard let url = URL(string: baseURL + "/api/tags") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            
            let result = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return normalizeModels(result.models.map(\.name))
        } catch {
            Logger.shared.error("Failed to fetch Ollama model list: \(error.localizedDescription)")
            return []
        }
    }
    
    private func normalizeModels(_ models: [String]) -> [String] {
        let cleanedModels = models
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        
        var uniqueModels: [String] = []
        for model in cleanedModels where !uniqueModels.contains(model) {
            uniqueModels.append(model)
        }
        
        return uniqueModels
    }
    
    private init() {
    }
}
