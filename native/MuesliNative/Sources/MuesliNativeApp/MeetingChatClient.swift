import Foundation
import MuesliCore

/// One turn in a meeting chat conversation.
struct MeetingChatMessage: Equatable, Identifiable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    var content: String
    /// Backend failure surfaced as a red bubble; excluded from LLM history.
    var isError: Bool = false

    init(role: Role, content: String, isError: Bool = false) {
        self.role = role
        self.content = content
        self.isError = isError
    }
}

/// The meeting material a chat answer is grounded in.
struct MeetingChatContext {
    let title: String
    let formattedNotes: String
    let manualNotes: String
    let transcript: String
}

/// Free-form Q&A about a meeting, powered by whichever LLM backend the user
/// selected for meeting summaries (config.meetingSummaryBackend). Mirrors the
/// backend dispatch of MeetingSummaryClient and reuses its error type.
enum MeetingChatClient {
    private static let maxOutputTokens = 1200
    private static let requestTimeout: TimeInterval = 120
    private static let transcriptCharBudget = 16_000
    private static let defaultOpenAIModel = "gpt-5.4-mini"
    private static let defaultOpenRouterModel = "stepfun/step-3.5-flash:free"
    private static let defaultChatGPTModel = "gpt-5.4-mini"
    private static let defaultOllamaModel = "qwen3.5"
    private static let openAIURL = URL(string: "https://api.openai.com/v1/responses")!
    private static let openRouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let defaultOllamaBaseURL = URL(string: "http://localhost:11434")!

    private static let instructions = """
    You are a helpful assistant answering questions about one specific meeting. \
    Base every answer only on the meeting material provided below (title, notes, \
    written notes, and transcript). If the material does not contain the answer, \
    say you don't see it in this meeting rather than guessing. Be concise and \
    conversational. Reply in the same language the user writes in. Use light \
    markdown only when it helps readability.
    """

    static func reply(
        history: [MeetingChatMessage],
        context: MeetingChatContext,
        config: AppConfig
    ) async throws -> String {
        try await dispatch(history: history, system: systemPrompt(for: context), config: config)
    }

    /// Single-shot completion with an explicit system prompt — used by the
    /// analytics Insights page to run one aggregate pass over many meetings on
    /// the user's selected backend.
    static func complete(system: String, user: String, config: AppConfig) async throws -> String {
        try await dispatch(
            history: [MeetingChatMessage(role: .user, content: user)],
            system: system,
            config: config
        )
    }

    private static func dispatch(
        history: [MeetingChatMessage],
        system: String,
        config: AppConfig
    ) async throws -> String {
        let backend = (config.meetingSummaryBackend.isEmpty
            ? MeetingSummaryBackendOption.chatGPT.backend
            : config.meetingSummaryBackend).lowercased()

        if backend == MeetingSummaryBackendOption.chatGPT.backend {
            return try await replyWithChatGPT(history: history, system: system, config: config)
        }
        if backend == MeetingSummaryBackendOption.openRouter.backend {
            return try await replyWithOpenRouter(history: history, system: system, config: config)
        }
        if backend == MeetingSummaryBackendOption.ollama.backend {
            return try await replyWithOllama(history: history, system: system, config: config)
        }
        if backend == MeetingSummaryBackendOption.lmStudio.backend {
            return try await replyWithLMStudio(history: history, system: system, config: config)
        }
        if backend == MeetingSummaryBackendOption.customLLM.backend {
            return try await replyWithCustomLLM(history: history, system: system, config: config)
        }
        return try await replyWithOpenAI(history: history, system: system, config: config)
    }

    // MARK: - Prompt building

