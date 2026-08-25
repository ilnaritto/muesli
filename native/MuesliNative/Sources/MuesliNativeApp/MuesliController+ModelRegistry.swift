import Foundation

/// The model registry (task 8.2): a catalog of every model the user has
/// connected, for any role, local or cloud — as many as they like. Two
/// different things are unified here:
///
/// - **Text-generation models** are genuinely new persisted entries
///   (`config.configuredModels`): before this, the app could only hold ONE
///   set of credentials per provider type (one OpenAI key, one Ollama URL),
///   so "my own Ollama AND ChatGPT AND a custom endpoint at once" was not
///   representable. `defaultModelIDs[.textGeneration]` is the only role
///   where this file is the actual source of truth for "what's selected."
/// - **Transcription and cleanup models** already supported "download as
///   many as you like, pick one" via `BackendOption`/`PostProcessorOption` —
///   the gap there was a scattered UX (Models tab to download, a different
///   settings pane to pick), not a data-model limitation. For those two
///   roles this file only *lists* what's downloaded; the actual selection
///   still flows through the existing `selectBackend` /
///   `selectMeetingTranscriptionBackend` / `selectPostProcessor` calls,
///   which already own preloading engines and other side effects that
///   should not be duplicated here.
extension MuesliController {
    /// All models available for a role: persisted registry entries plus
    /// (for transcription/cleanup) the already-downloaded bundled models.
    func configuredModels(role: ModelRole) -> [ConfiguredModel] {
        var result = config.configuredModels.filter { $0.role == role && $0.isEnabled }
        switch role {
        case .transcription:
            result.append(contentsOf: Self.derivedTranscriptionModels())
        case .cleanup:
            result.append(contentsOf: Self.derivedCleanupModels())
        case .textGeneration:
            // The local GGUF summarizer can be downloaded after migration
            // already ran — surface it live rather than only at migration time.
            if LocalSummaryModelOption.isAnyDownloaded,
               !result.contains(where: { $0.provider == .bundledLocal }) {
                result.append(Self.derivedLocalTextModel())
            }
        }
        return result
    }

    static func derivedLocalTextModel() -> ConfiguredModel {
        ConfiguredModel(
            id: "bundled:local_gguf:\(LocalSummaryModelOption.defaultOption.id)",
            displayName: "\(LocalSummaryModelOption.defaultOption.label) (local)",
            role: .textGeneration,
            provider: .bundledLocal,
            modelID: LocalSummaryModelOption.defaultOption.id
        )
    }

    /// Every persisted entry for a role, enabled or not — for the Models
    /// management screen, which needs to show disabled ones too.
    func allConfiguredModels(role: ModelRole) -> [ConfiguredModel] {
        config.configuredModels.filter { $0.role == role }
    }

    /// `BackendOption.downloaded` stats the filesystem for every backend
    /// (`FileManager.contentsOfDirectory` etc.). `configuredModels(role:)` is
    /// called from inside SwiftUI view bodies, including ones that also
    /// render toggles elsewhere in the same pane — any unrelated `@Observable`
    /// config change re-runs that whole body, so an uncached disk scan here
    /// made every settings toggle feel like it hitches before flipping.
    /// A short TTL keeps this responsive to real downloads without scanning
    /// disk on every render.
    private static var cachedDownloadedBackendOptions: (at: Date, options: [BackendOption])?
    private static let downloadedCacheTTL: TimeInterval = 2

    private static func downloadedBackendOptionsCached() -> [BackendOption] {
        if let cached = cachedDownloadedBackendOptions, Date().timeIntervalSince(cached.at) < downloadedCacheTTL {
            return cached.options
        }
        let fresh = BackendOption.downloaded
        cachedDownloadedBackendOptions = (Date(), fresh)
        return fresh
    }

    static func derivedTranscriptionModels() -> [ConfiguredModel] {
        downloadedBackendOptionsCached().map { option in
            ConfiguredModel(
                id: bundledTranscriptionID(option),
                displayName: option.label,
                role: .transcription,
                provider: .bundledLocal,
                modelID: option.model
            )
        }
    }

    private static var cachedDownloadedPostProcessorOptions: (at: Date, options: [PostProcessorOption])?

