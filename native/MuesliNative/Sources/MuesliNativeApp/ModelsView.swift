import SwiftUI
import MuesliCore

/// The Models screen used to be four tabs keyed by this enum; per direct
/// feedback ("часть будет не шибко-то удобно" — managing one connected
/// model across two separate role tabs was busywork) it's now one
/// continuous scrollable page (see `ModelsView.body`). This only survives
/// as a set of `ScrollViewReader` anchor ids, so `HomeView.swift`'s
/// existing "jump to Models → Cleanup" deep links still land in the right
/// place — they scroll there now instead of switching a selected tab.
enum ModelsTab: String, CaseIterable, Identifiable {
    case speech
    case text
    case cleanup
    case catalog

    var id: String { rawValue }
}

struct ModelsView: View {
    let appState: AppState
    let controller: MuesliController

    @State private var showAddModelSheet = false
    @State private var nemotron35UpdateAvailable = false
    @State private var downloadingModels: Set<String> = []
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadedModels: Set<String> = []
    @State private var downloadTasks: [String: Task<Void, Never>] = [:]
    @State private var modelToDelete: BackendOption?
    @State private var selectedParakeetModel: String
    @State private var selectedWhisperModel: String
    @State private var showExperimental: Bool

    // Post-processor state
    @State private var downloadingPostProcModels: Set<String> = []
    @State private var downloadProgressPostProc: [String: Double] = [:]
    @State private var downloadedPostProcModels: Set<String> = []
    @State private var downloadTasksPostProc: [String: Task<Void, Never>] = [:]
    @State private var postProcModelToDelete: PostProcessorOption?
    @State private var isEditingSystemPrompt = false
    @State private var editedSystemPrompt = ""

    // Local summarization model (downloadable on-device LLM) state
    @State private var downloadingSummaryModels: Set<String> = []
    @State private var downloadProgressSummary: [String: Double] = [:]
    @State private var downloadedSummaryModels: Set<String> = []
    @State private var downloadTasksSummary: [String: Task<Void, Never>] = [:]
    @State private var summaryModelToDelete: LocalSummaryModelOption?

    init(appState: AppState, controller: MuesliController) {
        self.appState = appState
        self.controller = controller

        let active = appState.selectedBackend
        _selectedParakeetModel = State(initialValue: BackendOption.parakeetFamily.contains(active) ? active.model : BackendOption.parakeetMultilingual.model)
        _selectedWhisperModel = State(initialValue: BackendOption.whisperFamily.contains(active) ? active.model : BackendOption.whisperSmall.model)
        _showExperimental = State(initialValue: false)
    }

