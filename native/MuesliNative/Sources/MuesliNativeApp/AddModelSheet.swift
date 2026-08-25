import AppKit
import SwiftUI
import MuesliCore

/// "Add Model" wizard (task 8.2.3): role → provider → provider-specific
/// fields → optional connection test → save. Bundled/local downloadable
/// models (Parakeet, Whisper, the post-processor GGUFs) keep their existing
/// download-progress cards on the Speech/Cleanup tabs — this sheet is for
/// connecting something the app doesn't ship: your own endpoint, key, or
/// account.
struct AddModelSheet: View {
    let controller: MuesliController

    @Environment(\.dismiss) private var dismiss

    @State private var role: ModelRole
    @State private var provider: ModelProvider
    @State private var displayName: String = ""
    @State private var modelID: String = ""
    @State private var endpointURL: String = ""
    @State private var secret: String = ""
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var showValidationError = false

    init(controller: MuesliController, initialRole: ModelRole) {
        self.controller = controller
        _role = State(initialValue: initialRole)
        _provider = State(initialValue: Self.availableProviders(for: initialRole).first ?? .openAICompatible)
    }

    static func availableProviders(for role: ModelRole) -> [ModelProvider] {
        switch role {
        case .textGeneration:
            return [.chatGPTOAuth, .openAICompatible, .anthropicCompatible, .ollama, .lmStudio]
        case .transcription, .cleanup:
            // Bundled local models are downloaded from their own tab (they
            // need download-progress UI, not a form); this sheet only adds
            // custom remote endpoints for these two roles.
            return [.openAICompatible]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(MuesliTheme.surfaceBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
                    roleSection
                    providerSection
                    parameterFields
                    testConnectionSection
                }
                .padding(MuesliTheme.spacing20)
            }
            Divider().background(MuesliTheme.surfaceBorder)
            footer
        }
        .frame(width: 460, height: 560)
        .background(MuesliTheme.backgroundDeep)
        .onChange(of: role) { _, newRole in
            provider = Self.availableProviders(for: newRole).first ?? .openAICompatible
            resetFields()
        }
        .onChange(of: provider) { _, _ in
            resetFields()
        }
    }

    private func resetFields() {
        displayName = ""
        modelID = ""
        endpointURL = Self.defaultEndpoint(for: provider)
        secret = ""
        testMessage = nil
        testSucceeded = false
        showValidationError = false
    }

    private static func defaultEndpoint(for provider: ModelProvider) -> String {
        switch provider {
        case .ollama: return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234"
        default: return ""
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(tr("Add Model", "Добавить модель"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(MuesliTheme.backgroundBase))
            }
            .buttonStyle(.plain)
        }
        .padding(MuesliTheme.spacing20)
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(tr("Role", "Роль"))
            Picker("", selection: $role) {
                ForEach(ModelRole.allCases, id: \.self) { role in
                    Text(role.title).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(tr("Provider", "Провайдер"))
            Picker("", selection: $provider) {
                ForEach(Self.availableProviders(for: role), id: \.self) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var parameterFields: some View {
        switch provider {
        case .chatGPTOAuth:
            chatGPTFields
        case .ollama, .lmStudio:
            VStack(alignment: .leading, spacing: 14) {
                textField(label: tr("Server URL", "URL сервера"), text: $endpointURL, placeholder: Self.defaultEndpoint(for: provider))
                textField(label: tr("Model", "Модель"), text: $modelID, placeholder: provider == .ollama ? "qwen3.5" : tr("loaded model name", "имя загруженной модели"))
                textField(label: tr("Name (optional)", "Название (необязательно)"), text: $displayName, placeholder: provider.title)
            }
        case .openAICompatible, .anthropicCompatible:
            VStack(alignment: .leading, spacing: 14) {
                textField(
                    label: tr("Endpoint URL", "URL эндпоинта"),
                    text: $endpointURL,
                    placeholder: provider == .anthropicCompatible ? "https://api.anthropic.com/v1/messages" : "https://api.openai.com/v1/chat/completions"
                )
                secureField(label: tr("API Key", "API-ключ"), text: $secret, placeholder: "sk-...")
                textField(label: tr("Model ID", "ID модели"), text: $modelID, placeholder: provider == .anthropicCompatible ? "claude-3-5-sonnet-20241022" : "gpt-5.4-mini")
                textField(label: tr("Name (optional)", "Название (необязательно)"), text: $displayName, placeholder: tr("My endpoint", "Мой эндпоинт"))
            }
        case .bundledLocal, .localGGUF:
            Text(tr("This kind of model downloads from its own tab — Speech or Cleanup.", "Такая модель скачивается на своей вкладке — «Распознавание» или «Очистка»."))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
        }
    }

    private var chatGPTFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.appState.isChatGPTAuthenticated {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MuesliTheme.success)
                    Text(tr("Signed in to ChatGPT.", "Выполнен вход в ChatGPT."))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
            } else {
                Text(tr("Sign in with your ChatGPT subscription to use it for meeting summaries and chat.", "Войдите со своей подпиской ChatGPT, чтобы использовать её для сводок встреч и чата."))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                Button(tr("Sign in with ChatGPT…", "Войти через ChatGPT…")) {
                    Task { _ = await controller.signInWithChatGPT(selectMeetingSummaryBackend: false) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, MuesliTheme.spacing16)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(MuesliTheme.accent)
                .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var testConnectionSection: some View {
        if provider != .chatGPTOAuth, provider != .bundledLocal, provider != .localGGUF {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "bolt.horizontal.circle")
                        }
                        Text(tr("Test Connection", "Проверить подключение"))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 6)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isTesting || endpointURL.trimmingCharacters(in: .whitespaces).isEmpty)

                if let testMessage {
                    HStack(spacing: 6) {
                        Image(systemName: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testSucceeded ? MuesliTheme.success : MuesliTheme.recording)
                        Text(testMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(MuesliTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if showValidationError {
                Text(tr("Fill in the required fields.", "Заполните обязательные поля."))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.recording)
            }
            Spacer()
            Button(tr("Cancel", "Отмена")) {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, MuesliTheme.spacing8)

            Button(tr("Add", "Добавить")) {
                save()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(MuesliTheme.accent)
            .clipShape(Capsule())
            .disabled(provider == .chatGPTOAuth && !controller.appState.isChatGPTAuthenticated)
        }
        .padding(MuesliTheme.spacing20)
    }

    // MARK: - Actions

    private func testConnection() async {
        isTesting = true
        testMessage = nil
        let error = await controller.testConfiguredModelConnection(
            provider: provider,
            endpointURL: endpointURL.trimmingCharacters(in: .whitespaces),
            modelID: modelID.trimmingCharacters(in: .whitespaces),
            secret: secret.isEmpty ? nil : secret
        )
        isTesting = false
        if let error {
            testSucceeded = false
            testMessage = error
        } else {
            testSucceeded = true
            testMessage = tr("Connected.", "Подключение установлено.")
        }
    }

    private func save() {
        switch provider {
        case .chatGPTOAuth:
            guard controller.appState.isChatGPTAuthenticated else { return }
            controller.addConfiguredModel(
                displayName: displayName.isEmpty ? "ChatGPT" : displayName,
                role: role,
                provider: provider,
                modelID: modelID
            )
        case .ollama, .lmStudio:
            let url = endpointURL.trimmingCharacters(in: .whitespaces)
            let model = modelID.trimmingCharacters(in: .whitespaces)
            guard !url.isEmpty, !model.isEmpty else {
                showValidationError = true
                return
            }
            controller.addConfiguredModel(
                displayName: displayName.isEmpty ? provider.title : displayName,
                role: role,
                provider: provider,
                modelID: model,
                endpointURL: url
            )
        case .openAICompatible, .anthropicCompatible:
            let url = endpointURL.trimmingCharacters(in: .whitespaces)
            let model = modelID.trimmingCharacters(in: .whitespaces)
            guard !url.isEmpty, !model.isEmpty else {
                showValidationError = true
                return
            }
            controller.addConfiguredModel(
                displayName: displayName.isEmpty ? (URL(string: url)?.host ?? provider.title) : displayName,
                role: role,
                provider: provider,
                modelID: model,
                endpointURL: url,
                secret: secret.isEmpty ? nil : secret
            )
        case .bundledLocal, .localGGUF:
            return
        }
        dismiss()
    }

    // MARK: - Field helpers

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textSecondary)
    }

    private func textField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            PastableTextField(text: text.wrappedValue, placeholder: placeholder, onChange: { text.wrappedValue = $0 })
                .frame(height: 30)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall).fill(MuesliTheme.backgroundBase))
                .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
        }
    }

    private func secureField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            PastableSecureField(text: text.wrappedValue, placeholder: placeholder, onChange: { text.wrappedValue = $0 })
                .frame(height: 30)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall).fill(MuesliTheme.backgroundBase))
                .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
        }
    }
}