    private static func downloadedPostProcessorOptionsCached() -> [PostProcessorOption] {
        if let cached = cachedDownloadedPostProcessorOptions, Date().timeIntervalSince(cached.at) < downloadedCacheTTL {
            return cached.options
        }
        let fresh = PostProcessorOption.downloaded
        cachedDownloadedPostProcessorOptions = (Date(), fresh)
        return fresh
    }

    static func derivedCleanupModels() -> [ConfiguredModel] {
        downloadedPostProcessorOptionsCached().map { option in
            ConfiguredModel(
                id: bundledCleanupID(option),
                displayName: option.label,
                role: .cleanup,
                provider: .bundledLocal,
                modelID: option.id
            )
        }
    }

    /// Stable synthetic ids for the derived (non-persisted) local entries.
    static func bundledTranscriptionID(_ option: BackendOption) -> String {
        "bundled:\(option.backend):\(option.model)"
    }

    static func bundledCleanupID(_ option: PostProcessorOption) -> String {
        "bundled:\(option.id)"
    }

    // MARK: - Text-generation default (the one role this registry truly drives)

    func defaultConfiguredModelID(role: ModelRole) -> String? {
        config.defaultModelIDs[role.rawValue]
    }

    func defaultConfiguredModel(role: ModelRole) -> ConfiguredModel? {
        guard let id = defaultConfiguredModelID(role: role) else { return nil }
        return configuredModels(role: role).first { $0.id == id }
    }

    func setDefaultConfiguredModel(id: String, role: ModelRole) {
        updateConfig { $0.defaultModelIDs[role.rawValue] = id }
    }

    // MARK: - Insights chat model (independent selection, task 1)

    /// The Insights composer's model pill: `config.insightsModelID` if it's
    /// still a connected text model, else the meeting-summary default.
    func insightsModelID() -> String? {
        let models = configuredModels(role: .textGeneration)
        if let id = config.insightsModelID, models.contains(where: { $0.id == id }) {
            return id
        }
        return defaultConfiguredModelID(role: .textGeneration)
    }

    func setInsightsModelID(_ id: String) {
        updateConfig { $0.insightsModelID = id }
    }

    // MARK: - CRUD

    /// Adds a model to the registry. `secret` (an API key) is written to
    /// `ModelSecretsStore` and only its reference is persisted in config.
    @discardableResult
    func addConfiguredModel(
        displayName: String,
        role: ModelRole,
        provider: ModelProvider,
        modelID: String,
        endpointURL: String = "",
        localPath: String? = nil,
        secret: String? = nil
    ) -> ConfiguredModel {
        let ref = secret.flatMap { $0.isEmpty ? nil : ModelSecretsStore.save($0) }
        let model = ConfiguredModel(
            displayName: displayName,
            role: role,
            provider: provider,
            modelID: modelID,
            endpointURL: endpointURL,
            localPath: localPath,
            keychainRef: ref
        )
        updateConfig { config in
            config.configuredModels.append(model)
            if config.defaultModelIDs[role.rawValue] == nil {
                config.defaultModelIDs[role.rawValue] = model.id
            }
        }
        return model
    }

    /// - Parameter secret: pass to replace the stored secret; pass `nil` to
    ///   leave the existing one untouched (the edit form doesn't re-show it).
    func updateConfiguredModel(
        id: String,
        displayName: String,
        modelID: String,
        endpointURL: String,
        secret: String?
    ) {
        updateConfig { config in
            guard let index = config.configuredModels.firstIndex(where: { $0.id == id }) else { return }
            config.configuredModels[index].displayName = displayName
            config.configuredModels[index].modelID = modelID
            config.configuredModels[index].endpointURL = endpointURL
            if let secret {
                if let existingRef = config.configuredModels[index].keychainRef {
                    ModelSecretsStore.update(ref: existingRef, secret: secret)
                } else {
                    config.configuredModels[index].keychainRef = ModelSecretsStore.save(secret)
                }
            }
        }
    }

