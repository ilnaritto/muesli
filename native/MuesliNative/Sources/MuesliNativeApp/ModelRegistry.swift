import Foundation

/// A task a connected model is used for. Every picker in the app (dictation
/// model, meeting transcription model, cleanup model, Insights chat, meeting
/// chat) resolves its choices from the registry filtered to one role.
enum ModelRole: String, Codable, CaseIterable, Sendable {
    case transcription
    case textGeneration
    case cleanup

    var title: String {
        switch self {
        case .transcription: return tr("Speech", "Распознавание")
        case .textGeneration: return tr("Text", "Текстовые")
        case .cleanup: return tr("Cleanup", "Очистка")
        }
    }
}

enum ModelProvider: String, Codable, Sendable {
    /// A ready-made local model shipped by Muesli (BackendOption / PostProcessorOption).
    case bundledLocal
    /// A user-chosen local `.gguf` file.
    case localGGUF
    case ollama
    case lmStudio
    /// OpenAI, OpenRouter, or any other `/v1/chat/completions`-compatible endpoint.
    case openAICompatible
    /// Any `/v1/messages`-compatible endpoint.
    case anthropicCompatible
    /// Subscription-based ChatGPT via OAuth (WHAM API).
    case chatGPTOAuth

    var isLocal: Bool {
        switch self {
        case .bundledLocal, .localGGUF: return true
        case .ollama, .lmStudio, .openAICompatible, .anthropicCompatible, .chatGPTOAuth: return false
        }
    }

    var title: String {
        switch self {
        case .bundledLocal: return tr("Bundled", "Встроенная")
        case .localGGUF: return tr("Local GGUF", "Локальный GGUF")
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .openAICompatible: return tr("OpenAI-compatible", "OpenAI-совместимый")
        case .anthropicCompatible: return tr("Anthropic-compatible", "Anthropic-совместимый")
        case .chatGPTOAuth: return "ChatGPT"
        }
    }
}

/// One model the user has connected — local or cloud, for one role. The
/// user can connect any number of these per role (task 8.2): several ASR
/// models, several text backends (their own Ollama AND ChatGPT AND a custom
/// endpoint side by side), etc.
struct ConfiguredModel: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var displayName: String
    var role: ModelRole
    var provider: ModelProvider
    /// Provider-specific model identifier: a `BackendOption`/`PostProcessorOption`
    /// id for `.bundledLocal`, an Ollama/LM Studio model name, or a
    /// `gpt-5.4-mini`-style id for OpenAI/Anthropic-compatible endpoints.
    var modelID: String
    /// Empty for local/bundled providers.
    var endpointURL: String
    /// Set only for `.localGGUF`.
    var localPath: String?
    /// A reference to the secret in `ModelSecretsStore`, NOT the secret
    /// itself — never serialize an API key into this struct or into config.json.
    var keychainRef: String?
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        displayName: String,
        role: ModelRole,
        provider: ModelProvider,
        modelID: String,
        endpointURL: String = "",
        localPath: String? = nil,
        keychainRef: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.provider = provider
        self.modelID = modelID
        self.endpointURL = endpointURL
        self.localPath = localPath
        self.keychainRef = keychainRef
        self.isEnabled = isEnabled
    }
}

extension ConfiguredModel {
    /// Round 3 feedback: adding a model shouldn't force the user to declare
    /// a single "purpose" up front — a cloud LLM is equally usable for
    /// meeting-summary text generation and for dictation cleanup, so it
    /// should just show up on both tabs. Only the stored `role` (set once,
    /// at add-time, from the tab the user was on) still hard-scopes the
    /// handful of genuinely single-purpose local providers: a bundled ASR
    /// model obviously can't generate text, and the bundled cleanup GGUFs
    /// are a separate, privacy-motivated download from the bundled
    /// summarization GGUF. Every cloud/server LLM provider, by contrast,
    /// speaks the same "chat completion" capability regardless of which
    /// tab it was added from.
    var roles: Set<ModelRole> {
        switch provider {
        case .chatGPTOAuth, .openAICompatible, .anthropicCompatible, .ollama, .lmStudio:
            return [.textGeneration, .cleanup]
        case .bundledLocal, .localGGUF:
            return [role]
        }
    }

    /// Maps this model's provider (plus, for OpenAI-compatible endpoints,
    /// its URL) to the shared LLM backend identifier used by both meeting
    /// summarization and transcript cleanup. `nil` for local/bundled
    /// providers, which don't go through either hosted client.
    var llmBackendOption: LLMBackendOption? {
        switch provider {
        case .chatGPTOAuth: return .chatGPT
        case .ollama: return .ollama
        case .lmStudio: return .lmStudio
        case .anthropicCompatible: return .customLLM
        case .openAICompatible:
            let host = URL(string: endpointURL)?.host?.lowercased() ?? ""
            if endpointURL.isEmpty || host.contains("api.openai.com") {
                return .openAI
            } else if host.contains("openrouter.ai") {
                return .openRouter
            } else {
                return .customLLM
            }
        case .bundledLocal, .localGGUF:
            return nil
        }
    }
}

