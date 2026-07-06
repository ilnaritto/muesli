import AppKit
import AVFoundation
import SwiftUI
import MuesliCore

private struct MeetingDetectionAppOption: Identifiable {
    let bundleID: String
    let name: String
    let icon: String

    var id: String { bundleID }
}

private struct DictationMicrophoneOption: Identifiable {
    let uid: String?
    let label: String

    var id: String { uid ?? "__automatic__" }
}

struct SettingsView: View {
    private enum PendingDataDestruction {
        case dictations
        case meetings

        var title: String {
            switch self {
            case .dictations:
                return tr("Clear dictation history?", "Очистить историю диктовок?")
            case .meetings:
                return tr("Clear meeting history?", "Очистить историю встреч?")
            }
        }

        var message: String {
            switch self {
            case .dictations:
                return tr("This will permanently remove all saved dictations. This cannot be undone.", "Все сохранённые диктовки будут удалены безвозвратно. Это действие нельзя отменить.")
            case .meetings:
                return tr("This will permanently remove all saved meetings, notes, transcripts, and retained audio recordings. This cannot be undone.", "Все сохранённые встречи, заметки, транскрипты и аудиозаписи будут удалены безвозвратно. Это действие нельзя отменить.")
            }
        }

        var confirmLabel: String {
            switch self {
            case .dictations:
                return tr("Clear Dictations", "Очистить диктовки")
            case .meetings:
                return tr("Clear Meetings", "Очистить встречи")
            }
        }
    }

    let appState: AppState
    let controller: MuesliController

    @State private var chatGPTSignInError: String?
    @State private var isSigningInChatGPT = false
    @State private var googleCalSignInError: String?
    @State private var isSigningInGoogleCal = false
    @State private var pendingDataDestruction: PendingDataDestruction?
    @State private var isShowingDictionaryAccessibilityPrompt = false
    @State private var isPreviewingClip = false
    @State private var downloadedBackendOptions: [BackendOption] = []
    @State private var downloadedPostProcOptions: [PostProcessorOption] = []
    @State private var dictationInputDevices: [AudioInputDeviceInfo] = []
    @State private var permissionPollTimer: Timer?
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var screenRecordingGranted = false
    @AppStorage("settings.pendingScreenContextEnable") private var pendingScreenContextEnable = false
    @AppStorage("settings.pendingScreenContextRequestedAt") private var pendingScreenContextRequestedAt = 0.0
    @State private var systemAudioGranted = false
    @State private var isCheckingSystemAudioPermission = false
    @State private var openRouterFreeModels: [SummaryModelPreset] = []
    @State private var isLoadingOpenRouterFreeModels = false
    @State private var openRouterFreeModelsError: String?
    @State private var hasRefreshedMeetingCalendarSources = false

    // Uniform width for all right-side controls
    private let controlWidth: CGFloat = 220
    private let meetingControlWidth: CGFloat = 275
    private let iOSCompanionURL = IPhoneBridgeLinks.installURL
    private let screenContextGrantIntentTimeout: TimeInterval = 15 * 60
    private let meetingDetectionAppOptions: [MeetingDetectionAppOption] = [
        MeetingDetectionAppOption(bundleID: "com.google.Chrome", name: "Chrome", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "company.thebrowser.Browser", name: "Arc", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.apple.Safari", name: "Safari", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.microsoft.edgemac", name: "Edge", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.brave.Browser", name: "Brave", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", icon: "message.fill"),
        MeetingDetectionAppOption(bundleID: "us.zoom.xos", name: "Zoom", icon: "video.fill"),
        MeetingDetectionAppOption(bundleID: "com.microsoft.teams2", name: "Teams", icon: "person.2.fill"),
        MeetingDetectionAppOption(bundleID: "com.apple.FaceTime", name: "FaceTime", icon: "video.fill"),
        MeetingDetectionAppOption(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", icon: "phone.fill"),
    ]

    private var dictationBackendOptions: [BackendOption] {
        backendOptions(including: appState.selectedBackend)
    }

    private var meetingBackendOptions: [BackendOption] {
        downloadedBackendOptions
    }

    private var selectedMeetingBackendLabel: String {
        if meetingBackendOptions.contains(appState.selectedMeetingTranscriptionBackend) {
            return appState.selectedMeetingTranscriptionBackend.label
        }
        return meetingBackendOptions.first?.label ?? tr("No downloaded models", "Нет загруженных моделей")
    }

    private var selectedCohereLanguage: CohereTranscribeLanguage {
        appState.config.resolvedCohereLanguage
    }

    private var selectedUpcomingMeetingsWindow: UpcomingMeetingsWindow {
        UpcomingMeetingsWindow.resolve(dayCount: appState.config.upcomingMeetingsDayCount)
    }

    private var selectedIndicASRLanguage: IndicASRLanguage {
        appState.config.resolvedIndicASRLanguage
    }

    private var dictationMicrophoneOptions: [DictationMicrophoneOption] {
        var options = [DictationMicrophoneOption(uid: nil, label: tr("Automatic", "Автоматически"))]
        options += dictationInputDevices.map { device in
            DictationMicrophoneOption(uid: device.uid, label: device.name)
        }
        if let selectedUID = appState.config.dictationInputDeviceUID,
           !options.contains(where: { $0.uid == selectedUID }) {
            options.append(DictationMicrophoneOption(uid: selectedUID, label: tr("Selected microphone unavailable", "Выбранный микрофон недоступен")))
        }
        return options
    }

    private var selectedDictationMicrophoneLabel: String {
        let selectedUID = appState.config.dictationInputDeviceUID
        return dictationMicrophoneOptions.first(where: { $0.uid == selectedUID })?.label ?? tr("Automatic", "Автоматически")
    }

    var body: some View {
        HStack(spacing: 5) {
            PrimaryColumn(appState: appState, title: tr("Settings", "Настройки")) {
                sectionListPane
            }

            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            refreshDownloadedModelOptions()
            refreshDictationInputDevices()
            startPermissionPolling()
            if appState.selectedMeetingSummaryBackend == .openRouter {
                loadOpenRouterFreeModelsIfNeeded()
            }
        }
        .onDisappear {
            SoundController.stopMaraudersMapClip()
            isPreviewingClip = false
            stopPermissionPolling()
        }
        .onChange(of: appState.selectedTab) { _, tab in
            if tab == .settings {
                refreshDownloadedModelOptions()
                refreshDictationInputDevices()
                refreshPermissionStatuses(refreshLaunchAtLogin: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard appState.selectedTab == .settings else { return }
            refreshPermissionStatuses(refreshLaunchAtLogin: true)
        }
        .onChange(of: appState.selectedBackend) { _, _ in
            refreshDownloadedModelOptions()
        }
        .onChange(of: appState.selectedMeetingTranscriptionBackend) { _, _ in
            refreshDownloadedModelOptions()
        }
        .onChange(of: appState.selectedMeetingSummaryBackend) { _, backend in
            if backend == .openRouter {
                loadOpenRouterFreeModelsIfNeeded()
            }
        }
        .alert(
            pendingDataDestruction?.title ?? tr("Confirm Destructive Action", "Подтвердите действие"),
            isPresented: Binding(
                get: { pendingDataDestruction != nil },
                set: { if !$0 { pendingDataDestruction = nil } }
            )
        ) {
            Button(tr("Cancel", "Отмена"), role: .cancel) {
                pendingDataDestruction = nil
            }
            Button(pendingDataDestruction?.confirmLabel ?? tr("Delete", "Удалить"), role: .destructive) {
                switch pendingDataDestruction {
                case .dictations:
                    controller.clearDictationHistory()
                case .meetings:
                    controller.clearMeetingHistory()
                case nil:
                    break
                }
                pendingDataDestruction = nil
            }
        } message: {
            Text(pendingDataDestruction?.message ?? "")
        }
        .alert(
            tr("Enable Accessibility?", "Включить Универсальный доступ?"),
            isPresented: $isShowingDictionaryAccessibilityPrompt
        ) {
            Button(tr("Cancel", "Отмена"), role: .cancel) {
                controller.cancelDictionaryCorrectionAccessibilityEnableRequest()
            }
            Button(tr("Enable", "Включить")) {
                controller.requestDictionaryCorrectionAccessibilityEnable()
            }
        } message: {
            Text(tr("Dictionary suggestions briefly read focused app text via Accessibility after dictation. Grant access, then relaunch Muesli to turn suggestions on.", "Подсказки словаря кратко считывают текст активного приложения через Универсальный доступ после диктовки. Предоставьте доступ и перезапустите Muesli, чтобы включить подсказки."))
        }
    }

    private func refreshDownloadedModelOptions() {
        controller.refreshMeetingTranscriptionSelectionForAvailability()
        downloadedBackendOptions = BackendOption.downloaded
        downloadedPostProcOptions = PostProcessorOption.downloaded
    }

    private func refreshDictationInputDevices() {
        dictationInputDevices = controller.availableDictationInputDevices()
    }

    private func backendOptions(including selection: BackendOption) -> [BackendOption] {
        var options = downloadedBackendOptions
        if !options.contains(where: { $0 == selection }) {
            options.insert(selection, at: 0)
        }
        return options
    }

    private static let accentPresets: [(hex: String, name: String)] = [
        ("2563eb", tr("Blue", "Синий")),
        ("ef4444", tr("Red", "Красный")),
        ("f59e0b", tr("Amber", "Янтарный")),
        ("10b981", tr("Green", "Зелёный")),
        ("8b5cf6", tr("Purple", "Фиолетовый")),
        ("ec4899", tr("Pink", "Розовый")),
        ("1e1e2e", tr("Dark", "Тёмный")),
    ]

    private var screenContextDescription: String {
        if !accessibilityGranted {
            return tr("Grant Accessibility, then toggle again if needed.", "Предоставьте Универсальный доступ, затем при необходимости включите снова.")
        }
        if !screenRecordingGranted {
            return tr("Adds nearby app text for post-processing. Screen Recording enables OCR context.", "Добавляет текст приложения рядом с курсором для постобработки. Запись экрана включает контекст OCR.")
        }
        return tr("Adds nearby app text and OCR context. Processed on-device.", "Добавляет текст приложения и контекст OCR. Обрабатывается на устройстве.")
    }

    @ViewBuilder
    private func screenContextRow(_ title: String, controlWidth rowControlWidth: CGFloat? = nil) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(screenContextDescription)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 20)

            ZStack(alignment: .trailing) {
                Color.clear.frame(width: width, height: 1)
                screenContextControl(width: width)
            }
        }
        .frame(minHeight: 52)
    }