    func setConfiguredModelEnabled(id: String, enabled: Bool) {
        updateConfig { config in
            guard let index = config.configuredModels.firstIndex(where: { $0.id == id }) else { return }
            config.configuredModels[index].isEnabled = enabled
            if !enabled {
                for role in ModelRole.allCases where config.defaultModelIDs[role.rawValue] == id {
                    config.defaultModelIDs[role.rawValue] = config.configuredModels.first {
                        $0.role == role && $0.isEnabled && $0.id != id
                    }?.id
                }
            }
        }
    }

    func removeConfiguredModel(id: String) {
        updateConfig { config in
            guard let index = config.configuredModels.firstIndex(where: { $0.id == id }) else { return }
            ModelSecretsStore.delete(ref: config.configuredModels[index].keychainRef)
            let role = config.configuredModels[index].role
            config.configuredModels.remove(at: index)
            if config.defaultModelIDs[role.rawValue] == id {
                config.defaultModelIDs[role.rawValue] = config.configuredModels.first { $0.role == role && $0.isEnabled }?.id
            }
        }
    }

    // MARK: - Connection test

    /// One cheap request to confirm the endpoint/key actually work, before
    /// the user finds out only when a meeting summary fails. Returns nil on
    /// success, or a short error string.
    func testConfiguredModelConnection(
        provider: ModelProvider,
        endpointURL: String,
        modelID: String,
        secret: String?
    ) async -> String? {
        switch provider {
        case .bundledLocal, .localGGUF:
            return nil
        case .chatGPTOAuth:
            return appState.isChatGPTAuthenticated ? nil : tr("Not signed in to ChatGPT.", "Не выполнен вход в ChatGPT.")
        case .ollama, .lmStudio:
            guard let url = URL(string: endpointURL), !endpointURL.isEmpty else {
                return tr("Enter a valid URL.", "Введите корректный URL.")
            }
            return await Self.probeHTTP(url: url, headers: [:], timeout: 6)
        case .openAICompatible, .anthropicCompatible:
            guard let url = URL(string: endpointURL), !endpointURL.isEmpty else {
                return tr("Enter a valid URL.", "Введите корректный URL.")
            }
            var headers: [String: String] = [:]
            if let secret, !secret.isEmpty {
                headers["Authorization"] = "Bearer \(secret)"
                headers["x-api-key"] = secret
            }
            return await Self.probeHTTP(url: url, headers: headers, timeout: 8)
        }
    }

