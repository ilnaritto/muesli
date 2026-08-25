import Testing
import Foundation
import MuesliCore
@testable import MuesliNativeApp

@Suite("ModelRegistry")
struct ModelRegistryTests {

    @Test("resolvedForTextGeneration leaves config untouched with no default model")
    func noDefaultModelLeavesConfigUntouched() {
        var config = AppConfig()
        config.meetingSummaryBackend = "chatgpt"

        let resolved = config.resolvedForTextGeneration()

        #expect(resolved.meetingSummaryBackend == "chatgpt")
    }

    @Test("resolvedForTextGeneration maps an OpenAI endpoint to the openai backend")
    func mapsOpenAIEndpoint() {
        let secretRef = ModelSecretsStore.save("sk-test-openai")
        let model = ConfiguredModel(
            displayName: "OpenAI",
            role: .textGeneration,
            provider: .openAICompatible,
            modelID: "gpt-5.4-mini",
            endpointURL: "https://api.openai.com/v1/chat/completions",
            keychainRef: secretRef
        )
        var config = AppConfig()
        config.configuredModels = [model]
        config.defaultModelIDs[ModelRole.textGeneration.rawValue] = model.id

        let resolved = config.resolvedForTextGeneration()

        #expect(resolved.meetingSummaryBackend == MeetingSummaryBackendOption.openAI.backend)
        #expect(resolved.openAIAPIKey == "sk-test-openai")
        #expect(resolved.openAIModel == "gpt-5.4-mini")

        ModelSecretsStore.delete(ref: secretRef)
    }

    @Test("resolvedForTextGeneration distinguishes OpenRouter from a generic custom endpoint by host")
    func mapsOpenRouterByHost() {
        let secretRef = ModelSecretsStore.save("sk-or-test")
        let model = ConfiguredModel(
            displayName: "OpenRouter",
            role: .textGeneration,
            provider: .openAICompatible,
            modelID: "openrouter/free",
            endpointURL: "https://openrouter.ai/api/v1/chat/completions",
            keychainRef: secretRef
        )
        var config = AppConfig()
        config.configuredModels = [model]
        config.defaultModelIDs[ModelRole.textGeneration.rawValue] = model.id

        let resolved = config.resolvedForTextGeneration()

        #expect(resolved.meetingSummaryBackend == MeetingSummaryBackendOption.openRouter.backend)
        #expect(resolved.openRouterAPIKey == "sk-or-test")
        #expect(resolved.openRouterModel == "openrouter/free")

        ModelSecretsStore.delete(ref: secretRef)
    }

    @Test("resolvedForTextGeneration routes an unrecognized OpenAI-compatible host to custom_llm")
    func mapsUnknownHostToCustomLLM() {
        let secretRef = ModelSecretsStore.save("sk-custom")
        let model = ConfiguredModel(
            displayName: "My Endpoint",
            role: .textGeneration,
            provider: .openAICompatible,
            modelID: "my-model",
            endpointURL: "http://localhost:8080/v1/chat/completions",
            keychainRef: secretRef
        )
        var config = AppConfig()
        config.configuredModels = [model]
        config.defaultModelIDs[ModelRole.textGeneration.rawValue] = model.id

        let resolved = config.resolvedForTextGeneration()

        #expect(resolved.meetingSummaryBackend == MeetingSummaryBackendOption.customLLM.backend)
        #expect(resolved.customLLMAPIKey == "sk-custom")
        #expect(resolved.customLLMModel == "my-model")
        #expect(resolved.customLLMFormat == CustomLLMFormat.openAI.rawValue)

        ModelSecretsStore.delete(ref: secretRef)
    }

    @Test("resolvedForTextGeneration maps an Anthropic-compatible endpoint")
    func mapsAnthropicCompatible() {
        let secretRef = ModelSecretsStore.save("sk-ant-test")
        let model = ConfiguredModel(
            displayName: "Claude",
            role: .textGeneration,
            provider: .anthropicCompatible,
            modelID: "claude-3-5-sonnet-20241022",
            endpointURL: "https://api.anthropic.com/v1/messages",
            keychainRef: secretRef
        )
        var config = AppConfig()
        config.configuredModels = [model]
        config.defaultModelIDs[ModelRole.textGeneration.rawValue] = model.id

        let resolved = config.resolvedForTextGeneration()

        #expect(resolved.meetingSummaryBackend == MeetingSummaryBackendOption.customLLM.backend)
        #expect(resolved.customLLMFormat == CustomLLMFormat.anthropic.rawValue)
        #expect(resolved.customLLMAPIKey == "sk-ant-test")

        ModelSecretsStore.delete(ref: secretRef)
    }

    @Test("resolvedForTextGeneration maps Ollama without needing a secret")
    func mapsOllamaWithoutSecret() {
        let model = ConfiguredModel(
            displayName: "Ollama",
            role: .textGeneration,
            provider: .ollama,
            modelID: "qwen3.5",
            endpointURL: "http://localhost:11434"
        )
        var config = AppConfig()
        config.configuredModels = [model]
        config.defaultModelIDs[ModelRole.textGeneration.rawValue] = model.id

        let resolved = config.resolvedForTextGeneration()

        #expect(resolved.meetingSummaryBackend == MeetingSummaryBackendOption.ollama.backend)
        #expect(resolved.ollamaURL == "http://localhost:11434")
        #expect(resolved.ollamaModel == "qwen3.5")
    }

    @Test("resolvedForTextGeneration ignores a disabled default model")
    func ignoresDisabledModel() {
        var model = ConfiguredModel(
            displayName: "Disabled OpenAI",
            role: .textGeneration,
            provider: .openAICompatible,
            modelID: "gpt-5.4-mini",
            endpointURL: "https://api.openai.com/v1/chat/completions"
        )
        model.isEnabled = false
        var config = AppConfig()
        config.meetingSummaryBackend = "chatgpt"
        config.configuredModels = [model]
        config.defaultModelIDs[ModelRole.textGeneration.rawValue] = model.id

        let resolved = config.resolvedForTextGeneration()

        // The disabled model must not leak its (nonexistent) secret in; the
        // legacy backend stays whatever it already was.
        #expect(resolved.meetingSummaryBackend == "chatgpt")
        #expect(resolved.openAIAPIKey.isEmpty)
    }
}

@Suite("ModelSecretsStore")
struct ModelSecretsStoreTests {

    @Test("save then read round-trips the secret")
    func saveThenReadRoundTrips() {
        let ref = ModelSecretsStore.save("super-secret-key")
        defer { ModelSecretsStore.delete(ref: ref) }

        #expect(ModelSecretsStore.read(ref: ref) == "super-secret-key")
    }

    @Test("update overwrites the secret at an existing reference")
    func updateOverwrites() {
        let ref = ModelSecretsStore.save("old-key")
        defer { ModelSecretsStore.delete(ref: ref) }

        ModelSecretsStore.update(ref: ref, secret: "new-key")

        #expect(ModelSecretsStore.read(ref: ref) == "new-key")
    }

    @Test("delete removes the secret")
    func deleteRemoves() {
        let ref = ModelSecretsStore.save("to-be-deleted")
        ModelSecretsStore.delete(ref: ref)

        #expect(ModelSecretsStore.read(ref: ref) == nil)
    }

    @Test("read returns nil for a reference that was never saved")
    func readUnknownRefReturnsNil() {
        #expect(ModelSecretsStore.read(ref: UUID().uuidString) == nil)
    }

    @Test("read returns nil for a nil reference")
    func readNilRefReturnsNil() {
        #expect(ModelSecretsStore.read(ref: nil) == nil)
    }
}