    private let customIndicatorPositionLabel = tr("Custom (drag to reposition)", "Вручную (перетащите для изменения)")

    private var sectionListPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // "About" now lives at the bottom of the Home tab.
                ForEach(SettingsSection.allCases.filter { $0 != .about }) { section in
                    sectionRow(section)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, MuesliTheme.spacing12)
        }
    }

    private func sectionRow(_ section: SettingsSection) -> some View {
        SidebarNavRow(
            icon: section.icon,
            iconColor: section.iconColor,
            title: section.title,
            isSelected: appState.settingsSection == section
        ) {
            appState.settingsSection = section
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch appState.settingsSection {
        case .dictionary:
            DictionaryView(appState: appState, controller: controller)
        case .models:
            ModelsView(appState: appState, controller: controller)
        case .shortcuts:
            ShortcutsView(appState: appState, controller: controller)
        case .about:
            AboutView(appState: appState, onOpenManualDiagnosticReport: { controller.openManualDiagnosticReport() })
        case .templates:
            // No outer ScrollView: the manager scrolls its own list.
            MeetingTemplatesManagerView(
                appState: appState,
                controller: controller,
                onClose: {},
                isEmbedded: true
            )
            .padding(MuesliTheme.spacing32)
        case .general, .sync, .dictation, .computerUse, .meetings, .appearance:
            ScrollView {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                    Text(appState.settingsSection.title)
                        .font(MuesliTheme.pageTitle())
                        .foregroundStyle(MuesliTheme.textPrimary)

                    paneContent
                }
                .padding(MuesliTheme.spacing32)
            }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch appState.settingsSection {
        case .general:
            generalSettingsPane
        case .sync:
            syncSettingsPane
        case .dictation:
            dictationSettingsPane
        case .computerUse:
            computerUseSettingsPane
        case .meetings:
            meetingsSettingsPane
        case .appearance:
            appearanceSettingsPane
        case .dictionary, .models, .shortcuts, .about, .templates:
            EmptyView()
        }
    }

    private var generalSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(tr("General", "Общие")) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    settingsRow(tr("Launch at login", "Запускать при входе в систему")) {
                        settingsSwitch(isOn: appState.config.launchAtLogin) { newValue in
                            controller.setLaunchAtLogin(newValue)
                        }
                    }
                    if appState.launchAtLoginRegistrationState == .requiresApproval {
                        launchAtLoginApprovalPrompt
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Open dashboard on launch", "Открывать панель при запуске")) {
                    settingsSwitch(isOn: appState.config.openDashboardOnLaunch) { newValue in
                        controller.updateConfig { $0.openDashboardOnLaunch = newValue }
                    }
                }
            }

            settingsSection(tr("Language", "Язык")) {
                settingsRow(tr("App language", "Язык приложения")) {
                    Picker("", selection: Binding(
                        get: { appState.config.resolvedAppLanguage },
                        set: { newValue in
                            controller.updateConfig { $0.appLanguage = newValue.rawValue }
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: controlWidth)
                }
            }

            permissionsSection

            settingsSection(tr("Data", "Данные")) {
                HStack(spacing: MuesliTheme.spacing12) {
                    actionButton(tr("Clear dictation history", "Очистить историю диктовок"), role: .destructive) {
                        pendingDataDestruction = .dictations
                    }
                    actionButton(tr("Clear meeting history", "Очистить историю встреч"), role: .destructive) {
                        pendingDataDestruction = .meetings
                    }
                    .disabled(controller.isMeetingRecording())
                    .help(tr("Stop the current meeting recording before clearing meeting history.", "Остановите текущую запись встречи перед очисткой истории встреч."))
                }
            }
        }
    }

    private var launchAtLoginApprovalPrompt: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuesliTheme.recording)
            Text(tr("Requires approval in System Settings", "Требуется одобрение в Системных настройках"))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
            Spacer(minLength: MuesliTheme.spacing12)
            Button {
                controller.openLaunchAtLoginSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(tr("Open", "Открыть"))
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MuesliTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(MuesliTheme.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .help(tr("Open Login Items in System Settings", "Открыть «Объекты входа» в Системных настройках"))
        }
        .padding(.leading, MuesliTheme.spacing16)
        .padding(.trailing, MuesliTheme.spacing16)
        .padding(.bottom, MuesliTheme.spacing8)
    }

    private var syncSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(tr("iCloud Text Sync", "Синхронизация текста iCloud")) {
                settingsRow(tr("Private iCloud sync", "Частная синхронизация iCloud")) {
                    settingsSwitch(isOn: appState.config.iCloudSyncEnabled) { newValue in
                        controller.setICloudSyncEnabledFromSettings(newValue)
                    }
                }
                settingsDescription(tr("Sync dictation text, meeting transcripts, notes, summaries, and manual notes with Muesli for iPhone through your private iCloud account. Audio recordings are never synced.", "Синхронизация текста диктовок, транскриптов встреч, заметок, сводок и ручных заметок с Muesli для iPhone через ваш частный аккаунт iCloud. Аудиозаписи никогда не синхронизируются."))

                Divider().background(MuesliTheme.surfaceBorder)

                HStack(spacing: MuesliTheme.spacing12) {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                        Text(syncStatusText)
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let lastSyncedText = syncLastSyncedText {
                            Text(tr("Last synced: \(lastSyncedText)", "Последняя синхронизация: \(lastSyncedText)"))
                                .font(MuesliTheme.caption())
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                        if let linkedDeviceText = syncLinkedDeviceText {
                            Text(linkedDeviceText)
                                .font(MuesliTheme.caption())
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: MuesliTheme.spacing16)
                    actionButton(tr("Sync now", "Синхронизировать сейчас"), systemImage: "arrow.triangle.2.circlepath") {
                        controller.performICloudSync()
                    }
                    .frame(width: controlWidth)
                    .disabled(!appState.config.iCloudSyncEnabled)
                }
            }

            settingsSection(tr("iPhone Bridge", "Связь с iPhone")) {
                settingsRow(tr("Show iOS companion prompt", "Показывать предложение приложения для iOS")) {
                    settingsSwitch(isOn: appState.config.showIOSCompanionPrompt) { newValue in
                        controller.updateConfig { $0.showIOSCompanionPrompt = newValue }
                    }
                }
                settingsDescription(tr("Keep the timeline bridge card available while users connect Muesli on iPhone.", "Сохранять карточку подключения на таймлайне, пока Muesli подключается на iPhone."))

                Divider().background(MuesliTheme.surfaceBorder)

                HStack(spacing: MuesliTheme.spacing12) {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                        Text(tr("Muesli for iPhone", "Muesli для iPhone"))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        Text(tr("Use iPhone for offline meetings, keyboard dictation, and private iCloud text sync with this Mac.", "Используйте iPhone для офлайн-встреч, диктовки с клавиатуры и частной синхронизации текста через iCloud с этим Mac."))
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: MuesliTheme.spacing16)
                    actionButton(tr("Open iOS app page", "Открыть страницу приложения для iOS")) {
                        NSWorkspace.shared.open(iOSCompanionURL)
                    }
                    .frame(width: controlWidth)
                }
            }
        }
    }

    private var syncStatusText: String {
        if !appState.config.iCloudSyncEnabled {
            return tr("Sync is off. Turn it on to bridge this Mac with Muesli for iPhone.", "Синхронизация выключена. Включите её, чтобы связать этот Mac с Muesli для iPhone.")
        }
        return appState.iCloudSyncStatus ?? tr("Private iCloud text sync is ready.", "Частная синхронизация текста iCloud готова.")
    }

    private var syncLastSyncedText: String? {
        guard let date = appState.iCloudLastSyncedAt else { return nil }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private var syncLinkedDeviceText: String? {
        guard appState.config.iCloudSyncEnabled else { return nil }
        if let remoteDeviceName = appState.iCloudBridgeCompanionDeviceName {
            if let platform = appState.iCloudBridgeRemoteDevicePlatform {
                return tr("Linked \(syncDeviceLabel(for: platform)): \(remoteDeviceName)", "Связанный \(syncDeviceLabel(for: platform)): \(remoteDeviceName)")
            }
            return tr("Linked device: \(remoteDeviceName)", "Связанное устройство: \(remoteDeviceName)")
        }
        return tr("No linked iPhone yet.", "iPhone ещё не связан.")
    }

    private func syncDeviceLabel(for platform: String) -> String {
        switch platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ios":
            return "iPhone"
        case "ipados":
            return "iPad"
        default:
            return platform
        }
    }

    private var dictationSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(tr("Transcription", "Транскрипция")) {
                settingsRow(tr("Dictation model", "Модель диктовки")) {
                    settingsMenu(
                        selection: appState.selectedBackend.label,
                        options: dictationBackendOptions.map(\.label)
                    ) { label in
                        if let option = dictationBackendOptions.first(where: { $0.label == label }) {
                            controller.selectBackend(option)
                        }
                    }
                }
                if appState.selectedBackend.backend == BackendOption.cohereTranscribe.backend {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Cohere language", "Язык Cohere")) {
                        settingsMenu(
                            selection: selectedCohereLanguage.label,
                            options: CohereTranscribeLanguage.allCases.map(\.label)
                        ) { label in
                            guard let language = CohereTranscribeLanguage.allCases.first(where: { $0.label == label }) else { return }
                            controller.selectCohereLanguage(language)
                        }
                    }
                }
                if appState.selectedBackend.backend == BackendOption.indicASR.backend {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Indic language", "Индийский язык")) {
                        FixedWidthPopUp(
                            selection: selectedIndicASRLanguage.label,
                            options: IndicASRLanguage.allCases.map(\.label),
                            onSelectIndex: { index in
                                guard index >= 0, index < IndicASRLanguage.allCases.count else { return }
                                controller.selectIndicASRLanguage(IndicASRLanguage.allCases[index])
                            }
                        )
                        .frame(height: 24)
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(
                    tr("Microphone", "Микрофон"),
                    description: tr("Automatic uses system input, or Mac mic with AirPods.", "«Автоматически» использует системный вход или микрофон Mac с AirPods.")
                ) {
                    let options = dictationMicrophoneOptions
                    FixedWidthPopUp(
                        selection: selectedDictationMicrophoneLabel,
                        options: options.map(\.label),
                        onSelectIndex: { index in
                            guard index >= 0, index < options.count else { return }
                            controller.selectDictationInputDeviceUID(options[index].uid)
                            refreshDictationInputDevices()
                        }
                    )
                    .frame(height: 24)
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("AI transcript cleanup", "ИИ-очистка транскрипта")) {
                    settingsSwitch(isOn: appState.config.enablePostProcessor) { newValue in
                        controller.setPostProcessorEnabled(newValue)
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(
                    tr("Dictionary suggestions", "Подсказки словаря"),
                    description: tr("Suggest words after corrections by briefly reading focused app text via Accessibility.", "Предлагает слова после исправлений, кратко считывая текст активного приложения через Универсальный доступ.")
                ) {
                    settingsSwitch(isOn: appState.config.enableDictionaryCorrectionPrompts) { newValue in
                        handleDictionaryCorrectionPromptsToggle(newValue)
                    }
                    .help(tr("Briefly reads focused app text after dictation to detect corrections.", "Кратко считывает текст активного приложения после диктовки для обнаружения исправлений."))
                }
                if appState.config.enablePostProcessor && !downloadedPostProcOptions.isEmpty {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Cleanup model", "Модель очистки")) {
                        let selection = downloadedPostProcOptions.contains(where: { $0.id == appState.activePostProcessor.id })
                            ? appState.activePostProcessor.label
                            : (downloadedPostProcOptions.first?.label ?? "")
                        settingsMenu(
                            selection: selection,
                            options: downloadedPostProcOptions.map(\.label)
                        ) { label in
                            if let option = downloadedPostProcOptions.first(where: { $0.label == label }) {
                                controller.selectPostProcessor(option)
                            }
                        }
                    }
                } else if appState.config.enablePostProcessor {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Cleanup model", "Модель очистки")) {
                        Text(tr("Download a cleanup model in Models", "Загрузите модель очистки в разделе «Модели»"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: controlWidth, alignment: .trailing)
                    }
                }
            }

            settingsSection(tr("Advanced", "Дополнительно")) {
                settingsRow(tr("Pause media during dictation", "Приостанавливать медиа во время диктовки")) {
                    settingsSwitch(isOn: appState.config.pauseMediaDuringDictation) { newValue in
                        controller.updateConfig { $0.pauseMediaDuringDictation = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Mute system audio during dictation", "Отключать системный звук во время диктовки")) {
                    settingsSwitch(isOn: appState.config.muteSystemAudioDuringDictation) { newValue in
                        controller.updateConfig { $0.muteSystemAudioDuringDictation = newValue }
                    }
                }
                screenContextRow(tr("App context", "Контекст приложения"))
            }
        }
    }

    private var computerUseSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(tr("Computer Use", "Компьютер")) {
                settingsRow(tr("Enable planner", "Включить планировщик"), controlWidth: meetingControlWidth) {
                    settingsSwitch(isOn: appState.config.enableComputerUsePlanner) { newValue in
                        controller.updateConfig { $0.enableComputerUsePlanner = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Account", "Аккаунт"), controlWidth: meetingControlWidth) {
                    chatGPTAccountControl
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Planner model", "Модель планировщика"), controlWidth: meetingControlWidth) {
                    settingsModelMenu(
                        currentModel: appState.config.computerUsePlannerModel,
                        presets: SummaryModelPreset.computerUsePlannerModels
                    ) { val in controller.updateConfig { $0.computerUsePlannerModel = val } }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Timeout", "Тайм-аут"), controlWidth: meetingControlWidth) {
                    Stepper(
                        value: Binding(
                            get: { max(appState.config.computerUseTimeoutSeconds, 1) },
                            set: { newValue in
                                controller.updateConfig { $0.computerUseTimeoutSeconds = max(newValue, 1) }
                            }
                        ),
                        in: 1...600,
                        step: 15
                    ) {
                        Text(tr("\(max(appState.config.computerUseTimeoutSeconds, 1)) seconds", "\(max(appState.config.computerUseTimeoutSeconds, 1)) сек."))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }
                }
            }
        }
    }

    private var meetingsSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(tr("Meeting Transcription", "Транскрипция встреч")) {
                settingsRow(tr("Meeting model", "Модель встреч"), controlWidth: meetingControlWidth) {
                    if meetingBackendOptions.isEmpty {
                        Text(tr("No downloaded models", "Нет загруженных моделей"))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        settingsMenu(
                            selection: selectedMeetingBackendLabel,
                            options: meetingBackendOptions.map(\.label)
                        ) { label in
                            if let option = meetingBackendOptions.first(where: { $0.label == label }) {
                                controller.selectMeetingTranscriptionBackend(option)
                            }
                        }
                    }
                }
                if appState.selectedMeetingTranscriptionBackend.backend == BackendOption.cohereTranscribe.backend {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Cohere language", "Язык Cohere")) {
                        settingsMenu(
                            selection: selectedCohereLanguage.label,
                            options: CohereTranscribeLanguage.allCases.map(\.label)
                        ) { label in
                            guard let language = CohereTranscribeLanguage.allCases.first(where: { $0.label == label }) else { return }
                            controller.selectCohereLanguage(language)
                        }
                    }
                }
                if appState.selectedMeetingTranscriptionBackend.backend == BackendOption.indicASR.backend {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Indic language", "Индийский язык")) {
                        FixedWidthPopUp(
                            selection: selectedIndicASRLanguage.label,
                            options: IndicASRLanguage.allCases.map(\.label),
                            onSelectIndex: { index in
                                guard index >= 0, index < IndicASRLanguage.allCases.count else { return }
                                controller.selectIndicASRLanguage(IndicASRLanguage.allCases[index])
                            }
                        )
                        .frame(height: 24)
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                screenContextRow(tr("Meeting context", "Контекст встречи"))
            }

            settingsSection(tr("Meeting Summaries", "Сводки встреч")) {
                settingsRow(tr("Summary backend", "Бэкенд сводок"), controlWidth: meetingControlWidth) {
                    settingsMenu(
                        selection: appState.selectedMeetingSummaryBackend.label,
                        options: MeetingSummaryBackendOption.all.map(\.label)
                    ) { label in
                        if let option = MeetingSummaryBackendOption.all.first(where: { $0.label == label }) {
                            controller.selectMeetingSummaryBackend(option)
                        }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)

                if appState.selectedMeetingSummaryBackend == .chatGPT {
                    settingsRow(tr("Account", "Аккаунт"), controlWidth: meetingControlWidth) {
                        chatGPTAccountControl
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Model", "Модель"), controlWidth: meetingControlWidth) {
                        settingsModelMenu(
                            currentModel: appState.config.chatGPTModel,
                            presets: SummaryModelPreset.chatGPTModels
                        ) { val in controller.updateConfig { $0.chatGPTModel = val } }
                    }
                } else if appState.selectedMeetingSummaryBackend == .openAI {
                    settingsRow(tr("API Key", "API-ключ"), controlWidth: meetingControlWidth) {
                        PastableSecureField(
                            text: appState.config.openAIAPIKey,
                            placeholder: "sk-...",
                            onChange: { val in controller.updateConfig { $0.openAIAPIKey = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Model", "Модель"), controlWidth: meetingControlWidth) {
                        settingsModelMenu(
                            currentModel: appState.config.openAIModel,
                            presets: SummaryModelPreset.openAIModels
                        ) { val in controller.updateConfig { $0.openAIModel = val } }
                    }
                    keyStatusRow(key: appState.config.openAIAPIKey)
                } else if appState.selectedMeetingSummaryBackend == .ollama {
                    settingsRow(tr("Ollama URL", "URL Ollama"), controlWidth: meetingControlWidth) {
                        PastableTextField(
                            text: appState.config.ollamaURL,
                            placeholder: "http://localhost:11434",
                            onChange: { val in controller.updateConfig { $0.ollamaURL = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Model", "Модель"), controlWidth: meetingControlWidth) {
                        settingsModelTextField(
                            currentModel: appState.config.ollamaModel,
                            placeholder: "qwen3.5"
                        ) { val in controller.updateConfig { $0.ollamaModel = val } }
                    }
                } else if appState.selectedMeetingSummaryBackend == .lmStudio {
                    settingsRow(tr("LM Studio URL", "URL LM Studio"), controlWidth: meetingControlWidth) {
                        PastableTextField(
                            text: appState.config.lmStudioURL,
                            placeholder: "http://localhost:1234",
                            onChange: { val in controller.updateConfig { $0.lmStudioURL = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Model", "Модель"), controlWidth: meetingControlWidth) {
                        settingsModelTextField(
                            currentModel: appState.config.lmStudioModel,
                            placeholder: tr("Select a loaded LM Studio model", "Выберите загруженную модель LM Studio")
                        ) { val in controller.updateConfig { $0.lmStudioModel = val } }
                    }
                } else if appState.selectedMeetingSummaryBackend == .customLLM {
                    settingsRow(tr("API Format", "Формат API"), controlWidth: meetingControlWidth) {
                        settingsMenu(
                            selection: CustomLLMFormat(rawValue: appState.config.customLLMFormat)?.label ?? CustomLLMFormat.openAI.label,
                            options: CustomLLMFormat.allCases.map(\.label)
                        ) { label in
                            guard let format = CustomLLMFormat.allCases.first(where: { $0.label == label }) else { return }
                            controller.updateConfig { $0.customLLMFormat = format.rawValue }
                        }
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Endpoint", "Эндпоинт"), controlWidth: meetingControlWidth) {
                        PastableTextField(
                            text: appState.config.customLLMURL,
                            placeholder: appState.config.customLLMFormat == CustomLLMFormat.anthropic.rawValue
                                ? "https://api.anthropic.com"
                                : "http://localhost:8080/v1",
                            onChange: { val in controller.updateConfig { $0.customLLMURL = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("API Key", "API-ключ"), controlWidth: meetingControlWidth) {
                        PastableSecureField(
                            text: appState.config.customLLMAPIKey,
                            placeholder: appState.config.customLLMFormat == CustomLLMFormat.anthropic.rawValue
                                ? tr("Required for Anthropic API", "Требуется для Anthropic API")
                                : tr("Optional for local servers", "Необязательно для локальных серверов"),
                            onChange: { val in controller.updateConfig { $0.customLLMAPIKey = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Model", "Модель"), controlWidth: meetingControlWidth) {
                        settingsModelTextField(
                            currentModel: appState.config.customLLMModel,
                            placeholder: appState.config.customLLMFormat == CustomLLMFormat.anthropic.rawValue
                                ? "claude-3-5-sonnet-20241022"
                                : "custom-model-id"
                        ) { val in controller.updateConfig { $0.customLLMModel = val } }
                    }
                } else {
                    settingsRow(tr("API Key", "API-ключ"), controlWidth: meetingControlWidth) {
                        PastableSecureField(
                            text: appState.config.openRouterAPIKey,
                            placeholder: "sk-or-...",
                            onChange: { val in controller.updateConfig { $0.openRouterAPIKey = val } }
                        )
                        .frame(height: 22)
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Free model", "Бесплатная модель"), controlWidth: meetingControlWidth) {
                        openRouterFreeModelMenu
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Custom model ID", "Свой ID модели"), controlWidth: meetingControlWidth) {
                        settingsModelTextField(
                            currentModel: appState.config.openRouterModel,
                            placeholder: "provider/model or openrouter/free"
                        ) { val in controller.updateConfig { $0.openRouterModel = val } }
                    }
                    keyStatusRow(key: appState.config.openRouterAPIKey)
                }

                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Default template", "Шаблон по умолчанию"), controlWidth: meetingControlWidth) {
                    meetingTemplateMenu(selectionID: appState.config.defaultMeetingTemplateID) { id in
                        controller.updateDefaultMeetingTemplate(id: id)
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Templates", "Шаблоны"), controlWidth: meetingControlWidth) {
                    actionButton(tr("Manage Templates…", "Управление шаблонами…")) {
                        controller.showMeetingTemplateSettings()
                    }
                }
            }

            settingsSection(tr("Recording", "Запись")) {
                settingsRow(tr("Auto-record calendar meetings", "Автозапись встреч из календаря")) {
                    settingsSwitch(isOn: appState.config.autoRecordMeetings) { newValue in
                        controller.updateConfig { $0.autoRecordMeetings = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Save meeting recording", "Сохранять запись встречи")) {
                    settingsMenu(
                        selection: recordingSaveLabel(for: appState.config.meetingRecordingSavePolicy),
                        options: MeetingRecordingSavePolicy.allCases.map(recordingSaveLabel(for:))
                    ) { label in
                        guard let policy = recordingSavePolicy(for: label) else { return }
                        controller.updateConfig { $0.meetingRecordingSavePolicy = policy }
                    }
                }
                settingsDescription(tr("Saved audio can be played back on the meeting page and is also used as the soundtrack of screen video recordings.", "Сохранённое аудио можно прослушать на странице встречи; оно же добавляет звук в видеозапись экрана."))
                if appState.config.meetingRecordingSavePolicy != .never {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Recording format", "Формат записи")) {
                        settingsMenu(
                            selection: appState.config.resolvedMeetingRecordingFileFormat.displayName,
                            options: MeetingRecordingFileFormat.allCases.map(recordingFileFormatLabel(for:))
                        ) { label in
                            guard let format = recordingFileFormat(for: label) else { return }
                            controller.updateConfig { $0.meetingRecordingFileFormat = format.rawValue }
                        }
                    }
                    settingsDescription(tr("M4A is recommended for smaller files. WAV is lossless and uses more storage.", "M4A рекомендуется для файлов меньшего размера. WAV — без потерь, но занимает больше места."))
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Record screen video", "Записывать видео экрана")) {
                    settingsSwitch(isOn: appState.config.enableMeetingScreenVideo) { newValue in
                        controller.updateConfig { $0.enableMeetingScreenVideo = newValue }
                    }
                }
                settingsDescription(tr("Captures the main display during meetings and saves an .mp4 with the meeting audio. Uses significant disk space (roughly 1 GB per hour).", "Записывает основной экран во время встреч и сохраняет .mp4 со звуком встречи. Занимает много места на диске (примерно 1 ГБ в час)."))
            }

            settingsSection(tr("Auto Export", "Автоэкспорт")) {
                settingsRow(tr("Auto-export meetings", "Автоэкспорт встреч")) {
                    settingsSwitch(isOn: appState.config.autoExportMarkdownEnabled) { newValue in
                        controller.updateConfig { $0.autoExportMarkdownEnabled = newValue }
                    }
                }
                if appState.config.autoExportMarkdownEnabled {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Destination folder", "Папка назначения")) {
                        autoExportFolderPicker
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("Content", "Содержимое")) {
                        settingsMenu(
                            selection: appState.config.resolvedAutoExportMarkdownContent.displayName,
                            options: MeetingExportContent.allCases.map(\.displayName)
                        ) { label in
                            guard let index = MeetingExportContent.allCases.firstIndex(where: { $0.displayName == label }) else { return }
                            let content = MeetingExportContent.allCases[index]
                            controller.updateConfig { $0.autoExportMarkdownContent = content.rawValue }
                        }
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(tr("File format", "Формат файла")) {
                        settingsMenu(
                            selection: appState.config.resolvedAutoExportFileFormat.displayName,
                            options: MeetingAutoExportFileFormat.allCases.map(\.displayName)
                        ) { label in
                            guard let format = MeetingAutoExportFileFormat.allCases.first(where: { $0.displayName == label }) else { return }
                            controller.updateConfig { $0.autoExportFileFormat = format.rawValue }
                        }
                    }
                }
                Text(tr("Automatically saves each completed meeting to the chosen folder in the selected format.", "Автоматически сохраняет каждую завершённую встречу в выбранную папку в выбранном формате."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.horizontal, MuesliTheme.spacing16)
            }

            settingsSection(tr("Meeting Notifications", "Уведомления о встречах")) {
                settingsRow(tr("Scheduled meetings", "Запланированные встречи")) {
                    settingsSwitch(isOn: appState.config.showScheduledMeetingNotifications) { newValue in
                        controller.updateConfig { $0.showScheduledMeetingNotifications = newValue }
                    }
                }
                settingsDescription(tr("Show notifications for calendar meetings with a join link.", "Показывать уведомления о встречах из календаря со ссылкой для подключения."))

                if appState.config.showScheduledMeetingNotifications {
                    Divider().background(MuesliTheme.surfaceBorder)

                    settingsRow(tr("Reminder timing", "Время напоминания")) {
                        settingsMenu(
                            selection: scheduledMeetingLeadTimeLabel(for: appState.config.scheduledMeetingNotificationLeadTime),
                            options: ScheduledMeetingNotificationLeadTime.allCases.map(scheduledMeetingLeadTimeLabel(for:))
                        ) { label in
                            guard let leadTime = scheduledMeetingLeadTime(for: label) else { return }
                            controller.updateConfig { $0.scheduledMeetingNotificationLeadTime = leadTime }
                        }
                    }
                    settingsDescription(tr("At start time avoids early calendar-only prompts before you join.", "«В момент начала» позволяет избежать ранних напоминаний из календаря до подключения."))
                }

                Divider().background(MuesliTheme.surfaceBorder)

                settingsRow(tr("Auto-detected meetings", "Автоматически обнаруженные встречи")) {
                    settingsSwitch(isOn: appState.config.showMeetingDetectionNotification) { newValue in
                        controller.updateConfig { $0.showMeetingDetectionNotification = newValue }
                    }
                }
                settingsDescription(tr("Show notifications when a call is detected from browser, camera, microphone, or app audio activity.", "Показывать уведомления, когда звонок обнаружен по активности браузера, камеры, микрофона или звука приложения."))

                if appState.config.showMeetingDetectionNotification {
                    Divider().background(MuesliTheme.surfaceBorder)
                    mutedMeetingDetectionAppsControl
                }
            }

            settingsSection(tr("Calendars", "Календари")) {
                settingsRow(tr("Upcoming meetings", "Предстоящие встречи"), controlWidth: meetingControlWidth) {
                    settingsMenu(
                        selection: selectedUpcomingMeetingsWindow.label,
                        options: UpcomingMeetingsWindow.allCases.map(\.label)
                    ) { label in
                        guard let window = UpcomingMeetingsWindow.allCases.first(where: { $0.label == label }) else { return }
                        controller.updateUpcomingMeetingsWindow(dayCount: window.dayCount)
                    }
                }
                settingsDescription(tr("Controls how many calendar days appear in Coming Up, the menu bar, and scheduled meeting checks.", "Определяет, сколько календарных дней отображается в разделе «Скоро», строке меню и проверках запланированных встреч."))
                Divider().background(MuesliTheme.surfaceBorder)
                calendarSourcesControl
                    .padding(.bottom, MuesliTheme.spacing8)
            }

            if appState.isGoogleCalendarAvailable {
                settingsSection(tr("Calendar", "Календарь")) {
                    settingsRow("Google Calendar") {
                        googleCalendarControl
                    }
                }
            }

            settingsSection(tr("Advanced", "Дополнительно")) {
                settingsRow(tr("Enable post-meeting hook", "Включить хук после встречи"), controlWidth: meetingControlWidth) {
                    settingsSwitch(isOn: appState.config.meetingHookEnabled) { newValue in
                        controller.updateConfig { $0.meetingHookEnabled = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Hook script", "Скрипт хука"), controlWidth: meetingControlWidth) {
                    meetingHookPathPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Timeout", "Тайм-аут"), controlWidth: meetingControlWidth) {
                    meetingHookTimeoutControl
                }
                settingsDescription(tr("Runs a user-supplied executable after each completed meeting. The executable receives JSON on stdin and must already be runnable on its own.", "Запускает указанный пользователем исполняемый файл после каждой завершённой встречи. Файл получает JSON на stdin и должен запускаться самостоятельно."))
            }
            .padding(.top, MuesliTheme.spacing8)
        }
        .onAppear {
            refreshMeetingCalendarSourcesIfNeeded()
        }
    }

    private var appearanceSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(tr("Theme", "Тема")) {
                settingsRow(tr("App theme", "Тема приложения")) {
                    Picker("", selection: Binding(
                        get: { appState.config.darkMode },
                        set: { newValue in
                            controller.updateConfig { $0.darkMode = newValue }
                        }
                    )) {
                        Text(tr("Light", "Светлая")).tag(false)
                        Text(tr("Dark", "Тёмная")).tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: controlWidth)
                }
            }

            settingsSection(tr("Floating Indicator", "Плавающий индикатор")) {
                settingsRow(tr("Show floating indicator", "Показывать плавающий индикатор")) {
                    settingsSwitch(isOn: appState.config.showFloatingIndicator) { newValue in
                        controller.updateConfig { $0.showFloatingIndicator = newValue }
                        controller.refreshIndicatorVisibility()
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Indicator position", "Положение индикатора")) {
                    let isCustom = appState.config.indicatorAnchor == .custom
                    let selection = isCustom ? customIndicatorPositionLabel : appState.config.indicatorAnchor.label
                    let options = (isCustom ? [customIndicatorPositionLabel] : [])
                        + IndicatorAnchor.allCases.filter { $0 != .custom }.map(\.label)
                    settingsMenu(
                        selection: selection,
                        options: options
                    ) { label in
                        if label == customIndicatorPositionLabel { return }
                        guard let anchor = IndicatorAnchor.allCases.first(where: { $0.label == label }) else { return }
                        controller.updateConfig { $0.indicatorAnchor = anchor }
                        controller.refreshIndicatorVisibility()
                    }
                }
            }

            settingsSection(tr("Appearance", "Оформление")) {
                settingsRow(tr("Dark mode", "Тёмная тема")) {
                    settingsSwitch(isOn: appState.config.darkMode) { newValue in
                        controller.updateConfig { $0.darkMode = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Menu bar icon", "Значок в строке меню")) {
                    menuBarIconPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Accent color", "Акцентный цвет")) {
                    glassTintPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Play sound effects", "Звуковые эффекты")) {
                    settingsSwitch(isOn: appState.config.soundEnabled) { newValue in
                        controller.updateConfig { $0.soundEnabled = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(tr("Show next meeting in menu bar", "Показывать следующую встречу в строке меню")) {
                    settingsSwitch(isOn: appState.config.showNextMeetingInMenuBar) { newValue in
                        controller.updateConfig { $0.showNextMeetingInMenuBar = newValue }
                    }
                }
            }

            if appState.config.maraudersMapUnlocked {
                settingsSection(tr("Marauder\u{2019}s Map", "Карта Мародёров")) {
                    settingsRow(tr("Meeting countdown audio", "Звук обратного отсчёта встречи")) {
                        maraudersMapControl
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow("") {
                        Button {
                            SoundController.stopMaraudersMapClip()
                            isPreviewingClip = false
                            controller.resetMaraudersMap()
                        } label: {
                            Text(tr("Mischief Managed", "Шалость удалась"))
                                .font(.system(size: 11))
                                .foregroundColor(MuesliTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var glassTintPicker: some View {
        HStack(spacing: 6) {
            ForEach(Self.accentPresets, id: \.hex) { preset in
                let isSelected = appState.config.recordingColorHex.lowercased() == preset.hex
                Button {
                    controller.updateConfig { $0.recordingColorHex = preset.hex }
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                        )
                        .overlay(
                            Circle().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }

    private var menuBarIconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(MenuBarIconRenderer.options, id: \.id) { option in
                    let isSelected = appState.config.menuBarIcon == option.id
                    Button {
                        controller.updateConfig { $0.menuBarIcon = option.id }
                    } label: {
                        Group {
                            if option.id == "muesli",
                               let img = MenuBarIconRenderer.make(choice: "muesli") {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: option.id)
                                    .font(.system(size: 12))
                            }
                        }
                        .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(isSelected ? 0.3 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                }
            }
        }
    }

    @ViewBuilder
    private var chatGPTAccountControl: some View {
        if appState.isChatGPTAuthenticated {
            Button {
                controller.signOutChatGPT()
            } label: {
                HStack(spacing: 5) {
                    OpenAILogoShape()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                    Text(tr("Signed in · Sign Out", "Вход выполнен · Выйти"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        } else if isSigningInChatGPT {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(tr("Signing in...", "Выполняется вход..."))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isSigningInChatGPT = true
                    chatGPTSignInError = nil
                    Task {
                        let error = await controller.signInWithChatGPT()
                        isSigningInChatGPT = false
                        chatGPTSignInError = error
                    }
                } label: {
                    HStack(spacing: 5) {
                        OpenAILogoShape()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                        Text(tr("Sign in with ChatGPT", "Войти через ChatGPT"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)

                if let chatGPTSignInError {
                    Text(chatGPTSignInError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var googleCalendarControl: some View {
        if appState.isGoogleCalendarAuthenticated {
            Button {
                controller.signOutGoogleCalendar()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                    Text(tr("Connected · Disconnect", "Подключено · Отключить"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        } else if isSigningInGoogleCal {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(tr("Connecting...", "Подключение..."))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
        } else if !appState.isGoogleCalendarVerified {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(tr("Connect Google Calendar", "Подключить Google Calendar"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.textTertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                Text(tr("Google OAuth verification pending", "Ожидается проверка Google OAuth"))
                    .font(.system(size: 10))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isSigningInGoogleCal = true
                    googleCalSignInError = nil
                    Task {
                        let error = await controller.signInWithGoogleCalendar()
                        isSigningInGoogleCal = false
                        googleCalSignInError = error
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                        Text(tr("Connect Google Calendar", "Подключить Google Calendar"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)

                if let googleCalSignInError {
                    Text(googleCalSignInError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    private var maraudersMapControl: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            settingsMenu(
                selection: SoundController.labelForClip(
                    id: appState.config.maraudersMapAudioClip,
                    customPath: appState.config.maraudersMapCustomAudioPath
                ),
                options: SoundController.maraudersMapClipLabels
            ) { label in
                if label == "Custom\u{2026}" {
                    pickCustomAudioFile()
                } else if let preset = SoundController.maraudersMapPresets
                    .first(where: { $0.label == label }) {
                    SoundController.stopMaraudersMapClip()
                    isPreviewingClip = false
                    controller.updateConfig {
                        $0.maraudersMapAudioClip = preset.id
                        $0.maraudersMapCustomAudioPath = nil
                    }
                    controller.updateMaraudersMapAudioClip()
                }
            }
            Button {
                if isPreviewingClip {
                    SoundController.stopMaraudersMapClip()
                    isPreviewingClip = false
                } else {
                    SoundController.playMaraudersMapClip(
                        id: appState.config.maraudersMapAudioClip,
                        customPath: appState.config.maraudersMapCustomAudioPath
                    ) {
                        isPreviewingClip = false
                    }
                    isPreviewingClip = true
                }
            } label: {
                Image(systemName: isPreviewingClip ? "stop.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundColor(MuesliTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Marauder's Map

    private func pickCustomAudioFile() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose an audio clip", "Выберите аудиоклип")
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let appSupportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fputs("[muesli-native] Could not resolve Application Support directory\n", stderr)
            return
        }

        do {
            let supportDir = appSupportBase
                .appendingPathComponent(Bundle.main.infoDictionary?["MuesliSupportDirectoryName"] as? String ?? "Muesli")
            let destPath = try SoundController.importCustomClip(from: url, supportDir: supportDir)
            controller.updateConfig {
                $0.maraudersMapAudioClip = SoundController.customClipID
                $0.maraudersMapCustomAudioPath = destPath
            }
            controller.updateMaraudersMapAudioClip()
        } catch {
            fputs("[muesli-native] Failed to import custom audio: \(error)\n", stderr)
        }
    }

    private func pickMeetingHookFile() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose a hook script", "Выберите скрипт хука")
        panel.prompt = tr("Choose Script", "Выбрать")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = preferredMeetingHookDirectoryURL()

        presentOpenPanel(panel) { url in
            controller.updateConfig { $0.meetingHookPath = url.standardizedFileURL.path }
        }
    }

    private func pickAutoExportFolder() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose a folder for exported notes", "Выберите папку для экспортируемых заметок")
        panel.prompt = tr("Choose Folder", "Выбрать")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferredAutoExportDirectoryURL()

        presentOpenPanel(panel) { url in
            controller.updateConfig { $0.autoExportMarkdownFolderPath = url.standardizedFileURL.path }
        }
    }

    private func preferredAutoExportDirectoryURL() -> URL {
        let configuredPath = appState.config.autoExportMarkdownFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath).standardizedFileURL
            if FileManager.default.fileExists(atPath: configuredURL.path) {
                return configuredURL
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    }

    private func preferredMeetingHookDirectoryURL() -> URL {
        let configuredPath = appState.config.meetingHookPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath).standardizedFileURL
            let parentDirectory = configuredURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentDirectory.path) {
                return parentDirectory
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private func presentOpenPanel(_ panel: NSOpenPanel, onPick: @escaping (URL) -> Void) {
        NSApp.activate()
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        settingsSection(tr("Permissions", "Разрешения")) {
            permissionStatusRow(
                tr("Microphone", "Микрофон"),
                granted: micGranted,
                action: { AVCaptureDevice.requestAccess(for: .audio) { _ in } },
                pane: "Privacy_Microphone"
            )
            Divider().background(MuesliTheme.surfaceBorder)
            permissionStatusRow(
                tr("Accessibility", "Универсальный доступ"),
                granted: accessibilityGranted,
                action: {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(opts)
                },
                pane: "Privacy_Accessibility"
            )
            Divider().background(MuesliTheme.surfaceBorder)
            permissionStatusRow(
                tr("Input Monitoring", "Мониторинг ввода"),
                granted: inputMonitoringGranted,
                action: {
                    if !CGRequestListenEventAccess() {
                        openPrivacyPane("Privacy_ListenEvent")
                    }
                },
                pane: "Privacy_ListenEvent"
            )
            Divider().background(MuesliTheme.surfaceBorder)
            permissionStatusRow(
                tr("Screen Recording", "Запись экрана"),
                granted: screenRecordingGranted,
                action: { CGRequestScreenCaptureAccess() },
                pane: "Privacy_ScreenCapture"
            )
            if appState.config.useCoreAudioTap {
                Divider().background(MuesliTheme.surfaceBorder)
                permissionStatusRow(
                    tr("System Audio", "Системный звук"),
                    granted: systemAudioGranted,
                    action: {
                        Task { await CoreAudioSystemRecorder.requestSystemAudioAccess() }
                    },
                    pane: "Privacy_ScreenCapture"
                )
            }
        }
    }

    @ViewBuilder
    private func permissionStatusRow(_ name: String, granted: Bool, action: @escaping () -> Void, pane: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(granted ? MuesliTheme.success : MuesliTheme.recording)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
            }
            Spacer()
            if granted {
                Text(tr("Granted", "Предоставлено"))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.success)
            } else {
                Button(tr("Grant", "Предоставить")) {
                    action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(MuesliTheme.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            Button {
                openPrivacyPane(pane)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(tr("Open in System Settings", "Открыть в Системных настройках"))
        }
        .frame(minHeight: 32)
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private func screenContextControl(width: CGFloat? = nil) -> some View {
        if accessibilityGranted {
            settingsSwitch(isOn: appState.config.enableScreenContext) { newValue in
                handleScreenContextToggle(newValue)
            }
            .frame(width: width, alignment: .trailing)
        } else {
            Button {
                handleScreenContextToggle(true)
            } label: {
                Text(tr("Grant", "Предоставить"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.accent)
                    .frame(width: width)
                    .frame(minHeight: 32)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        }
    }

    @discardableResult
    private func handleScreenContextToggle(_ enabled: Bool) -> Bool {
        guard enabled else {
            clearPendingScreenContextEnable()
            controller.updateConfig { $0.enableScreenContext = false }
            return false
        }

        guard accessibilityGranted else {
            pendingScreenContextEnable = true
            pendingScreenContextRequestedAt = Date().timeIntervalSince1970
            let granted = controller.requestScreenContextEnable()
            accessibilityGranted = AXIsProcessTrusted()
            if granted || accessibilityGranted {
                clearPendingScreenContextEnable()
            }
            return granted || accessibilityGranted
        }

        clearPendingScreenContextEnable()
        return controller.requestScreenContextEnable()
    }

    private func handleDictionaryCorrectionPromptsToggle(_ enabled: Bool) {
        if controller.setDictionaryCorrectionPromptsFromToggle(enabled) == .needsAccessibilityPermission {
            isShowingDictionaryAccessibilityPrompt = true
        }
    }

    private func startPermissionPolling() {
        refreshPermissionStatuses(refreshLaunchAtLogin: true)
        permissionPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshPermissionStatuses()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func refreshPermissionStatuses(refreshLaunchAtLogin: Bool = false) {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        controller.reconcilePendingDictionaryCorrectionAccessibilityEnable()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        if refreshLaunchAtLogin {
            controller.refreshLaunchAtLoginState()
        }
        if accessibilityGranted && pendingScreenContextEnable {
            if controller.requestScreenContextEnable() {
                clearPendingScreenContextEnable()
            }
        }
        if !accessibilityGranted && isPendingScreenContextGrantExpired {
            clearPendingScreenContextEnable()
        }
        if !accessibilityGranted && appState.config.enableScreenContext {
            clearPendingScreenContextEnable()
            controller.updateConfig { $0.enableScreenContext = false }
        }
        controller.reclassifyVoiceNotesAsDictationIfReady(
            microphoneGranted: micGranted,
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted
        )
        refreshSystemAudioPermissionIfNeeded()
    }

    private var isPendingScreenContextGrantExpired: Bool {
        guard pendingScreenContextEnable else { return false }
        guard pendingScreenContextRequestedAt > 0 else { return true }
        return Date().timeIntervalSince1970 - pendingScreenContextRequestedAt > screenContextGrantIntentTimeout
    }

    private func clearPendingScreenContextEnable() {
        pendingScreenContextEnable = false
        pendingScreenContextRequestedAt = 0
    }

    private func refreshSystemAudioPermissionIfNeeded() {
        guard appState.config.useCoreAudioTap, !isCheckingSystemAudioPermission else { return }
        isCheckingSystemAudioPermission = true

        Task {
            let granted = await Task.detached(priority: .utility) {
                CoreAudioSystemRecorder.checkSystemAudioPermission()
            }.value
            await MainActor.run {
                self.systemAudioGranted = granted
                self.isCheckingSystemAudioPermission = false
            }
        }
    }

    // MARK: - Layout Primitives

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuesliTheme.textTertiary)
                .textCase(.uppercase)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(MuesliTheme.spacing16)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    /// Standardized row: label on left, control on right.
    /// Controls share a fixed-width column so they all right-align consistently.
    @ViewBuilder
    private func settingsRow(_ label: String, controlWidth rowControlWidth: CGFloat? = nil, @ViewBuilder control: () -> some View) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .center) {
            Text(label)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .layoutPriority(1)
            Spacer(minLength: 20)
            ZStack(alignment: .trailing) {
                // Invisible spacer forces the ZStack to exactly controlWidth
                Color.clear.frame(width: width, height: 1)
                control()
                    .frame(maxWidth: width)
            }
        }
        .frame(minHeight: 32)
    }

    @ViewBuilder
    private func settingsRow(
        _ label: String,
        description: String,
        controlWidth rowControlWidth: CGFloat? = nil,
        @ViewBuilder control: () -> some View
    ) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(description)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            control()
                .frame(width: width, alignment: .trailing)
        }
        .frame(minHeight: 44)
    }

    private func settingsDescription(_ text: String) -> some View {
        Text(text)
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textTertiary)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.top, -4)
            .padding(.bottom, MuesliTheme.spacing8)
    }

    // MARK: - Controls

    @ViewBuilder
    private func settingsSwitch(isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
                .toggleStyle(.switch)
                .tint(MuesliTheme.accent)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func settingsMenu(selection: String, options: [String], onChange: @escaping (String) -> Void) -> some View {
        FixedWidthPopUp(selection: selection, options: options, onChange: onChange)
            .frame(height: 24)
    }

    private var mutedMeetingDetectionAppsControl: some View {
        let muted = Set(appState.config.mutedMeetingDetectionAppBundleIDs)
        return VStack(alignment: .leading, spacing: 10) {
            Text(tr("Don't notify me when a call is detected in these apps:", "Не уведомлять при обнаружении звонка в этих приложениях:"))
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], alignment: .leading, spacing: 8) {
                ForEach(meetingDetectionAppOptions) { app in
                    mutedDetectionAppButton(app, isMuted: muted.contains(app.bundleID))
                }
            }
        }
        .padding(.leading, MuesliTheme.spacing16)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(MuesliTheme.surfaceBorder)
                .frame(width: 2)
        }
    }

    private func mutedDetectionAppButton(_ app: MeetingDetectionAppOption, isMuted: Bool) -> some View {
        Button {
            updateMutedMeetingDetectionApp(app.bundleID, isMuted: !isMuted)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isMuted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isMuted ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 16)
                Image(systemName: app.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .frame(width: 14)
                Text(app.name)
                    .font(.system(size: 12))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isMuted ? MuesliTheme.accentSubtle : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(isMuted ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func updateMutedMeetingDetectionApp(_ bundleID: String, isMuted: Bool) {
        controller.updateConfig { config in
            var muted = Set(config.mutedMeetingDetectionAppBundleIDs)
            if isMuted {
                muted.insert(bundleID)
            } else {
                muted.remove(bundleID)
            }
            config.mutedMeetingDetectionAppBundleIDs = muted.sorted()
        }
    }

    // MARK: - Calendars

    private struct CalendarToggleItem: Identifiable, Equatable {
        let id: String
        let title: String
        let colorHex: String?
        let isEnabled: Bool
    }

    private struct CalendarSourceGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let iconName: String
        let items: [CalendarToggleItem]
    }

    private var calendarSourceGroups: [CalendarSourceGroup] {
        let disabled = Set(appState.config.disabledCalendarIDs)
        var groups: [CalendarSourceGroup] = []

        let ekBySource = Dictionary(grouping: appState.availableEventKitCalendars) { $0.sourceTitle }
        for sourceTitle in ekBySource.keys.sorted() {
            let items = (ekBySource[sourceTitle] ?? [])
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .map { cal in
                    CalendarToggleItem(
                        id: cal.id,
                        title: cal.title,
                        colorHex: cal.colorHex,
                        isEnabled: !disabled.contains(cal.id)
                    )
                }
            groups.append(CalendarSourceGroup(
                id: "ek::\(sourceTitle)",
                title: sourceTitle,
                subtitle: calendarSourceSubtitle(for: sourceTitle),
                iconName: calendarSourceIconName(for: sourceTitle),
                items: items
            ))
        }

        if appState.isGoogleCalendarAuthenticated && !appState.availableGoogleCalendars.isEmpty {
            let items = appState.availableGoogleCalendars.map { cal in
                CalendarToggleItem(
                    id: cal.id,
                    title: cal.summary + (cal.isPrimary ? tr(" (Primary)", " (основной)") : ""),
                    colorHex: cal.colorHex,
                    isEnabled: !disabled.contains(cal.id)
                )
            }
            groups.append(CalendarSourceGroup(
                id: "google_oauth",
                title: "Google Calendar",
                subtitle: tr("Connected directly to Muesli", "Подключено напрямую к Muesli"),
                iconName: "calendar.badge.plus",
                items: items
            ))
        }

        return groups
    }

    private var calendarSourcesControl: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            Text(tr("Calendar sources are listed first, with their calendars underneath. Disabled calendars are hidden from Muesli — no notifications, no Coming Up, no meeting detection.", "Сначала перечислены источники календарей, под ними — их календари. Отключённые календари скрыты из Muesli: без уведомлений, без раздела «Скоро», без обнаружения встреч."))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if calendarSourceGroups.isEmpty {
                Text(tr("No calendars detected. Make sure Calendar permission is granted in System Settings > Privacy & Security > Calendars.", "Календари не обнаружены. Убедитесь, что разрешение «Календарь» предоставлено в Системных настройках > Конфиденциальность и безопасность > Календари."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(calendarSourceGroups) { group in
                    calendarSourceGroupView(group)
                }
            }

            if appState.isGoogleCalendarAuthenticated && !appState.availableEventKitCalendars.isEmpty {
                Text(tr("Google calendars may appear once from macOS Calendar and once from Muesli's Google connection. Turn off both copies to hide that calendar completely.", "Календари Google могут отображаться дважды: из Календаря macOS и из подключения Google в Muesli. Отключите обе копии, чтобы полностью скрыть календарь."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.isGoogleCalendarAuthenticated {
                googleCalendarListLoadStateView
            }
        }
    }

    @ViewBuilder
    private func calendarSourceGroupView(_ group: CalendarSourceGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: group.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)

                    Text(tr("\(group.subtitle) • \(group.items.count) \(group.items.count == 1 ? "calendar" : "calendars")", "\(group.subtitle) • календарей: \(group.items.count)"))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], alignment: .leading, spacing: 8) {
                ForEach(group.items) { item in
                    calendarToggleButton(item)
                }
            }
            .padding(.leading, 28)
        }
        .padding(.vertical, 2)
    }

    private func calendarSourceSubtitle(for sourceTitle: String) -> String {
        let normalized = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "icloud" {
            return tr("iCloud account in macOS Calendar", "Аккаунт iCloud в Календаре macOS")
        }
        if normalized == "subscribed calendars" {
            return tr("Subscribed in macOS Calendar", "Подписка в Календаре macOS")
        }
        if normalized == "other" {
            return tr("System calendars from macOS", "Системные календари macOS")
        }
        return tr("Calendar account in macOS", "Аккаунт календаря в macOS")
    }

    private func calendarSourceIconName(for sourceTitle: String) -> String {
        let normalized = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "icloud" {
            return "icloud"
        }
        if normalized == "subscribed calendars" {
            return "calendar.badge.clock"
        }
        if normalized == "other" {
            return "person.crop.circle.badge.clock"
        }
        return "calendar"
    }

    private func calendarToggleButton(_ item: CalendarToggleItem) -> some View {
        Button {
            updateDisabledCalendar(item.id, isDisabled: item.isEnabled)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.isEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.isEnabled ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 16)
                Circle()
                    .fill(item.colorHex.map { Color(hex: $0) } ?? MuesliTheme.textTertiary)
                    .frame(width: 8, height: 8)
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(item.isEnabled ? MuesliTheme.textPrimary : MuesliTheme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var googleCalendarListLoadStateView: some View {
        switch appState.googleCalendarListLoadState {
        case .loading:
            Text(tr("Loading Google calendars…", "Загрузка календарей Google…"))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
        case .failed(let message):
            HStack(spacing: 8) {
                Text(tr("Failed to load Google calendars: \(message)", "Не удалось загрузить календари Google: \(message)"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                Button(tr("Retry", "Повторить")) {
                    Task { await controller.refreshGoogleCalendarList() }
                }
                .buttonStyle(.link)
                .font(MuesliTheme.caption())
            }
        case .idle, .loaded:
            EmptyView()
        }
    }

    private func refreshMeetingCalendarSourcesIfNeeded() {
        guard !hasRefreshedMeetingCalendarSources else { return }
        hasRefreshedMeetingCalendarSources = true
        controller.refreshAvailableEventKitCalendars()
        Task { await controller.refreshGoogleCalendarList() }
    }

    private func updateDisabledCalendar(_ calendarID: String, isDisabled: Bool) {
        controller.updateConfig { config in
            var disabled = Set(config.disabledCalendarIDs)
            if isDisabled {
                disabled.insert(calendarID)
            } else {
                disabled.remove(calendarID)
            }
            config.disabledCalendarIDs = disabled.sorted()
        }
        Task { await controller.refreshUpcomingCalendarEvents() }
    }

    @ViewBuilder
    private var autoExportFolderPicker: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)

                if appState.config.autoExportMarkdownFolderPath.isEmpty {
                    Text(tr("Choose a folder…", "Выберите папку…"))
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(appState.config.autoExportMarkdownFolderPath)
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .help(appState.config.autoExportMarkdownFolderPath.isEmpty ? tr("No destination folder selected", "Папка назначения не выбрана") : appState.config.autoExportMarkdownFolderPath)

            if !appState.config.autoExportMarkdownFolderPath.isEmpty {
                Button {
                    controller.updateConfig { $0.autoExportMarkdownFolderPath = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Clear destination folder", "Очистить папку назначения"))
                .help(tr("Clear destination folder", "Очистить папку назначения"))
            }

            Button {
                pickAutoExportFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Choose destination folder", "Выбрать папку назначения"))
            .help(tr("Choose destination folder", "Выбрать папку назначения"))
        }
    }

    @ViewBuilder
    private var meetingHookPathPicker: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)

                if appState.config.meetingHookPath.isEmpty {
                    Text(tr("Choose a script…", "Выберите скрипт…"))
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(appState.config.meetingHookPath)
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .help(appState.config.meetingHookPath.isEmpty ? tr("No hook script selected", "Скрипт хука не выбран") : appState.config.meetingHookPath)

            if !appState.config.meetingHookPath.isEmpty {
                Button {
                    controller.updateConfig { $0.meetingHookPath = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(tr("Clear hook script", "Очистить скрипт хука"))
            }

            Button {
                pickMeetingHookFile()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(tr("Choose hook script", "Выбрать скрипт хука"))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var meetingHookTimeoutControl: some View {
        Stepper(
            value: Binding(
                get: { max(appState.config.meetingHookTimeoutSeconds, 1) },
                set: { newValue in
                    controller.updateConfig { $0.meetingHookTimeoutSeconds = max(newValue, 1) }
                }
            ),
            in: 1...600
        ) {
            Text(tr("\(max(appState.config.meetingHookTimeoutSeconds, 1)) seconds", "\(max(appState.config.meetingHookTimeoutSeconds, 1)) сек."))
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 92, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func meetingTemplateMenu(selectionID: String, onChange: @escaping (String) -> Void) -> some View {
        let allItems: [(id: String, label: String)] = {
            var items: [(String, String)] = [(MeetingTemplates.autoID, MeetingTemplates.auto.title)]
            items += controller.builtInMeetingTemplates().map { ($0.id, $0.title) }
            items += controller.customOnlyMeetingTemplates().map { ($0.id, $0.name) }
            return items
        }()
        let selectedLabel = allItems.first(where: { $0.id == selectionID })?.label ?? tr("Auto", "Авто")
        FixedWidthPopUp(
            selection: selectedLabel,
            options: allItems.map(\.label),
            onSelectIndex: { index in
                guard index >= 0 && index < allItems.count else { return }
                onChange(allItems[index].id)
            }
        )
        .frame(height: 24)
    }

    @ViewBuilder
    private func settingsModelMenu(currentModel: String, presets: [SummaryModelPreset], onChange: @escaping (String) -> Void) -> some View {
        let menuPresets = SummaryModelPreset.menuPresets(presets, currentModel: currentModel)
        let effectiveModel = currentModel.isEmpty ? (presets.first?.id ?? "") : currentModel
        let selectedLabel = menuPresets.first(where: { $0.id == effectiveModel })?.label ?? menuPresets.first?.label ?? ""
        FixedWidthPopUp(
            selection: selectedLabel,
            options: menuPresets.map(\.label),
            onSelectIndex: { index in
                guard index >= 0 && index < menuPresets.count else { return }
                let selectedId = menuPresets[index].id
                onChange(selectedId == presets.first?.id ? "" : selectedId)
            }
        )
        .frame(height: 24)
    }

    @ViewBuilder
    private func settingsModelTextField(currentModel: String, placeholder: String, onChange: @escaping (String) -> Void) -> some View {
        PastableTextField(
            text: currentModel,
            placeholder: placeholder,
            onChange: { value in
                onChange(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
        .frame(height: 22)
    }

    @ViewBuilder
    private var openRouterFreeModelMenu: some View {
        if isLoadingOpenRouterFreeModels {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(tr("Loading models", "Загрузка моделей"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else if !openRouterFreeModels.isEmpty {
            settingsModelMenu(
                currentModel: appState.config.openRouterModel,
                presets: openRouterFreeModels
            ) { val in controller.updateConfig { $0.openRouterModel = val } }
        } else {
            HStack(spacing: 8) {
                if let openRouterFreeModelsError {
                    Text(openRouterFreeModelsError)
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                }
                Button(tr("Load", "Загрузить")) {
                    loadOpenRouterFreeModels(force: true)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func loadOpenRouterFreeModelsIfNeeded() {
        guard openRouterFreeModels.isEmpty, !isLoadingOpenRouterFreeModels else { return }
        loadOpenRouterFreeModels(force: false)
    }

    private func loadOpenRouterFreeModels(force: Bool) {
        guard force || openRouterFreeModels.isEmpty else { return }
        isLoadingOpenRouterFreeModels = true
        openRouterFreeModelsError = nil

        Task {
            do {
                let url = URL(string: "https://openrouter.ai/api/v1/models?output_modalities=text")!
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let catalog = try JSONDecoder().decode(OpenRouterModelCatalog.self, from: data)
                let presets = OpenRouterModelCatalogFilter.freeTextSummaryPresets(from: catalog.data)

                await MainActor.run {
                    openRouterFreeModels = presets
                    openRouterFreeModelsError = presets.isEmpty ? tr("No free text models found", "Бесплатные текстовые модели не найдены") : nil
                    isLoadingOpenRouterFreeModels = false
                }
            } catch {
                await MainActor.run {
                    openRouterFreeModels = []
                    openRouterFreeModelsError = tr("Could not load", "Не удалось загрузить")
                    isLoadingOpenRouterFreeModels = false
                }
            }
        }
    }

    @ViewBuilder
    private func keyStatusRow(key: String) -> some View {
        HStack(spacing: 6) {
            Spacer()
            Circle()
                .fill(key.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
                .frame(width: 6, height: 6)
            Text(key.isEmpty ? tr("No API key configured", "API-ключ не настроен") : tr("Key configured", "Ключ настроен"))
                .font(.system(size: 11))
                .foregroundStyle(key.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
        }
        .frame(minHeight: 20)
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            HStack(spacing: MuesliTheme.spacing8) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isDestructive ? MuesliTheme.recording : MuesliTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MuesliTheme.spacing16)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(isDestructive ? MuesliTheme.recording.opacity(0.1) : MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(
                            isDestructive ? MuesliTheme.recording.opacity(0.2) : MuesliTheme.surfaceBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func recordingSaveLabel(for policy: MeetingRecordingSavePolicy) -> String {
        switch policy {
        case .never:
            return tr("Never", "Никогда")
        case .prompt:
            return tr("Ask every time", "Спрашивать каждый раз")
        case .always:
            return tr("Always", "Всегда")
        }
    }

    private func recordingSavePolicy(for label: String) -> MeetingRecordingSavePolicy? {
        let policy = MeetingRecordingSavePolicy.allCases.first { recordingSaveLabel(for: $0) == label }
        if policy == nil {
            assertionFailure("Unexpected recording save label: \(label)")
        }
        return policy
    }

    private func recordingFileFormatLabel(for format: MeetingRecordingFileFormat) -> String {
        format.displayName
    }

    private func recordingFileFormat(for label: String) -> MeetingRecordingFileFormat? {
        let format = MeetingRecordingFileFormat.allCases.first { recordingFileFormatLabel(for: $0) == label }
        if format == nil {
            assertionFailure("Unexpected recording file format label: \(label)")
        }
        return format
    }

    private func scheduledMeetingLeadTimeLabel(for leadTime: ScheduledMeetingNotificationLeadTime) -> String {
        switch leadTime {
        case .atStart:
            return tr("At start time", "В момент начала")
        case .oneMinute:
            return tr("1 min before", "За 1 мин")
        case .threeMinutes:
            return tr("3 min before", "За 3 мин")
        case .fiveMinutes:
            return tr("5 min before", "За 5 мин")
        }
    }

    private func scheduledMeetingLeadTime(for label: String) -> ScheduledMeetingNotificationLeadTime? {
        let leadTime = ScheduledMeetingNotificationLeadTime.allCases.first {
            scheduledMeetingLeadTimeLabel(for: $0) == label
        }
        if leadTime == nil {
            assertionFailure("Unexpected scheduled meeting notification lead time label: \(label)")
        }
        return leadTime
    }
}

// MARK: - Pastable Secure Field (NSViewRepresentable)

/// NSSecureTextField subclass that handles Cmd+V/C/X/A without needing a standard Edit menu.
/// Required because the app runs as .accessory (no menu bar), so key equivalents
/// don't route to text fields by default.
class EditableNSSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// NSPopUpButton wrapper that respects width constraints (SwiftUI Picker with .menu style ignores them).
struct FixedWidthPopUp: NSViewRepresentable {
    let selection: String
    let options: [String]
    /// Reports the selected index, avoiding label collision issues.
    let onSelectionIndex: (Int) -> Void

    init(selection: String, options: [String], onChange: @escaping (String) -> Void) {
        self.selection = selection
        self.options = options
        self.onSelectionIndex = { index in
            guard index >= 0 && index < options.count else { return }
            onChange(options[index])
        }
    }

    init(selection: String, options: [String], onSelectIndex: @escaping (Int) -> Void) {
        self.selection = selection
        self.options = options
        self.onSelectionIndex = onSelectIndex
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.removeAllItems()
        button.addItems(withTitles: options)
        button.selectItem(withTitle: selection)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let currentTitles = button.itemTitles
        if currentTitles != options {
            button.removeAllItems()
            button.addItems(withTitles: options)
        }
        if button.titleOfSelectedItem != selection {
            button.selectItem(withTitle: selection)
        }
        context.coordinator.onSelectionIndex = onSelectionIndex
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelectionIndex: onSelectionIndex) }

    class Coordinator: NSObject {
        var onSelectionIndex: (Int) -> Void
        init(onSelectionIndex: @escaping (Int) -> Void) { self.onSelectionIndex = onSelectionIndex }
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            onSelectionIndex(sender.indexOfSelectedItem)
        }
    }
}

/// A text field that supports Cmd+V paste and masks the value when not focused.
struct PastableSecureField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> EditableNSSecureTextField {
        let field = EditableNSSecureTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: EditableNSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onChange(field.stringValue)
        }
    }
}

/// Plain text field with the same accessory-app edit shortcuts as secure fields.
struct PastableTextField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> EditableNSTextField {
        let field = EditableNSTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: EditableNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onChange(field.stringValue)
        }
    }
}

private extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        h = h.hasPrefix("#") ? String(h.dropFirst()) : h
        guard h.count == 6, let value = UInt64(h, radix: 16) else {
            self = .black; return
        }
        self = Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

private extension NSColor {
    func toHexString() -> String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent   * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent  * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }
}