    private static func systemPrompt(for context: MeetingChatContext) -> String {
        var sections = [instructions, "--- MEETING ---", "Title: \(context.title)"]
        let notes = context.formattedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            sections.append("## Notes\n\(notes)")
        }
        let manual = context.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty {
            sections.append("## Written notes\n\(manual)")
        }
        let transcript = truncatedTranscript(context.transcript)
        if !transcript.isEmpty {
            sections.append("## Transcript\n\(transcript)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func truncatedTranscript(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > transcriptCharBudget else { return trimmed }
        // Keep the opening and the ending — both usually carry key context.
        let half = transcriptCharBudget / 2
        let head = String(trimmed.prefix(half))
        let tail = String(trimmed.suffix(half))
        return head + "\n\n[…transcript truncated…]\n\n" + tail
    }

    /// OpenAI-style chat messages array: system first, then the conversation.
    private static func messagesArray(system: String, history: [MeetingChatMessage]) -> [[String: Any]] {
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for message in history {
            messages.append(["role": message.role.rawValue, "content": message.content])
        }
        return messages
    }

    /// Flattens the conversation into a single prompt (for backends that only
    /// accept one user message, i.e. the ChatGPT WHAM client).
    private static func flattenedPrompt(history: [MeetingChatMessage]) -> String {
        guard history.count > 1 else {
            return history.last?.content ?? ""
        }
        var lines: [String] = []
        for message in history.dropLast() {
            let speaker = message.role == .user ? "User" : "Assistant"
            lines.append("\(speaker): \(message.content)")
        }
        if let latest = history.last {
            lines.append("")
            lines.append("User's new message: \(latest.content)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Backends

    private static func replyWithChatGPT(
        history: [MeetingChatMessage],
        system: String,
        config: AppConfig
    ) async throws -> String {
        do {
            let text = try await ChatGPTResponsesClient.respond(
                systemPrompt: system,
                userPrompt: flattenedPrompt(history: history),
                model: config.chatGPTModel.isEmpty ? defaultChatGPTModel : config.chatGPTModel,
                logCategory: "chat"
            )
            guard !text.isEmpty else { throw MeetingSummaryError.emptyResponse(backend: "ChatGPT") }
            return text
        } catch {
            throw MeetingSummaryError.requestFailed(backend: "ChatGPT", underlying: error)
        }
    }

    private static func replyWithOpenAI(
        history: [MeetingChatMessage],
        system: String,
        config: AppConfig
    ) async throws -> String {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? config.openAIAPIKey
        guard !apiKey.isEmpty else {
            throw MeetingSummaryError.backendFailed(backend: "OpenAI", statusCode: nil, message: "No API key configured. Add an OpenAI key in Settings.")
        }
        let body: [String: Any] = [
            "model": config.openAIModel.isEmpty ? defaultOpenAIModel : config.openAIModel,
            "input": messagesArray(system: system, history: history),
            "reasoning": ["effort": "low"],
            "text": ["verbosity": "low"],
            "max_output_tokens": maxOutputTokens,
        ]
        return try await send(
            url: openAIURL,
            body: body,
            backend: "OpenAI",
            headers: ["Authorization": "Bearer \(apiKey)"],
            extract: extractOpenAIText
        )
    }

    private static func replyWithOpenRouter(
        history: [MeetingChatMessage],
        system: String,
        config: AppConfig
    ) async throws -> String {
        let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? config.openRouterAPIKey
        guard !apiKey.isEmpty else {
            throw MeetingSummaryError.backendFailed(backend: "OpenRouter", statusCode: nil, message: "No API key configured. Add an OpenRouter key in Settings.")
        }
        let configuredModel = config.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "model": configuredModel.isEmpty ? defaultOpenRouterModel : configuredModel,
            "messages": messagesArray(system: system, history: history),
            "max_tokens": maxOutputTokens,
        ]
        return try await send(
            url: openRouterURL,
            body: body,
            backend: "OpenRouter",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "X-OpenRouter-Title": AppIdentity.displayName,
            ],
            extract: extractChatCompletionText
        )
    }

    private static func replyWithOllama(
        history: [MeetingChatMessage],
        system: String,
        config: AppConfig
    ) async throws -> String {
        let baseURLString = config.ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL: URL
        if baseURLString.isEmpty {
            baseURL = defaultOllamaBaseURL
        } else if let url = URL(string: baseURLString) {
            baseURL = url
        } else {
            throw MeetingSummaryError.backendFailed(backend: "Ollama", statusCode: nil, message: "Invalid Ollama URL: \(baseURLString)")
        }
        let configuredModel = config.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "model": configuredModel.isEmpty ? defaultOllamaModel : configuredModel,
            "messages": messagesArray(system: system, history: history),
            "stream": false,
            "options": ["num_predict": maxOutputTokens],
        ]
        return try await send(
            url: baseURL.appendingPathComponent("api/chat"),
            body: body,
            backend: "Ollama",
            headers: [:],
            extract: extractOllamaText
        )
    }

    private static func replyWithLMStudio(
        history: [MeetingChatMessage],
        system: String,
        config: AppConfig
    ) async throws -> String {
        guard let url = MeetingSummaryClient.resolveLMStudioURL(config: config) else {
            throw MeetingSummaryError.backendFailed(backend: "LM Studio", statusCode: nil, message: "Invalid LM Studio URL.")
        }
        let model = config.lmStudioModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw MeetingSummaryError.backendFailed(backend: "LM Studio", statusCode: nil, message: "No model selected in Settings.")
        }
        let body: [String: Any] = [
            "model": model,
            "messages": messagesArray(system: system, history: history),
            "max_tokens": maxOutputTokens,
        ]
        return try await send(url: url, body: body, backend: "LM Studio", headers: [:], extract: extractChatCompletionText)
    }