    var body: some View {
        // One continuous scrollable page instead of four tabs — per direct
        // feedback: a connected cloud model already serves both text
        // generation AND cleanup at once (`ConfiguredModel.roles`), so
        // switching tabs to manage what's really ONE thing was busywork.
        // `ModelsTab` stays around as a scroll anchor (`.id(_:)` below) so
        // the existing "jump here" deep links from HomeView.swift still
        // land in the right place — they just scroll now instead of
        // switching a selected tab.
        //
        // Per direct feedback ("визуально цветом отделим что к чему
        // относится") each section is wrapped in a tinted `sectionGroup`
        // matching its header's accent color, and ("кнопку добавить
        // облачную модель закрепить при скролле") the connect-cloud-model
        // action lives in a fixed top-right overlay instead of scrolling
        // away with the page.
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                        sectionGroup(color: Color(hex: 0x007AFF)) {
                            modelsSectionHeader(
                                title: tr("Speech recognition", "Распознавание речи"),
                                icon: "waveform",
                                color: Color(hex: 0x007AFF)
                            )
                            speechTabContent
                        }
                        .id(ModelsTab.speech)

                        sectionGroup(color: Color(hex: 0xAF52DE)) {
                            modelsSectionHeader(
                                title: tr("Text & cleanup", "Текстовые и очистка"),
                                icon: "text.bubble",
                                color: Color(hex: 0xAF52DE),
                                subtitle: tr("One connected model can handle both — turn each on for whatever it should do.", "Одна подключённая модель может делать и то, и другое — включи то, для чего она нужна.")
                            )
                            textAndCleanupContent
                        }
                        .id(ModelsTab.text)

                        sectionGroup(color: Color(hex: 0x00C7BE)) {
                            // Tapping the section HEADER opens the same
                            // connect sheet as the pinned top-right button —
                            // a second obvious entry point right where this
                            // "add more" section already lives.
                            Button {
                                showAddModelSheet = true
                            } label: {
                                modelsSectionHeader(
                                    title: tr("Add more", "Добавить ещё"),
                                    icon: "square.grid.2x2",
                                    color: Color(hex: 0x00C7BE)
                                )
                            }
                            .buttonStyle(.plain)
                            addMoreSectionContent
                        }
                        .id(ModelsTab.catalog)
                    }
                    .padding(MuesliTheme.spacing24)
                    .padding(.top, MuesliTheme.spacing24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    let anchor = appState.modelsTab == .cleanup ? ModelsTab.text : appState.modelsTab
                    DispatchQueue.main.async {
                        scrollProxy.scrollTo(anchor, anchor: .top)
                    }
                }
            }

            connectCloudModelButton
                .padding(.top, MuesliTheme.spacing20)
                .padding(.trailing, MuesliTheme.spacing24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showAddModelSheet) {
            AddModelSheet(controller: controller)
        }
        .onAppear {
            checkDownloadedModels()
            checkDownloadedPostProcModels()
            checkDownloadedSummaryModels()
            syncSelectionsFromActiveBackend()
            checkNemotron35Update()
        }
        .onChange(of: appState.selectedBackend.model) { _, _ in
            syncSelectionsFromActiveBackend()
        }
        .alert(
            tr("Delete \"\(modelToDelete?.label ?? "")\"?", "Удалить «\(modelToDelete?.label ?? "")»?"),
            isPresented: Binding(
                get: { modelToDelete != nil },
                set: { if !$0 { modelToDelete = nil } }
            )
        ) {
            Button(tr("Cancel", "Отмена"), role: .cancel) {
                modelToDelete = nil
            }
            Button(tr("Delete", "Удалить"), role: .destructive) {
                guard let option = modelToDelete else { return }
                deleteModel(option)
                modelToDelete = nil
            }
        } message: {
            Text(tr("The downloaded model files will be removed from this Mac. You can download the model again later.", "Файлы скачанной модели будут удалены с этого Mac. Позже модель можно скачать снова."))
        }
        .alert(
            tr("Delete \"\(postProcModelToDelete?.label ?? "")\"?", "Удалить «\(postProcModelToDelete?.label ?? "")»?"),
            isPresented: Binding(
                get: { postProcModelToDelete != nil },
                set: { if !$0 { postProcModelToDelete = nil } }
            )
        ) {
            Button(tr("Cancel", "Отмена"), role: .cancel) {
                postProcModelToDelete = nil
            }
            Button(tr("Delete", "Удалить"), role: .destructive) {
                guard let option = postProcModelToDelete else { return }
                deletePostProcModel(option)
                postProcModelToDelete = nil
            }
        } message: {
            Text(tr("The downloaded model files will be removed from this Mac. You can download the model again later.", "Файлы скачанной модели будут удалены с этого Mac. Позже модель можно скачать снова."))
        }
        .alert(
            tr("Delete \"\(summaryModelToDelete?.label ?? "")\"?", "Удалить «\(summaryModelToDelete?.label ?? "")»?"),
            isPresented: Binding(
                get: { summaryModelToDelete != nil },
                set: { if !$0 { summaryModelToDelete = nil } }
            )
        ) {
            Button(tr("Cancel", "Отмена"), role: .cancel) {
                summaryModelToDelete = nil
            }
            Button(tr("Delete", "Удалить"), role: .destructive) {
                guard let option = summaryModelToDelete else { return }
                deleteSummaryModel(option)
                summaryModelToDelete = nil
            }
        } message: {
            Text(tr("The downloaded model files will be removed from this Mac. You can download the model again later.", "Файлы скачанной модели будут удалены с этого Mac. Позже модель можно скачать снова."))
        }
    }

    // MARK: - Section header (one continuous page instead of tabs)

    /// Pinned top-right action — stays in place while the page scrolls
    /// (see the `ZStack(alignment: .topTrailing)` in `body`), so it's
    /// always reachable regardless of which section is in view.
    private var connectCloudModelButton: some View {
        Button {
            showAddModelSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text(tr("Connect a cloud model", "Подключить облачную модель"))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, 10)
            .background(MuesliTheme.accent)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// Separates one page section from the next with a thin accent rule in
    /// its header's color, instead of a full boxed background — a boxed
    /// tint around cards that already have their own borders (and an
    /// accent-glow border on the active one) read as clutter, nested boxes
    /// inside boxes ("колхозно"). A simple color-coded rule is enough to
    /// tell sections apart without competing with the cards themselves.
    private func sectionGroup<Content: View>(
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: MuesliTheme.spacing16) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color.opacity(0.55))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                content()
            }
        }
    }

    private func modelsSectionHeader(
        title: String,
        icon: String,
        color: Color,
        subtitle: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.leading, 36)
            }
        }
    }

    // Per direct feedback ("непонятно первое — две в ряду, следующее по
    // одной") — a 2-column grid here while every other section on the page
    // is a single column made the layout read as inconsistent/random.
    // Back to one card per row, matching Text & cleanup and Add more.
    @ViewBuilder
    private var speechTabContent: some View {
        VStack(spacing: MuesliTheme.spacing12) {
            familyCard(
                title: tr("Parakeet Family", "Семейство Parakeet"),
                defaultBadge: tr("Default: v3", "По умолчанию: v3"),
                logo: "nvidia-logo",
                selection: $selectedParakeetModel,
                options: BackendOption.parakeetFamily
            )

            familyCard(
                title: "Whisper",
                defaultBadge: tr("Default: Small", "По умолчанию: Small"),
                logo: "openai-logo",
                selection: $selectedWhisperModel,
                options: BackendOption.whisperFamily
            )

            modelCard(option: .cohereTranscribe, logo: "cohere-logo")
            modelCard(option: .nemotron35Multilingual, logo: "nvidia-logo")
        }

        experimentalSection
    }

    @ViewBuilder
    private var addMoreSectionContent: some View {
        if !BackendOption.comingSoon.isEmpty {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text(tr("COMING SOON", "СКОРО"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.leading, 2)

                VStack(spacing: MuesliTheme.spacing12) {
                    ForEach(BackendOption.comingSoon, id: \.model) { option in
                        comingSoonCard(option: option)
                    }
                }
            }
        }
    }

    // MARK: - Text & cleanup (merged — a connected cloud model serves both)

    /// Union of both roles' connected models, deduplicated by id. A cloud
    /// model's `roles` set already contains both `.textGeneration` and
    /// `.cleanup` (see `ModelRegistry.swift`), so it naturally appears once
    /// here with both capability chips instead of showing up as two
    /// separate cards across two tabs.
    private var combinedTextAndCleanupModels: [ConfiguredModel] {
        var seen = Set<String>()
        var merged: [ConfiguredModel] = []
        for model in controller.allConfiguredModels(role: .textGeneration) + controller.allConfiguredModels(role: .cleanup) {
            if seen.insert(model.id).inserted {
                merged.append(model)
            }
        }
        return merged
    }

    @ViewBuilder
    private var textAndCleanupContent: some View {
        // The prominent "connect a cloud model" action now lives in the
        // pinned top-right overlay (`connectCloudModelButton` in `body`) —
        // no in-line copy of it here anymore.
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            let models = combinedTextAndCleanupModels

            if models.isEmpty {
                emptyTextModelsCard
            } else {
                VStack(spacing: MuesliTheme.spacing12) {
                    ForEach(models) { model in
                        combinedConfiguredModelCard(model)
                    }
                }
            }
        }

        localSummarySection
        postProcessorSection
    }

    private var emptyTextModelsCard: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(tr("No cloud model connected", "Нет подключённой облачной модели"))
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textPrimary)
            Text(tr("Connect ChatGPT, an API key, or your own endpoint to generate meeting summaries and clean up dictation.", "Подключите ChatGPT, API-ключ или свой эндпоинт, чтобы генерировать сводки встреч и очищать диктовку."))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    /// One card, both capability chips — replaces the old per-role
    /// `configuredModelCard`, which needed the SAME model shown on two
    /// different tabs to manage what's really one connection. Each chip
    /// only appears if `model.roles` actually supports that job (a
    /// bundled cleanup-only GGUF never gets a "meeting summaries" chip).
    private func combinedConfiguredModelCard(_ model: ConfiguredModel) -> some View {
        let isDefaultText = model.id == controller.defaultConfiguredModelID(role: .textGeneration)
        let isDefaultCleanup = model.id == controller.activeCleanupModelID()

        return VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                Image(systemName: model.provider == .chatGPTOAuth ? "sparkles" : (model.provider.isLocal ? "cpu" : "icloud"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(MuesliTheme.accentSubtle))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        Text(model.provider.isLocal ? tr("Local", "Локальная") : tr("Cloud", "Облачная"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    Text(model.modelID.isEmpty ? model.provider.title : model.modelID)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if !model.isEnabled {
                    Text(tr("Disabled", "Отключена"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            HStack(spacing: MuesliTheme.spacing8) {
                if model.roles.contains(.textGeneration) {
                    roleChip(tr("Meeting summaries", "Сводки встреч"), isOn: isDefaultText) {
                        controller.setDefaultConfiguredModel(id: model.id, role: .textGeneration)
                    }
                }
                if model.roles.contains(.cleanup) {
                    roleChip(tr("Dictation cleanup", "Очистка диктовки"), isOn: isDefaultCleanup) {
                        controller.selectCleanupModel(id: model.id)
                    }
                }
            }

            if model.provider != .bundledLocal, model.provider != .localGGUF {
                HStack(spacing: MuesliTheme.spacing8) {
                    modelsTabActionButton(model.isEnabled ? tr("Disable", "Отключить") : tr("Enable", "Включить")) {
                        controller.setConfiguredModelEnabled(id: model.id, enabled: !model.isEnabled)
                    }
                    Button {
                        controller.removeConfiguredModel(id: model.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder((isDefaultText || isDefaultCleanup) ? MuesliTheme.accent.opacity(0.5) : MuesliTheme.surfaceBorder, lineWidth: (isDefaultText || isDefaultCleanup) ? 1.5 : 1)
        )
        .opacity(model.isEnabled ? 1 : 0.6)
    }

    /// A capability toggle-chip: tapping an OFF chip makes this model the
    /// active one for that job (the previously-active model's own chip
    /// simply stops reading as ON, since both read from the same shared
    /// default). Tapping an already-ON chip is a harmless no-op — there's
    /// always exactly one active model per job, so there's no "off" state
    /// to switch to.
    private func roleChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(isOn ? MuesliTheme.accent : MuesliTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isOn ? MuesliTheme.accentSubtle : MuesliTheme.surfacePrimary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isOn ? MuesliTheme.accent.opacity(0.4) : MuesliTheme.surfaceBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func modelsTabActionButton(_ title: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(accent ? MuesliTheme.accent : MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 4)
            .background(accent ? MuesliTheme.accentSubtle : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
    }

    // MARK: - Local summarization model (on-device meeting notes)

    private var localSummarySection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(tr("LOCAL SUMMARIZATION", "ЛОКАЛЬНАЯ СУММАРИЗАЦИЯ"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.leading, 2)

                Text(tr("Optional on-device LLM for meeting notes — runs fully offline, no cloud and no tokens. After downloading, choose \"Локальная (T-lite)\" as the summary backend in Settings.", "Необязательная локальная LLM для заметок встреч — работает полностью офлайн, без облака и токенов. После скачивания выберите «Локальная (T-lite)» как бэкенд суммаризации в Настройках."))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.leading, 2)
            }
            .padding(.top, MuesliTheme.spacing8)

            VStack(spacing: MuesliTheme.spacing12) {
                ForEach(LocalSummaryModelOption.all) { option in
                    localSummaryModelCard(option)
                }
            }
        }
    }

    private func localSummaryModelCard(_ option: LocalSummaryModelOption) -> some View {
        let isDownloaded = downloadedSummaryModels.contains(option.id)
        let isDownloading = downloadingSummaryModels.contains(option.id)
        let progress = downloadProgressSummary[option.id] ?? 0
        let isActive = isDownloaded
            && appState.config.meetingSummaryBackend.lowercased() == MeetingSummaryBackendOption.localGguf.backend

        return VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                brandLogo("qwen-logo")
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Text(option.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        Text(option.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }

                    Text(option.description)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                if isActive {
                    Text(tr("Active", "Активна"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isDownloaded {
                    Text(tr("Downloaded", "Скачано"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(MuesliTheme.accent)
                    Text(tr("\(Int(progress * 100))% downloading...", "Скачивание… \(Int(progress * 100))%"))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
            }

            HStack(spacing: MuesliTheme.spacing8) {
                if isDownloading {
                    Button(tr("Cancel", "Отмена")) {
                        cancelSummaryDownload(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                } else if isDownloaded {
                    if !isActive {
                        Button(tr("Use for summaries", "Использовать для заметок")) {
                            controller.selectMeetingSummaryBackend(.localGguf)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.accent)
                        .padding(.horizontal, MuesliTheme.spacing12)
                        .padding(.vertical, 4)
                        .background(MuesliTheme.accentSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }

                    Button {
                        summaryModelToDelete = option
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.6))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(tr("Download", "Скачать")) {
                        startSummaryDownload(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(isActive ? MuesliTheme.accent.opacity(0.5) : MuesliTheme.surfaceBorder, lineWidth: isActive ? 1.5 : 1)
        )
    }

    private var experimentalSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Button {
                showExperimental.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing12) {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                        HStack(spacing: 6) {
                            Image(systemName: showExperimental ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MuesliTheme.textTertiary)

                            Text(tr("Experimental", "Экспериментальные"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MuesliTheme.textSecondary)
                        }

                        Text(tr("SenseVoice, Qwen, Indic ASR, and legacy streaming backends. Hidden by default because these are still slower and less polished.", "SenseVoice, Qwen, Indic ASR и устаревшие потоковые движки. Скрыты по умолчанию: они пока медленнее и менее отточены."))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .opacity(0.8)
                    }

                    Spacer()

                    Text("IYKYK")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showExperimental {
                VStack(spacing: MuesliTheme.spacing12) {
                    ForEach(BackendOption.experimental, id: \.model) { option in
                        modelCard(option: option, logo: logoForBackend(option))
                    }
                }
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var cohereLanguageSelection: Binding<CohereTranscribeLanguage> {
        Binding(
            get: { appState.config.resolvedCohereLanguage },
            set: { controller.selectCohereLanguage($0) }
        )
    }

    private var indicASRLanguageSelection: Binding<IndicASRLanguage> {
        Binding(
            get: { appState.config.resolvedIndicASRLanguage },
            set: { controller.selectIndicASRLanguage($0) }
        )
    }

    private var nemotron35LanguageSelection: Binding<Nemotron35Language> {
        Binding(
            get: { appState.config.resolvedNemotron35Language },
            set: { language in
                Task { await controller.setNemotron35Language(language) }
            }
        )
    }

    private var postProcessorSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(tr("POST-PROCESSING", "ПОСТОБРАБОТКА"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.leading, 2)

                Text(tr("Optional LLM cleanup layer applied after transcription. Removes filler words, formats spoken lists, and corrects common dictation errors.", "Необязательный слой LLM-очистки после транскрипции. Убирает слова-паразиты, форматирует произнесённые списки и исправляет типичные ошибки диктовки."))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.leading, 2)
            }
            .padding(.top, MuesliTheme.spacing8)

            VStack(spacing: MuesliTheme.spacing12) {
                ForEach(PostProcessorOption.all) { option in
                    postProcModelCard(option)
                }
            }

            systemPromptCard
        }
    }

    private func postProcModelCard(_ option: PostProcessorOption) -> some View {
        let isDownloaded = downloadedPostProcModels.contains(option.id)
        // Source of truth is the shared cleanup selection, not the
        // local-only `activePostProcessor` mirror — otherwise a bundled
        // card here can still read "Active" after the user switches
        // cleanup to a connected cloud model above.
        let isActive = controller.activeCleanupModelID() == MuesliController.bundledCleanupID(option) && isDownloaded
        let isDownloading = downloadingPostProcModels.contains(option.id)
        let progress = downloadProgressPostProc[option.id] ?? 0

        return VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                brandLogo("qwen-logo")
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Text(option.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        Text(option.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }

                    Text(option.description)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                if isActive {
                    Text(tr("Active", "Активна"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isDownloaded {
                    Text(tr("Downloaded", "Скачано"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(MuesliTheme.accent)
                    Text(tr("\(Int(progress * 100))% downloading...", "Скачивание… \(Int(progress * 100))%"))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
            }

            HStack(spacing: MuesliTheme.spacing8) {
                if isDownloading {
                    Button(tr("Cancel", "Отмена")) {
                        cancelPostProcDownload(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                } else if isDownloaded {
                    if !isActive {
                        Button(tr("Set Active", "Сделать активной")) {
                            controller.selectCleanupModel(id: MuesliController.bundledCleanupID(option))
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.accent)
                        .padding(.horizontal, MuesliTheme.spacing12)
                        .padding(.vertical, 4)
                        .background(MuesliTheme.accentSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }

                    Button {
                        postProcModelToDelete = option
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.6))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(tr("Download", "Скачать")) {
                        startPostProcDownload(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(isActive ? MuesliTheme.accent.opacity(0.5) : MuesliTheme.surfaceBorder, lineWidth: isActive ? 1.5 : 1)
        )
    }

    private var systemPromptCard: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    Text(tr("System Prompt", "Системный промпт"))
                        .font(MuesliTheme.headline())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("Controls how the model cleans up transcriptions. Applies to the active post-processor model.", "Определяет, как модель очищает транскрипции. Применяется к активной модели постобработки."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                Spacer()
                if !isEditingSystemPrompt {
                    Button(tr("Edit", "Изменить")) {
                        editedSystemPrompt = appState.config.postProcessorSystemPrompt
                        isEditingSystemPrompt = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
            }

            if isEditingSystemPrompt {
                TextEditor(text: $editedSystemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )

                HStack(spacing: MuesliTheme.spacing8) {
                    Button(tr("Save", "Сохранить")) {
                        controller.updatePostProcessorSystemPrompt(editedSystemPrompt)
                        isEditingSystemPrompt = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                    Button(tr("Cancel", "Отмена")) {
                        isEditingSystemPrompt = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                    Button(tr("Reset to Default", "Сбросить по умолчанию")) {
                        editedSystemPrompt = PostProcessorOption.defaultSystemPrompt
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
            } else {
                Text(appState.config.postProcessorSystemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(6)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    // Per direct feedback ("надо попробовать компактнее, зачем всё это
    // писать... пусть будет как в мини-табличке, и в серой обводке всё то,
    // что входит, к одному — перед обводкой заголовок") — dropped the
    // prose description entirely, moved the title/badges above the gray
    // box instead of inside it, and collapsed variant + size + actions
    // into one compact table row inside the box.
    private func familyCard(
        title: String,
        defaultBadge: String,
        logo: String? = nil,
        selection: Binding<String>,
        options: [BackendOption]
    ) -> some View {
        let selectedOption = options.first(where: { $0.model == selection.wrappedValue }) ?? options[0]
        let isActive = appState.selectedBackend == selectedOption
        let isDownloaded = downloadedModels.contains(selectedOption.model)
        let isDownloading = downloadingModels.contains(selectedOption.model)
        let progress = downloadProgress[selectedOption.model] ?? 0

        return VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing8) {
                brandLogo(logo)
                Text(title)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(defaultBadge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MuesliTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(Capsule())

                Spacer()

                familyStatusBadge(isActive: isActive, isDownloaded: isDownloaded)
            }

            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                    Text(tr("Variant", "Вариант"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)

                    Picker("", selection: selection) {
                        ForEach(options, id: \.model) { option in
                            Text(option.label).tag(option.model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 170, alignment: .leading)

                    Text(selectedOption.sizeLabel)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)

                    Spacer()

                    actionButtons(for: selectedOption, isActive: isActive, isDownloaded: isDownloaded, isDownloading: isDownloading)
                }

                if isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .tint(MuesliTheme.accent)
                        Text(tr("\(Int(progress * 100))% downloading...", "Скачивание… \(Int(progress * 100))%"))
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func familyStatusBadge(isActive: Bool, isDownloaded: Bool) -> some View {
        if isActive {
            Text(tr("Active", "Активна"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuesliTheme.success)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(MuesliTheme.success.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if isDownloaded {
            Text(tr("Downloaded", "Скачано"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MuesliTheme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    // Per direct feedback ("все модели должны быть в одинаковых
    // плашках") — this used to render a bare 24×24 logo image with no
    // background at all, while `combinedConfiguredModelCard`'s icon was a
    // 36×36 SF Symbol in an accent-tinted circle. Same circular tile size
    // everywhere now, regardless of whether a card's icon is a brand PNG
    // or a system symbol — and a generic fallback icon instead of
    // rendering nothing when a card has no logo asset.
    private func brandLogo(_ name: String?) -> some View {
        ZStack {
            Circle().fill(MuesliTheme.accentSubtle)
            if let name,
               let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
            }
        }
        .frame(width: 36, height: 36)
    }

    private func logoForBackend(_ option: BackendOption) -> String? {
        switch option.backend {
        case "fluidaudio": return "nvidia-logo"
        case "whisper": return "openai-logo"
        case "cohere": return "cohere-logo"
        case "qwen": return "qwen-logo"
        case "nemotron35": return "nvidia-logo"
        case "indicasr": return "ai4bharat-logo"
        case "sensevoice": return "qwen-logo"
        default: return nil
        }
    }

    @ViewBuilder
    private func actionButtons(for option: BackendOption, isActive: Bool, isDownloaded: Bool, isDownloading: Bool) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            if isDownloading {
                Button(tr("Cancel", "Отмена")) {
                    cancelDownload(option)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.textSecondary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 4)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            } else if isDownloaded {
                if !isActive {
                    Button(tr("Set Active", "Сделать активной")) {
                        controller.selectBackend(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }

                Button {
                    modelToDelete = option
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.6))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            } else {
                Button(tr("Download", "Скачать")) {
                    startDownload(option)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 4)
                .background(MuesliTheme.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
        }
    }

    // Same compact treatment as `familyCard`: title/badges above the box,
    // no prose description, everything else (language picker, progress,
    // actions) collapsed into one gray-bordered table box.
    private func modelCard(option: BackendOption, logo: String? = nil) -> some View {
        let isActive = appState.selectedBackend == option
        let isDownloaded = downloadedModels.contains(option.model)
        let isDownloading = downloadingModels.contains(option.model)
        let progress = downloadProgress[option.model] ?? 0

        return VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing8) {
                brandLogo(logo)
                Text(option.label)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)

                if option.recommended {
                    Text(tr("Recommended", "Рекомендуемая"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MuesliTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text(option.sizeLabel)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)

                Spacer()

                if isActive {
                    Text(tr("Active", "Активна"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isDownloaded {
                    Text(tr("Downloaded", "Скачано"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                    if option.backend == BackendOption.cohereTranscribe.backend {
                        Text(tr("Language", "Язык"))
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                        Picker("", selection: cohereLanguageSelection) {
                            ForEach(CohereTranscribeLanguage.allCases, id: \.self) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 170, alignment: .leading)
                    } else if option.backend == BackendOption.indicASR.backend {
                        Text(tr("Language", "Язык"))
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                        Picker("", selection: indicASRLanguageSelection) {
                            ForEach(IndicASRLanguage.allCases, id: \.self) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 170, alignment: .leading)
                    } else if option.backend == BackendOption.nemotron35Multilingual.backend {
                        Text(tr("Language", "Язык"))
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                        Picker("", selection: nemotron35LanguageSelection) {
                            ForEach(Nemotron35Language.allCases, id: \.self) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 170, alignment: .leading)
                    }

                    Spacer()

                    actionButtons(for: option, isActive: isActive, isDownloaded: isDownloaded, isDownloading: isDownloading)
                }

                if option.backend == BackendOption.nemotron35Multilingual.backend,
                   isDownloaded, nemotron35UpdateAvailable, !isDownloading {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.accent)
                        Text(tr("A newer model build is available.", "Доступна новая сборка модели."))
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textSecondary)
                        Button(tr("Update", "Обновить")) { updateNemotron35(option) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuesliTheme.accent)
                    }
                }

                if isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .tint(MuesliTheme.accent)
                        Text(tr("\(Int(progress * 100))% downloading...", "Скачивание… \(Int(progress * 100))%"))
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private func comingSoonCard(option: BackendOption) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Text(option.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textTertiary)

                        Text(tr("Experimental", "Экспериментальная"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MuesliTheme.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(option.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary.opacity(0.6))
                    }

                    Text(option.description)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary.opacity(0.7))
                }
                Spacer()
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder.opacity(0.5), lineWidth: 1)
        )
        .opacity(0.6)
    }

    // MARK: - Post-Processor Actions

    private func startPostProcDownload(_ option: PostProcessorOption) {
        withAnimation { _ = downloadingPostProcModels.insert(option.id) }
        downloadProgressPostProc[option.id] = 0.02

        let task = Task {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: option.cacheDirectory, withIntermediateDirectories: true)

                try await downloadPostProcModel(option)

                await MainActor.run {
                    withAnimation {
                        downloadingPostProcModels.remove(option.id)
                        downloadedPostProcModels.insert(option.id)
                        downloadProgressPostProc.removeValue(forKey: option.id)
                        downloadTasksPostProc.removeValue(forKey: option.id)
                    }
                    if appState.config.enablePostProcessor && !appState.activePostProcessor.isDownloaded {
                        controller.selectPostProcessor(option)
                        controller.preloadExperimentalTranscriptionFeatures()
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        downloadingPostProcModels.remove(option.id)
                        downloadProgressPostProc.removeValue(forKey: option.id)
                        downloadTasksPostProc.removeValue(forKey: option.id)
                    }
                }
                let isCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !isCancelled {
                    fputs("[muesli-native] Post-processor download failed: \(error)\n", stderr)
                }
            }
        }
        downloadTasksPostProc[option.id] = task
    }

    private func downloadPostProcModel(_ option: PostProcessorOption, maxRetries: Int = 3) async throws {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            try Task.checkCancellation()
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
                fputs("[download] retry \(attempt)/\(maxRetries) for \(option.filename)\n", stderr)
                await MainActor.run {
                    downloadProgressPostProc[option.id] = 0.02
                }
            }
            do {
                let tmpURL = try await downloadPostProcTempFile(option)
                try installPostProcModel(from: tmpURL, option: option)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        let underlying = lastError ?? NSError(domain: "PostProcDownload", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "No download attempts were made",
        ])
        throw DownloadError.retriesExhausted(option.filename, underlying)
    }

    private func downloadPostProcTempFile(_ option: PostProcessorOption) async throws -> URL {
        let delegate = PostProcDownloadDelegate { progress in
            DispatchQueue.main.async {
                downloadProgressPostProc[option.id] = max(progress, 0.02)
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let invalidator = URLSessionInvalidator()
        do {
            let downloadedURL = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.setContinuation(continuation)
                    session.downloadTask(with: option.downloadURL).resume()
                }
            } onCancel: {
                invalidator.cancel(session)
            }
            invalidator.finish(session)
            return downloadedURL
        } catch {
            if error is CancellationError {
                invalidator.cancel(session)
            } else {
                invalidator.finish(session)
            }
            throw error
        }
    }

    private func installPostProcModel(from tmpURL: URL, option: PostProcessorOption) throws {
        let fm = FileManager.default
        let stagingURL = option.cacheDirectory.appendingPathComponent(".\(option.filename).download")
        defer {
            try? fm.removeItem(at: tmpURL)
            try? fm.removeItem(at: stagingURL)
        }
        try? fm.removeItem(at: stagingURL)
        try fm.moveItem(at: tmpURL, to: stagingURL)
        if fm.fileExists(atPath: option.modelURL.path) {
            _ = try fm.replaceItemAt(
                option.modelURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fm.moveItem(at: stagingURL, to: option.modelURL)
        }
    }

    private func cancelPostProcDownload(_ option: PostProcessorOption) {
        downloadTasksPostProc[option.id]?.cancel()
        withAnimation {
            downloadingPostProcModels.remove(option.id)
            downloadProgressPostProc.removeValue(forKey: option.id)
            downloadTasksPostProc.removeValue(forKey: option.id)
        }
    }

    private func deletePostProcModel(_ option: PostProcessorOption) {
        if appState.activePostProcessor.id == option.id {
            let remainingDownloadedIDs = downloadedPostProcModels.subtracting([option.id])
            if let fallback = PostProcessorOption.firstDownloaded(excluding: option.id, downloadedIDs: remainingDownloadedIDs) {
                controller.selectPostProcessor(fallback)
            } else {
                controller.setPostProcessorEnabled(false)
            }
        }
        try? FileManager.default.removeItem(at: option.cacheDirectory)
        downloadedPostProcModels.remove(option.id)
    }

    private func checkDownloadedPostProcModels() {
        downloadedPostProcModels.removeAll()
        for option in PostProcessorOption.all {
            if option.isDownloaded {
                downloadedPostProcModels.insert(option.id)
            }
        }
    }

    // MARK: - Local Summary Model Actions

    private func checkDownloadedSummaryModels() {
        downloadedSummaryModels.removeAll()
        for option in LocalSummaryModelOption.all where option.isDownloaded {
            downloadedSummaryModels.insert(option.id)
        }
    }

    private func startSummaryDownload(_ option: LocalSummaryModelOption) {
        withAnimation { _ = downloadingSummaryModels.insert(option.id) }
        downloadProgressSummary[option.id] = 0.02

        let task = Task {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: option.cacheDirectory, withIntermediateDirectories: true)
                try await downloadSummaryModel(option)

                await MainActor.run {
                    withAnimation {
                        downloadingSummaryModels.remove(option.id)
                        downloadedSummaryModels.insert(option.id)
                        downloadProgressSummary.removeValue(forKey: option.id)
                        downloadTasksSummary.removeValue(forKey: option.id)
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        downloadingSummaryModels.remove(option.id)
                        downloadProgressSummary.removeValue(forKey: option.id)
                        downloadTasksSummary.removeValue(forKey: option.id)
                    }
                }
                let isCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !isCancelled {
                    fputs("[muesli-native] Local summary model download failed: \(error)\n", stderr)
                }
            }
        }
        downloadTasksSummary[option.id] = task
    }

    private func downloadSummaryModel(_ option: LocalSummaryModelOption, maxRetries: Int = 3) async throws {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            try Task.checkCancellation()
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
                fputs("[download] retry \(attempt)/\(maxRetries) for \(option.filename)\n", stderr)
                await MainActor.run {
                    downloadProgressSummary[option.id] = 0.02
                }
            }
            do {
                let tmpURL = try await downloadSummaryTempFile(option)
                try installSummaryModel(from: tmpURL, option: option)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        let underlying = lastError ?? NSError(domain: "SummaryDownload", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "No download attempts were made",
        ])
        throw DownloadError.retriesExhausted(option.filename, underlying)
    }

    private func downloadSummaryTempFile(_ option: LocalSummaryModelOption) async throws -> URL {
        let delegate = PostProcDownloadDelegate { progress in
            DispatchQueue.main.async {
                downloadProgressSummary[option.id] = max(progress, 0.02)
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let invalidator = URLSessionInvalidator()
        do {
            let downloadedURL = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.setContinuation(continuation)
                    session.downloadTask(with: option.downloadURL).resume()
                }
            } onCancel: {
                invalidator.cancel(session)
            }
            invalidator.finish(session)
            return downloadedURL
        } catch {
            if error is CancellationError {
                invalidator.cancel(session)
            } else {
                invalidator.finish(session)
            }
            throw error
        }
    }

    private func installSummaryModel(from tmpURL: URL, option: LocalSummaryModelOption) throws {
        let fm = FileManager.default
        let stagingURL = option.cacheDirectory.appendingPathComponent(".\(option.filename).download")
        defer {
            try? fm.removeItem(at: tmpURL)
            try? fm.removeItem(at: stagingURL)
        }
        try? fm.removeItem(at: stagingURL)
        try fm.moveItem(at: tmpURL, to: stagingURL)
        if fm.fileExists(atPath: option.modelURL.path) {
            _ = try fm.replaceItemAt(
                option.modelURL,
                withItemAt: stagingURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fm.moveItem(at: stagingURL, to: option.modelURL)
        }
    }

    private func cancelSummaryDownload(_ option: LocalSummaryModelOption) {
        downloadTasksSummary[option.id]?.cancel()
        withAnimation {
            downloadingSummaryModels.remove(option.id)
            downloadProgressSummary.removeValue(forKey: option.id)
            downloadTasksSummary.removeValue(forKey: option.id)
        }
    }

    private func deleteSummaryModel(_ option: LocalSummaryModelOption) {
        // If this local backend was selected, fall back to ChatGPT so summaries keep working.
        if appState.config.meetingSummaryBackend.lowercased() == MeetingSummaryBackendOption.localGguf.backend {
            controller.selectMeetingSummaryBackend(.chatGPT)
        }
        try? FileManager.default.removeItem(at: option.cacheDirectory)
        downloadedSummaryModels.remove(option.id)
    }

    // MARK: - Actions

    private func startDownload(_ option: BackendOption) {
        withAnimation { _ = downloadingModels.insert(option.model) }
        downloadProgress[option.model] = 0.05  // Show initial progress immediately

        let startTime = Date()
        let task = Task {
            do {
                try await controller.transcriptionCoordinator.preloadRequired(
                    backend: option,
                    includeMeetingHelpers: controller.config.resolvedOnboardingUseCase.includesMeetings
                ) { progress, _ in
                    DispatchQueue.main.async {
                        downloadProgress[option.model] = max(progress, 0.05)
                    }
                }
                guard isModelDownloaded(option, fm: FileManager.default) else {
                    throw NSError(
                        domain: "MuesliModelDownload",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "\(option.label) was not downloaded successfully."]
                    )
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        withAnimation {
                            downloadingModels.remove(option.model)
                            downloadProgress.removeValue(forKey: option.model)
                            downloadTasks.removeValue(forKey: option.model)
                        }
                    }
                    return
                }
                // Ensure the downloading state is visible for at least 1.5s
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed < 1.5 {
                    try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
                }
                await MainActor.run {
                    withAnimation {
                        downloadingModels.remove(option.model)
                        downloadedModels.insert(option.model)
                        downloadProgress.removeValue(forKey: option.model)
                        downloadTasks.removeValue(forKey: option.model)
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        downloadingModels.remove(option.model)
                        downloadProgress.removeValue(forKey: option.model)
                        downloadTasks.removeValue(forKey: option.model)
                    }
                }
                if !(error is CancellationError) {
                    fputs("[muesli-native] model download failed for \(option.backend)/\(option.model): \(error)\n", stderr)
                }
            }
        }
        downloadTasks[option.model] = task
    }

    private func cancelDownload(_ option: BackendOption) {
        downloadTasks[option.model]?.cancel()
        withAnimation {
            downloadingModels.remove(option.model)
            downloadProgress.removeValue(forKey: option.model)
            downloadTasks.removeValue(forKey: option.model)
        }
    }

    /// Re-download Nemotron 3.5 to pick up a newer upstream build: delete the cached
    /// files (so the download isn't skipped), then start a fresh download.
    private func updateNemotron35(_ option: BackendOption) {
        Task {
            do {
                await controller.transcriptionCoordinator.unloadNemotron35Transcriber()
                try await deleteModelFiles(option)
                await MainActor.run {
                    downloadedModels.remove(option.model)
                    nemotron35UpdateAvailable = false
                    startDownload(option)
                }
            } catch {
                fputs("[muesli-native] model update cleanup failed for \(option.backend)/\(option.model): \(error)\n", stderr)
            }
        }
    }

    private func deleteModel(_ option: BackendOption) {
        if appState.selectedBackend == option {
            let fallback = downloadedModels
                .compactMap { model in BackendOption.all.first(where: { $0.model == model && $0 != option }) }
                .first ?? .parakeetMultilingual
            controller.selectBackend(fallback)
        }
        // Remove cached model files
        Task {
            do {
                try await deleteModelFiles(option)
                await MainActor.run {
                    _ = downloadedModels.remove(option.model)
                }
            } catch {
                fputs("[muesli-native] model delete failed for \(option.backend)/\(option.model): \(error)\n", stderr)
            }
        }
    }

    private func deleteModelFiles(_ option: BackendOption) async throws {
        let fm = FileManager.default
        switch option.backend {
        case "whisper":
            WhisperKitTranscriber.deleteModel(option.model)
        case "nemotron35":
            let path = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/muesli/models/nemotron35-multilingual-2240ms")
            try removeItemIfPresent(at: path, fileManager: fm)
        case "cohere":
            try removeItemIfPresent(at: CohereTranscribeModelStore.cacheDirectory(), fileManager: fm)
        case "indicasr":
            if IndicASRModelStore.localOverrideDirectory() == nil {
                try removeItemIfPresent(at: IndicASRModelStore.cacheDirectory(), fileManager: fm)
            }
        case "sensevoice":
            SenseVoiceTranscriber.deleteModelFiles(fileManager: fm)
        case "fluidaudio":
            // FluidAudio models are in ~/Library/Application Support/FluidAudio/Models/
            let supportDir = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/FluidAudio/Models")
            if option.model.contains("parakeet") {
                let version = option.model.contains("v2") ? "v2" : "v3"
                if let contents = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) {
                    for dir in contents where dir.lastPathComponent.contains("parakeet") && dir.lastPathComponent.contains(version) {
                        try removeItemIfPresent(at: dir, fileManager: fm)
                    }
                }
            }
        case "qwen":
            let path = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/FluidAudio/Models/qwen3-asr-0.6b-coreml")
            try removeItemIfPresent(at: path, fileManager: fm)
        default:
            break
        }
    }

    private func removeItemIfPresent(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    // MARK: - Check Downloaded Status

    private func checkDownloadedModels() {
        let fm = FileManager.default
        for option in BackendOption.all {
            if isModelDownloaded(option, fm: fm) {
                downloadedModels.insert(option.model)
            }
        }
    }

    /// Background check: does FluidInference's repo have a newer commit than what's
    /// installed for Nemotron 3.5? Never auto-downloads — just surfaces a badge.
    private func checkNemotron35Update() {
        guard #available(macOS 15, *),
              isModelDownloaded(.nemotron35Multilingual, fm: FileManager.default) else { return }
        Task {
            let available = await Nemotron35StreamingTranscriber.updateAvailable()
            await MainActor.run { nemotron35UpdateAvailable = available }
        }
    }

    private func syncSelectionsFromActiveBackend() {
        let active = appState.selectedBackend
        if BackendOption.parakeetFamily.contains(active) {
            selectedParakeetModel = active.model
        }
        if BackendOption.whisperFamily.contains(active) {
            selectedWhisperModel = active.model
        }
        if BackendOption.experimental.contains(active) {
            return
        }
    }

    private func isModelDownloaded(_ option: BackendOption, fm: FileManager) -> Bool {
        switch option.backend {
        case "whisper":
            return WhisperKitTranscriber.isModelDownloaded(option.model)
        case "nemotron35":
            let path = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/muesli/models/nemotron35-multilingual-2240ms/encoder.mlmodelc/coremldata.bin")
            return fm.fileExists(atPath: path.path)
        case "fluidaudio":
            // Check FluidAudio's cache
            let supportDir = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/FluidAudio/Models")
            if option.model.contains("parakeet") {
                let version = option.model.contains("v2") ? "v2" : "v3"
                if let contents = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) {
                    return contents.contains { $0.lastPathComponent.contains("parakeet") && $0.lastPathComponent.contains(version) }
                }
            }
            return false
        case "qwen":
            let supportDir = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/FluidAudio/Models/qwen3-asr-0.6b-coreml")
            return fm.fileExists(atPath: supportDir.appendingPathComponent("int8/vocab.json").path)
                || fm.fileExists(atPath: supportDir.appendingPathComponent("f32/vocab.json").path)
        case "cohere":
            return CohereTranscribeModelStore.isAvailableLocally()
        case "indicasr":
            return IndicASRModelStore.isAvailableLocally()
        case "sensevoice":
            return SenseVoiceTranscriber.isModelDownloaded()
        default:
            return false
        }
    }
}

private final class URLSessionInvalidator: @unchecked Sendable {
    private let lock = NSLock()
    private var didInvalidate = false

    func finish(_ session: URLSession) {
        invalidate(session, action: { $0.finishTasksAndInvalidate() })
    }

    func cancel(_ session: URLSession) {
        invalidate(session, action: { $0.invalidateAndCancel() })
    }

    private func invalidate(_ session: URLSession, action: (URLSession) -> Void) {
        lock.lock()
        guard !didInvalidate else {
            lock.unlock()
            return
        }
        didInvalidate = true
        lock.unlock()
        action(session)
    }
}

/// URLSessionDownloadDelegate bridge for post-processor GGUF downloads.
/// Uses OS-level buffered download task instead of byte-by-byte async iteration.
private final class PostProcDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func setContinuation(_ c: CheckedContinuation<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        continuation = c
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        var dest: URL?
        do {
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw NSError(domain: "PostProcDownload", code: response.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Post-processor download failed with HTTP \(response.statusCode)",
                ])
            }

            // URLSession deletes the temp file after this returns — move it first.
            let movedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".gguf.tmp")
            try FileManager.default.moveItem(at: location, to: movedURL)
            dest = movedURL
            try validateGGUFHeader(at: movedURL)
            resumeOnce(.success(movedURL))
        } catch {
            if let dest { try? FileManager.default.removeItem(at: dest) }
            resumeOnce(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        resumeOnce(.failure(error))
    }

    private func resumeOnce(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func validateGGUFHeader(at url: URL) throws {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let header = try fh.read(upToCount: 4) ?? Data()
        guard header == Data([0x47, 0x47, 0x55, 0x46]) else {
            throw NSError(domain: "PostProcDownload", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Downloaded post-processor file is not a GGUF model",
            ])
        }
    }
}