    private static func probeHTTP(url: URL, headers: [String: String], timeout: TimeInterval) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return tr("No response from the server.", "Сервер не ответил.")
            }
            // Any response at all (even 404/405 for a GET on a chat-completions
            // endpoint) means the host is reachable and listening — good enough
            // for "is this endpoint alive", short of sending a real generation.
            if http.statusCode == 401 || http.statusCode == 403 {
                return tr("Rejected — check the API key.", "Отклонено — проверьте API-ключ.")
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Legacy migration

    /// One-shot: materializes the pre-registry summary-backend settings
    /// (every provider that actually has credentials/config, not just the
    /// currently active one — so nothing the user already set up "vanishes")
    /// into `configuredModels`, and carries the previously active backend
    /// forward as the new default.
    func migrateLegacyModelsToRegistryIfNeeded() {
        guard !config.didMigrateLegacyModelsToRegistry else { return }
        updateConfig { cfg in
            var migrated: [ConfiguredModel] = []

            if !cfg.openAIAPIKey.trimmingCharacters(in: .whitespaces).isEmpty {
                let ref = ModelSecretsStore.save(cfg.openAIAPIKey)
                migrated.append(ConfiguredModel(
                    displayName: "OpenAI",
                    role: .textGeneration,
                    provider: .openAICompatible,
                    modelID: cfg.openAIModel.isEmpty ? "gpt-5.4-mini" : cfg.openAIModel,
                    endpointURL: "https://api.openai.com/v1/chat/completions",
                    keychainRef: ref
                ))
                // Wipe the plaintext copy now that the secret lives in the
                // registry's store — leaving both around defeats the point.
                cfg.openAIAPIKey = ""
            }
            if !cfg.openRouterAPIKey.trimmingCharacters(in: .whitespaces).isEmpty {
                let ref = ModelSecretsStore.save(cfg.openRouterAPIKey)
                migrated.append(ConfiguredModel(
                    displayName: "OpenRouter",
                    role: .textGeneration,
                    provider: .openAICompatible,
                    modelID: cfg.openRouterModel,
                    endpointURL: "https://openrouter.ai/api/v1/chat/completions",
                    keychainRef: ref
                ))
                cfg.openRouterAPIKey = ""
            }
            if !cfg.customLLMURL.trimmingCharacters(in: .whitespaces).isEmpty {
                let ref = cfg.customLLMAPIKey.isEmpty ? nil : ModelSecretsStore.save(cfg.customLLMAPIKey)
                let provider: ModelProvider = cfg.customLLMFormat == CustomLLMFormat.anthropic.rawValue ? .anthropicCompatible : .openAICompatible
                migrated.append(ConfiguredModel(
                    displayName: "Custom LLM",
                    role: .textGeneration,
                    provider: provider,
                    modelID: cfg.customLLMModel,
                    endpointURL: cfg.customLLMURL,
                    keychainRef: ref
                ))
                cfg.customLLMAPIKey = ""
            }
            // Ollama/LM Studio ship non-empty default URLs even when unused —
            // only migrate them if the user actually selected that backend at
            // least once, otherwise every fresh install gets two phantom entries.
            if cfg.meetingSummaryBackend == MeetingSummaryBackendOption.ollama.backend {
                migrated.append(ConfiguredModel(displayName: "Ollama", role: .textGeneration, provider: .ollama, modelID: cfg.ollamaModel, endpointURL: cfg.ollamaURL))
            }
            if cfg.meetingSummaryBackend == MeetingSummaryBackendOption.lmStudio.backend {
                migrated.append(ConfiguredModel(displayName: "LM Studio", role: .textGeneration, provider: .lmStudio, modelID: cfg.lmStudioModel, endpointURL: cfg.lmStudioURL))
            }
            // "chatgpt" is the compiled-in DEFAULT of meetingSummaryBackend —
            // true on every fresh install whether or not the user ever
            // touched it. Gate this one on real sign-in state instead of the
            // backend string, or every new user gets a phantom ChatGPT entry
            // that silently wins as the default text model.
            if chatGPTAuth.isAuthenticated {
                migrated.append(ConfiguredModel(displayName: "ChatGPT", role: .textGeneration, provider: .chatGPTOAuth, modelID: cfg.chatGPTModel.isEmpty ? "gpt-5.4-mini" : cfg.chatGPTModel))
            }
            if cfg.meetingSummaryBackend == MeetingSummaryBackendOption.localGguf.backend || LocalSummaryModelOption.isAnyDownloaded {
                migrated.append(ConfiguredModel(displayName: "T-lite 7B (local)", role: .textGeneration, provider: .bundledLocal, modelID: LocalSummaryModelOption.defaultOption.id))
            }

            cfg.configuredModels.append(contentsOf: migrated)

            let activeBackend = MeetingSummaryBackendOption.resolved(cfg.meetingSummaryBackend).backend
            let activeModel = migrated.first { model in
                switch model.provider {
                case .chatGPTOAuth: return activeBackend == MeetingSummaryBackendOption.chatGPT.backend
                case .ollama: return activeBackend == MeetingSummaryBackendOption.ollama.backend
                case .lmStudio: return activeBackend == MeetingSummaryBackendOption.lmStudio.backend
                case .bundledLocal: return activeBackend == MeetingSummaryBackendOption.localGguf.backend
                case .localGGUF: return false
                case .openAICompatible, .anthropicCompatible:
                    return (activeBackend == MeetingSummaryBackendOption.openAI.backend && model.displayName == "OpenAI")
                        || (activeBackend == MeetingSummaryBackendOption.openRouter.backend && model.displayName == "OpenRouter")
                        || (activeBackend == MeetingSummaryBackendOption.customLLM.backend && model.displayName == "Custom LLM")
                }
            }
            cfg.defaultModelIDs[ModelRole.textGeneration.rawValue] = (activeModel ?? migrated.first)?.id

            cfg.didMigrateLegacyModelsToRegistry = true
        }
    }
}