    private static func replyWithCustomLLM(
        history: [MeetingChatMessage],
        system: String,
        config: AppConfig
    ) async throws -> String {
        let format = CustomLLMFormat(rawValue: config.customLLMFormat) ?? .openAI
        guard let url = MeetingSummaryClient.resolveCustomLLMURL(config: config, format: format) else {
            throw MeetingSummaryError.backendFailed(backend: "Custom LLM", statusCode: nil, message: "Invalid custom URL.")
        }
        let model = config.customLLMModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw MeetingSummaryError.backendFailed(backend: "Custom LLM", statusCode: nil, message: "No model configured in Settings.")
        }
        let apiKey = config.customLLMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch format {
        case .openAI:
            let body: [String: Any] = [
                "model": model,
                "messages": messagesArray(system: system, history: history),
                "max_tokens": maxOutputTokens,
            ]
            var headers: [String: String] = [:]
            if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
            return try await send(url: url, body: body, backend: "Custom LLM", headers: headers, extract: extractChatCompletionText)
        case .anthropic:
            var messages: [[String: Any]] = []
            for message in history {
                messages.append(["role": message.role.rawValue, "content": message.content])
            }
            let body: [String: Any] = [
                "model": model,
                "max_tokens": maxOutputTokens,
                "system": system,
                "messages": messages,
            ]
            var headers = ["anthropic-version": "2023-06-01"]
            if !apiKey.isEmpty { headers["x-api-key"] = apiKey }
            return try await send(url: url, body: body, backend: "Custom LLM", headers: headers, extract: extractAnthropicText)
        }
    }

    // MARK: - Transport

    private static func send(
        url: URL,
        body: [String: Any],
        backend: String,
        headers: [String: String],
        extract: @escaping ([String: Any]) -> String?
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let message = extractErrorMessage(from: data)
                    ?? String(data: data, encoding: .utf8)
                    ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                throw MeetingSummaryError.backendFailed(backend: backend, statusCode: http.statusCode, message: String(message.prefix(600)))
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let text = extract(json), !text.isEmpty
            else {
                if let message = extractErrorMessage(from: data) {
                    throw MeetingSummaryError.backendFailed(backend: backend, statusCode: nil, message: message)
                }
                throw MeetingSummaryError.emptyResponse(backend: backend)
            }
            return text
        } catch let error as MeetingSummaryError {
            throw error
        } catch {
            throw MeetingSummaryError.requestFailed(backend: backend, underlying: error)
        }
    }

    // MARK: - Response extraction

    private static func extractChatCompletionText(_ payload: [String: Any]) -> String? {
        let choices = payload["choices"] as? [[String: Any]] ?? []
        guard let message = choices.first?["message"] as? [String: Any] else { return nil }
        if let content = message["content"] as? String, !content.isEmpty {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = message["content"] as? [[String: Any]] {
            let joined = parts.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func extractOpenAIText(_ payload: [String: Any]) -> String? {
        if let outputText = payload["output_text"] as? String, !outputText.isEmpty {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let output = payload["output"] as? [[String: Any]] ?? []
        for item in output where (item["type"] as? String) == "message" {
            let content = item["content"] as? [[String: Any]] ?? []
            for entry in content {
                if let text = entry["text"] as? String, !text.isEmpty {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    private static func extractAnthropicText(_ payload: [String: Any]) -> String? {
        let content = payload["content"] as? [[String: Any]] ?? []
        let parts = content.compactMap { $0["text"] as? String }
        let joined = parts.joined()
        return joined.isEmpty ? nil : joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractOllamaText(_ payload: [String: Any]) -> String? {
        guard let message = payload["message"] as? [String: Any],
              let text = message["content"] as? String, !text.isEmpty else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty { return message }
            if let code = error["code"] as? String, !code.isEmpty { return code }
        }
        if let message = json["error"] as? String, !message.isEmpty { return message }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        return nil
    }
}
