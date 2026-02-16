import SwiftUI

@MainActor
class AIChatManager: ObservableObject {
    static let shared = AIChatManager()

    private let settings = AISettingsManager.shared
    private var urlSession: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Send message

    /// Send message
    func sendMessage(_ text: String, attachments: [MessageAttachmentType] = [], chatState: ChatState) async {
        guard !settings.apiKey.isEmpty else {
            let error = GlobalError.configuration(
                i18nKey: "OpenAI service not configured, please check API Key",
                level: .notification
            )
            Logger.shared.error("AI 服务未配置，请检查 API Key")
            await MainActor.run {
                chatState.isSending = false
                GlobalErrorHandler.shared.handle(error)
            }
            return
        }

        guard !settings.getModel().isEmpty else {
            let error = GlobalError.configuration(
                i18nKey: "AI model not configured, please fill in the model name in settings",
                level: .notification
            )
            Logger.shared.error("AI 模型未配置，请在设置中填写模型名称")
            await MainActor.run {
                chatState.isSending = false
                GlobalErrorHandler.shared.handle(error)
            }
            return
        }

        // Add user message
        let userMessage = ChatMessage(
            role: .user,
            content: text,
            attachments: attachments
        )
        await MainActor.run {
            chatState.addMessage(userMessage)

            // Add empty helper message for streaming updates
            let assistantMessage = ChatMessage(role: .assistant, content: "")
            chatState.addMessage(assistantMessage)
            chatState.isSending = true
        }

        // Build message history
        let historyMessages = chatState.messages.dropLast(2)
        var allMessages: [ChatMessage] = Array(historyMessages)
        allMessages.append(userMessage)

        do {
            switch settings.selectedProvider.apiFormat {
            case .openAI:
                try await sendOpenAIMessage(messages: allMessages, chatState: chatState)
            case .ollama:
                try await sendOllamaMessage(messages: allMessages, chatState: chatState)
//            case .gemini:
//                try await sendGeminiMessage(messages: allMessages, chatState: chatState)
            }
        } catch {
            Logger.shared.error("发送消息失败: \(error.localizedDescription)")
            await MainActor.run {
                chatState.isSending = false

                if let globalError = error as? GlobalError {
                    GlobalErrorHandler.shared.handle(globalError)
                    // Show error in message
                    if let lastIndex = chatState.messages.indices.last {
                        let userFriendlyMessage = globalError.localizedDescription
                        chatState.messages[lastIndex].content = userFriendlyMessage
                    }
                } else {
                    // Other errors are converted to GlobalError
                    let globalError = GlobalError(
                        type: .network,
                        i18nKey: "AI request failed",
                        level: .notification
                    )
                    GlobalErrorHandler.shared.handle(globalError)
                    // Show error in message
                    if let lastIndex = chatState.messages.indices.last {
                        let userFriendlyMessage = globalError.localizedDescription
                        chatState.messages[lastIndex].content = userFriendlyMessage
                    }
                }
            }
        }
    }

    // MARK: - OpenAI format (compatible with DeepSeek, etc.)

    private func sendOpenAIMessage(messages: [ChatMessage], chatState: ChatState) async throws {
        let apiURL = settings.getAPIURL()
        guard let url = URL(string: apiURL) else {
            throw GlobalError.network(
                i18nKey: "Invalid URL",
                level: .notification
            )
        }

        // Build request body
        let requestBody: [String: Any] = [
            "model": settings.getModel(),
            "stream": true,
            "messages": try await buildOpenAIMessages(messages: messages),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData

        // Send streaming request
        let (asyncBytes, response) = try await urlSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GlobalError(
                type: .network,
                i18nKey: "Invalid response",
                level: .notification
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorData = try await asyncBytes.reduce(into: Data()) { $0.append($1) }
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
            Logger.shared.error("AI API error response: \(errorMessage)")
            throw GlobalError(
                type: .network,
                i18nKey: "API error",
                level: .notification
            )
        }

        // Handling streaming responses (SSE format)
        var accumulatedContent = ""

        for try await line in asyncBytes.lines {
            guard !line.isEmpty else { continue }

            // OpenAI streaming response format: data: {...}
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                if jsonString == "[DONE]" {
                    break
                }

                guard !jsonString.isEmpty,
                      let jsonData = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let delta = firstChoice["delta"] as? [String: Any],
                      let content = delta["content"] as? String else {
                    continue
                }

                accumulatedContent += content
                await MainActor.run {
                    chatState.updateLastMessage(accumulatedContent)
                }
            }
        }

        await MainActor.run {
            chatState.isSending = false
        }
    }