extension AppConfig {
    /// A transient, in-memory-only copy of this config where the legacy
    /// summary-backend fields (still read by `MeetingSummaryClient` /
    /// `MeetingChatClient`, which support all 7 backends — reused here
    /// rather than rewritten) are populated from the registry's default
    /// text-generation model. Never persisted: the resolved secret only
    /// lives in this copy for the duration of one summarization call.
    /// Free function of `self`, not a `MuesliController` method, so
    /// `MeetingSession` and `AudioFileImportController` — which hold their
    /// own `AppConfig` snapshot, not a controller reference — can call it too.
    ///
    /// - Parameter modelID: overrides which registry entry to resolve —
    ///   used by the Insights chat, which has its own model selection
    ///   independent of the meeting-summary default. Falls back to that
    ///   default when nil.
    func resolvedForTextGeneration(modelID overrideModelID: String? = nil) -> AppConfig {
        var effective = self
        guard let id = overrideModelID ?? defaultModelIDs[ModelRole.textGeneration.rawValue],
              let model = configuredModels.first(where: { $0.id == id && $0.roles.contains(.textGeneration) && $0.isEnabled }) else {
            return effective
        }
        let secret = ModelSecretsStore.read(ref: model.keychainRef) ?? ""
        switch model.llmBackendOption {
        case .chatGPT:
            effective.meetingSummaryBackend = MeetingSummaryBackendOption.chatGPT.backend
            if !model.modelID.isEmpty { effective.chatGPTModel = model.modelID }
        case .ollama:
            effective.meetingSummaryBackend = MeetingSummaryBackendOption.ollama.backend
            if !model.endpointURL.isEmpty { effective.ollamaURL = model.endpointURL }
            effective.ollamaModel = model.modelID
        case .lmStudio:
            effective.meetingSummaryBackend = MeetingSummaryBackendOption.lmStudio.backend
            if !model.endpointURL.isEmpty { effective.lmStudioURL = model.endpointURL }
            effective.lmStudioModel = model.modelID
        case .openAI:
            effective.meetingSummaryBackend = MeetingSummaryBackendOption.openAI.backend
            effective.openAIAPIKey = secret
            effective.openAIModel = model.modelID
        case .openRouter:
            effective.meetingSummaryBackend = MeetingSummaryBackendOption.openRouter.backend
            effective.openRouterAPIKey = secret
            effective.openRouterModel = model.modelID
        case .customLLM:
            effective.meetingSummaryBackend = MeetingSummaryBackendOption.customLLM.backend
            effective.customLLMURL = model.endpointURL
            effective.customLLMAPIKey = secret
            effective.customLLMModel = model.modelID
            effective.customLLMFormat = (model.provider == .anthropicCompatible ? CustomLLMFormat.anthropic : CustomLLMFormat.openAI).rawValue
        case nil:
            effective.meetingSummaryBackend = MeetingSummaryBackendOption.localGguf.backend
        default:
            break
        }
        return effective
    }

    /// Mirrors `resolvedForTextGeneration` for the transcript-cleanup path —
    /// same registry entry can now serve both, but cleanup reads its own
    /// set of `postProcessor*Model` fields (not `openAIModel`/`ollamaModel`
    /// etc.), which `resolvedForTextGeneration` doesn't touch, so the two
    /// selections stay independent even when they point at the same model.
    func resolvedForCleanup(modelID overrideModelID: String? = nil) -> AppConfig {
        var effective = self
        guard let id = overrideModelID ?? defaultModelIDs[ModelRole.cleanup.rawValue],
              let model = configuredModels.first(where: { $0.id == id && $0.roles.contains(.cleanup) && $0.isEnabled }) else {
            return effective
        }
        let secret = ModelSecretsStore.read(ref: model.keychainRef) ?? ""
        switch model.llmBackendOption {
        case .chatGPT:
            effective.postProcessorBackend = TranscriptCleanupBackendOption.hosted(.chatGPT).backend
            if !model.modelID.isEmpty { effective.postProcessorChatGPTModel = model.modelID }
        case .ollama:
            effective.postProcessorBackend = TranscriptCleanupBackendOption.hosted(.ollama).backend
            if !model.endpointURL.isEmpty { effective.ollamaURL = model.endpointURL }
            effective.postProcessorOllamaModel = model.modelID
        case .lmStudio:
            effective.postProcessorBackend = TranscriptCleanupBackendOption.hosted(.lmStudio).backend
            if !model.endpointURL.isEmpty { effective.lmStudioURL = model.endpointURL }
            effective.postProcessorLMStudioModel = model.modelID
        case .openAI:
            effective.postProcessorBackend = TranscriptCleanupBackendOption.hosted(.openAI).backend
            effective.openAIAPIKey = secret
            effective.postProcessorOpenAIModel = model.modelID
        case .openRouter:
            effective.postProcessorBackend = TranscriptCleanupBackendOption.hosted(.openRouter).backend
            effective.openRouterAPIKey = secret
            effective.postProcessorOpenRouterModel = model.modelID
        case .customLLM:
            effective.postProcessorBackend = TranscriptCleanupBackendOption.hosted(.customLLM).backend
            effective.customLLMURL = model.endpointURL
            effective.customLLMAPIKey = secret
            effective.postProcessorCustomLLMModel = model.modelID
            effective.customLLMFormat = (model.provider == .anthropicCompatible ? CustomLLMFormat.anthropic : CustomLLMFormat.openAI).rawValue
        case nil:
            effective.postProcessorBackend = TranscriptCleanupBackendOption.local.backend
        default:
            break
        }
        return effective
    }
}