    /// Construct a message array in OpenAI format
    private func buildOpenAIMessages(messages: [ChatMessage]) async throws -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []

        for message in messages {
            var messageDict: [String: Any] = [
                "role": message.role.rawValue
            ]

            // Handle text content and file attachments
            var contentParts: [String] = []

            if !message.content.isEmpty {
                contentParts.append(message.content)
            }

            // Handle file attachments (skip images)
            for attachment in message.attachments {
                if case .file(let url, let fileName) = attachment {
                    let fileText = await processFile(url: url, fileName: fileName)
                    contentParts.append(fileText)
                }
                // Ignore image attachments
            }

            if contentParts.isEmpty {
                messageDict["content"] = ""
            } else if contentParts.count == 1 {
                messageDict["content"] = contentParts[0]
            } else {
                messageDict["content"] = contentParts.joined(separator: "\n\n")
            }

            apiMessages.append(messageDict)
        }

        return apiMessages
    }

    // MARK: - Ollama format

    private func sendOllamaMessage(messages: [ChatMessage], chatState: ChatState) async throws {
        let baseURL = settings.selectedProvider == .ollama
            ? (settings.ollamaBaseURL.isEmpty ? settings.selectedProvider.baseURL : settings.ollamaBaseURL)
            : settings.selectedProvider.baseURL
        let apiURL = baseURL + settings.selectedProvider.apiPath

        guard let url = URL(string: apiURL) else {
            throw GlobalError.network(
                i18nKey: "Invalid URL",
                level: .notification
            )
        }

        // Build request body
        let requestBody: [String: Any] = [
            "model": settings.getModel(),
            "stream": true,
            "messages": try await buildOllamaMessages(messages: messages),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Ollama may not require an API Key, but add it if you have one
        if !settings.apiKey.isEmpty {
            request.setValue(settings.apiKey, forHTTPHeaderField: "Authorization")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData

        // Send streaming request
        let (asyncBytes, response) = try await urlSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GlobalError(
                type: .network,
                i18nKey: "Invalid response",
                level: .notification
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorData = try await asyncBytes.reduce(into: Data()) { $0.append($1) }
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
            Logger.shared.error("AI API error response: \(errorMessage)")
            throw GlobalError(
                type: .network,
                i18nKey: "API error",
                level: .notification
            )
        }

        // Handling streaming responses
        var accumulatedContent = ""
        for try await line in asyncBytes.lines {
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Ollama streaming response format: {"message": {"content": "..."}, "done": false}
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                accumulatedContent += content
                await MainActor.run {
                    chatState.updateLastMessage(accumulatedContent)
                }
            }

            if let done = json["done"] as? Bool, done {
                break
            }
        }

        await MainActor.run {
            chatState.isSending = false
        }
    }

    /// Construct a message array in Ollama format
    private func buildOllamaMessages(messages: [ChatMessage]) async throws -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []

        for message in messages {
            var messageDict: [String: Any] = [
                "role": message.role.rawValue
            ]

            // Handle text content and file attachments
            var contentParts: [String] = []

            if !message.content.isEmpty {
                contentParts.append(message.content)
            }

            // Handle file attachments (skip images)
            for attachment in message.attachments {
                if case .file(let url, let fileName) = attachment {
                    let fileText = await processFile(url: url, fileName: fileName)
                    contentParts.append(fileText)
                }
                // Ignore image attachments
            }

            if contentParts.isEmpty {
                messageDict["content"] = ""
            } else {
                messageDict["content"] = contentParts.joined(separator: "\n\n")
            }

            apiMessages.append(messageDict)
        }

        return apiMessages
    }

    // MARK: - Gemini format

    private func sendGeminiMessage(messages: [ChatMessage], chatState: ChatState) async throws {
        let model = settings.getModel()
        // Gemini API requires key as query parameter
        let apiURL = "\(settings.selectedProvider.baseURL)/v1/models/\(model):streamGenerateContent?key=\(settings.apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? settings.apiKey)"

        guard let url = URL(string: apiURL) else {
            throw GlobalError.network(
                i18nKey: "Invalid URL",
                level: .notification
            )
        }

        // Build request body
        let requestBody: [String: Any] = [
            "contents": try await buildGeminiContents(messages: messages)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData

        // Send streaming request
        let (asyncBytes, response) = try await urlSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GlobalError(
                type: .network,
                i18nKey: "Invalid response",
                level: .notification
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorData = try await asyncBytes.reduce(into: Data()) { $0.append($1) }
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
            Logger.shared.error("AI API error response: \(errorMessage)")
            throw GlobalError(
                type: .network,
                i18nKey: "API error",
                level: .notification
            )
        }

        // Handling streaming responses
        var accumulatedContent = ""
        for try await line in asyncBytes.lines {
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                continue
            }

            accumulatedContent += text
            await MainActor.run {
                chatState.updateLastMessage(accumulatedContent)
            }
        }

        await MainActor.run {
            chatState.isSending = false
        }
    }

    /// Construct a content array in Gemini format
    private func buildGeminiContents(messages: [ChatMessage]) async throws -> [[String: Any]] {
        var contents: [[String: Any]] = []

        for message in messages {
            var parts: [[String: Any]] = []

            // Process text content
            if !message.content.isEmpty {
                parts.append(["text": message.content])
            }

            // Handle file attachments
            for attachment in message.attachments {
                if case .file(let url, let fileName) = attachment {
                    let fileText = await processFile(url: url, fileName: fileName)
                    parts.append(["text": fileText])
                }
            }

            guard !parts.isEmpty else { continue }

            var contentDict: [String: Any] = [
                "parts": parts
            ]

            // Set the role (Gemini uses "user" and "model")
            if message.role == .assistant {
                contentDict["role"] = "model"
            } else {
                contentDict["role"] = "user"
            }

            contents.append(contentDict)
        }

        return contents
    }

    // MARK: - File handling

    /// Processing files: reading text content
    private func processFile(url: URL, fileName: String) async -> String {
        // File size threshold: 100KB
        let maxFileSizeForReading: Int64 = 100_000

        // Get file size
        guard let fileSize = await getFileSize(url: url) else {
            return await readFileContent(url: url, fileName: fileName) ??
                   String(format: String(localized: "File: \(fileName) (cannot read)"))
        }

        // Determine processing method based on size
        if fileSize <= maxFileSizeForReading {
            // Small files: read text content
            return await readFileContent(url: url, fileName: fileName) ??
                   String(format: String(localized: "File: \(fileName) (cannot read text content)"))
        } else {
            // Large files: return file information
            let sizeDescription = formatFileSize(fileSize)
            return String(format: String(localized: "File: %@ (too large: %@)"), fileName, sizeDescription)
        }
    }

    /// Read file content (small file)
    private func readFileContent(url: URL, fileName: String) async -> String? {
        guard let fileContent = await loadFileAsText(url: url) else { return nil }

        let maxLength = 5000
        // Use string interpolation instead of string concatenation
        let truncatedContent = fileContent.count > maxLength
            ? "\(String(fileContent.prefix(maxLength)))\n... \(String(localized: "(content truncated)"))"
            : fileContent

        return String(format: String(localized: "File: \(fileName)\nContent:\n\(truncatedContent)"))
    }

    /// Get file size (bytes)
    private func getFileSize(url: URL) async -> Int64? {
        await Task.detached(priority: .utility) {
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                return nil
            }

            // `.size` may be Int/Int64/NSNumber in different platforms/scenarios, do a compatible analysis
            if let size = attributes[.size] as? Int64 { return size }
            if let size = attributes[.size] as? Int { return Int64(size) }
            if let size = attributes[.size] as? NSNumber { return size.int64Value }
            return nil
        }.value
    }

    /// Format file size
    private func formatFileSize(_ bytes: Int64) -> String {
        let sizeInKB = Double(bytes) / 1024.0
        
        if sizeInKB < 1024 {
            return String(format: "%.1f KB", sizeInKB)
        } else {
            let sizeInMB = sizeInKB / 1024.0
            return String(format: "%.2f MB", sizeInMB)
        }
    }

    /// Load file as text
    private func loadFileAsText(url: URL) async -> String? {
        await Task.detached(priority: .utility) {
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }

            // Synchronous reading is used here, but placed on a background thread to avoid @MainActor blocking (log/text attachments will be obvious)
            return try? String(contentsOf: url, encoding: .utf8)
        }.value
    }

    // MARK: - Open chat window

    /// Open chat window
    func openChatWindow() {
        let chatState = ChatState()
        // Store to WindowDataStore
        WindowDataStore.shared.aiChatState = chatState
        // open window
        WindowManager.shared.openWindow(id: .aiChat)
    }
}
