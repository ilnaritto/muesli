import AppKit
import AVFoundation
import Charts
import CoreImage.CIFilterBuiltins
import SwiftUI
import TelemetryDeck
import MuesliCore

/// Home tab: overview dashboard and app features. Hosts the usage stats moved
/// from the Dictations page; richer analytics blocks land here later.
struct HomeView: View {
    private enum HomeSection: String, CaseIterable, Identifiable {
        case overview
        case insights
        case functions
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return tr("Overview", "Обзор")
            case .insights: return tr("Insights", "Инсайты")
            case .functions: return tr("Features", "Функции")
            case .about: return tr("About", "О программе")
            }
        }

        var icon: String {
            switch self {
            case .overview: return "chart.bar.xaxis"
            case .insights: return "sparkles"
            case .functions: return "puzzlepiece.extension.fill"
            case .about: return "info.circle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .overview: return Color(hex: 0x007AFF)   // blue
            case .insights: return Color(hex: 0x5856D6)   // indigo
            case .functions: return Color(hex: 0xAF52DE)  // purple
            case .about: return Color(hex: 0x8E8E93)      // gray
            }
        }
    }

    let appState: AppState
    let controller: MuesliController
    @State private var selectedSection: HomeSection = .overview
    @State private var bridgePromptSeen = false
    @State private var isBridgeQRCodePresented = false
    @State private var insightsDraft = ""
    @FocusState private var insightsInputFocused: Bool
    @State private var showInsightsDatePopover = false
    @State private var insightsCustomDate = Date()
    @State private var insightsHeaderMeasuredHeight: CGFloat?
    @State private var showClearInsightsHistoryConfirmation = false
    @State private var permissionStatus = FeaturePermissionStatus()
    @State private var showConnectModelSheet = false

    var body: some View {
        HStack(spacing: 5) {
            PrimaryColumn(appState: appState, title: tr("Home", "Главная")) {
                sectionList
            }

            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Task 5: land on Features once after onboarding, so a new user
            // sees the tour before the empty Overview stats. The permissions
            // wizard itself is a separate flow — untouched.
            if !appState.config.hasSeenFeaturesTour {
                selectedSection = .functions
                controller.updateConfig { $0.hasSeenFeaturesTour = true }
            }
        }
        .sheet(isPresented: $isBridgeQRCodePresented) {
            IPhoneBridgeQRCodeSheet(
                deepLinkURL: IPhoneBridgeLinks.iOSSyncDeepLinkURL,
                installURL: IPhoneBridgeLinks.installURL
            )
        }
        // Connecting a model right from the Функции page — per feedback
        // that it must be possible to turn things on/connect them here,
        // not just be sent off to Settings.
        .sheet(isPresented: $showConnectModelSheet) {
            AddModelSheet(controller: controller)
        }
    }

    @ViewBuilder
    private var sectionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(HomeSection.allCases) { section in
                    sectionRow(section)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, MuesliTheme.spacing12)
        }
    }

    private func sectionRow(_ section: HomeSection) -> some View {
        SidebarNavRow(
            icon: section.icon,
            iconColor: section.iconColor,
            title: section.title,
            isSelected: selectedSection == section
        ) {
            selectedSection = section
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            overviewContent
        case .insights:
            insightsContent
        case .functions:
            functionsContent
        case .about:
            AboutView(appState: appState, onOpenManualDiagnosticReport: { controller.openManualDiagnosticReport() })
        }
    }

    // MARK: - Insights (AI chat over all meetings)

    @ViewBuilder
    private var insightsContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView {
                        if appState.insightsChatHistory.isEmpty && !appState.insightsChatAwaiting {
                            insightsEmptyState
                        } else {
                            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                                ForEach(appState.insightsChatHistory) { turn in
                                    insightsBubble(turn).id(turn.id)
                                }
                                if appState.insightsChatAwaiting {
                                    insightsTypingBubble.id("insights-typing")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .contentMargins(.top, insightsHeaderClearance + MuesliTheme.spacing8, for: .scrollContent)
                    .contentMargins(.bottom, MuesliTheme.spacing20, for: .scrollContent)
                    .padding(.horizontal, MuesliTheme.spacing24)
                    .onChange(of: appState.insightsChatHistory.count) { _, _ in insightsScrollToBottom(proxy) }
                    .onChange(of: appState.insightsChatAwaiting) { _, _ in insightsScrollToBottom(proxy) }
                }

                insightsHeaderBackdropGradient
                insightsFloatingHeader
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        insightsHeaderMeasuredHeight = height
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.config.insightsHintsEnabled {
                insightsHintsRow
                    .padding(.horizontal, MuesliTheme.spacing24)
                    .padding(.top, MuesliTheme.spacing8)
            }

            insightsComposer
                .padding(.horizontal, MuesliTheme.spacing24)
                .padding(.top, MuesliTheme.spacing8)
                .padding(.bottom, MuesliTheme.spacing16)
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.15), value: appState.config.insightsHintsEnabled)
        .alert(tr("Clear History", "Очистить историю"), isPresented: $showClearInsightsHistoryConfirmation) {
            Button(tr("Clear", "Очистить"), role: .destructive) {
                appState.insightsChatHistory.removeAll()
            }
            Button(tr("Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(tr("This clears the conversation. Your date, folder, and model selection stay as they are.", "Это очистит переписку. Выбранные период, папка и модель останутся прежними."))
        }
    }

    // MARK: Insights — floating pill header (task 3)

    private var insightsHeaderClearance: CGFloat {
        insightsHeaderMeasuredHeight ?? 74
    }

    /// Soft fade under the floating pill so messages scrolling behind it
    /// dim out instead of getting clipped — mirrors `headerBackdropGradient`
    /// on the meeting page.
    private var insightsHeaderBackdropGradient: some View {
        LinearGradient(
            stops: [
                .init(color: MuesliTheme.backgroundDeep.opacity(0.7), location: 0),
                .init(color: MuesliTheme.backgroundDeep.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: insightsHeaderClearance + 20)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var insightsFloatingHeader: some View {
        HStack(alignment: .center, spacing: 11) {
            // Actual pill chip now, matching the meeting page's headerPill —
            // was bare text over the gradient before, which didn't read as
            // a pill at all.
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("Insights", "Инсайты"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(tr("Ask AI about your meetings", "Спроси ИИ про свои встречи"))
                    .font(.system(size: 10))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(MuesliTheme.backgroundBase))
            .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))

            insightsMoreMenu
        }
        .padding(.horizontal, MuesliTheme.spacing24)
        .padding(.top, MuesliTheme.spacing20)
        .padding(.bottom, MuesliTheme.spacing12)
    }

    private var insightsMoreMenu: some View {
        Menu {
            Button(role: .destructive) {
                showClearInsightsHistoryConfirmation = true
            } label: {
                Label(tr("Clear History", "Очистить историю"), systemImage: "trash")
            }
            .disabled(appState.insightsChatHistory.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 40, height: 40)
        .background(Circle().fill(MuesliTheme.backgroundBase))
        .overlay(Circle().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
        .contentShape(Circle())
        .help(tr("More actions", "Другие действия"))
    }

    // MARK: Insights — empty state & bubbles

    private var insightsEmptyState: some View {
        VStack(spacing: MuesliTheme.spacing8) {
            Spacer(minLength: 0)
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(tr("Ask about your meetings", "Спроси про свои встречи"))
                .font(MuesliTheme.title3())
                .foregroundStyle(MuesliTheme.textPrimary)
            Text(tr("The AI reads across all your meetings for the selected period and answers right here.", "ИИ читает все твои встречи за выбранный период и отвечает прямо здесь."))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 260)
    }

    private var insightsTypingBubble: some View {
        HStack {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text(tr("Thinking…", "Печатает…"))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(MuesliTheme.backgroundBase)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
            Spacer(minLength: 40)
        }
    }

    @ViewBuilder
    private func insightsBubble(_ turn: MeetingChatMessage) -> some View {
        if turn.role == .system {
            HStack {
                Spacer(minLength: 0)
                Text(turn.content)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        } else {
            let isUser = turn.role == .user
            HStack {
                if isUser { Spacer(minLength: 40) }
                Group {
                    if isUser || turn.isError {
                        Text(turn.content)
                            .font(MuesliTheme.callout())
                            .foregroundStyle(isUser ? .white : MuesliTheme.recording)
                    } else {
                        ChatMarkdownText(markdown: turn.content)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isUser ? MuesliTheme.accent.opacity(0.75) : MuesliTheme.backgroundBase)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isUser ? Color.clear : (turn.isError ? MuesliTheme.recording.opacity(0.4) : MuesliTheme.surfaceBorder), lineWidth: 1)
                )
                if !isUser { Spacer(minLength: 40) }
            }
        }
    }

    private func insightsScrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if appState.insightsChatAwaiting {
                proxy.scrollTo("insights-typing", anchor: .bottom)
            } else if let last = appState.insightsChatHistory.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: Insights — hint chips (1.2)

    private var insightsHintsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(InsightsHints.all) { hint in
                    Button {
                        sendInsightsHint(hint)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: hint.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(hint.label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(MuesliTheme.backgroundBase))
                        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Insights — composer (1.1)

    private var insightsComposer: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                tr("Ask about your meetings…", "Спроси про свои встречи…"),
                text: $insightsDraft,
                axis: .vertical
            )
            .font(MuesliTheme.callout())
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused($insightsInputFocused)
            .onSubmit(sendInsightsMessage)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        insightsModelPill
                        insightsDatePill
                        insightsFolderPill
                        insightsHintsTogglePill
                    }
                }
                Spacer(minLength: 8)
                insightsSendButton
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { insightsInputFocused = true }
    }

    private func insightsPillLabel(icon: String, text: String, accent: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(accent ? MuesliTheme.accent : MuesliTheme.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 27)
        .background(Capsule().fill(accent ? MuesliTheme.accentSubtle : MuesliTheme.backgroundRaised))
        .overlay(Capsule().strokeBorder(accent ? Color.clear : MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    /// Leftmost pill: connected text models, grouped Local/Cloud. Empty
    /// registry → accent "Model not selected", only menu item routes to
    /// Models — never a dead dropdown or a network error on send.
    private var insightsModelPill: some View {
        let models = controller.configuredModels(role: .textGeneration)
        let localModels = models.filter { $0.provider.isLocal }
        let cloudModels = models.filter { !$0.provider.isLocal }
        let selectedID = controller.insightsModelID()
        let selectedModel = models.first { $0.id == selectedID }

        return Menu {
            if !localModels.isEmpty {
                Section(tr("Local", "Локальные")) {
                    ForEach(localModels) { model in
                        Button {
                            controller.setInsightsModelID(model.id)
                        } label: {
                            if model.id == selectedID {
                                Label(model.displayName, systemImage: "checkmark")
                            } else {
                                Text(model.displayName)
                            }
                        }
                    }
                }
            }
            if !cloudModels.isEmpty {
                Section(tr("Cloud", "Облачные")) {
                    ForEach(cloudModels) { model in
                        Button {
                            controller.setInsightsModelID(model.id)
                        } label: {
                            if model.id == selectedID {
                                Label(model.displayName, systemImage: "checkmark")
                            } else {
                                Text(model.displayName)
                            }
                        }
                    }
                }
            }
            if !models.isEmpty {
                Divider()
            }
            Button(tr("Manage Models…", "Управление моделями…")) {
                appState.selectedTab = .settings
                appState.settingsSection = .models
            }
        } label: {
            insightsPillLabel(
                icon: "cpu",
                text: selectedModel?.displayName ?? tr("Model not selected", "Модель не выбрана"),
                accent: selectedModel == nil
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var insightsDatePill: some View {
        Menu {
            ForEach([InsightsDateRange.allTime, .today, .week, .month], id: \.self) { range in
                Button {
                    selectInsightsDateRange(range)
                } label: {
                    if appState.insightsDateRange == range {
                        Label(range.title, systemImage: "checkmark")
                    } else {
                        Text(range.title)
                    }
                }
            }
            Divider()
            Button(tr("Specific date…", "Конкретная дата…")) {
                showInsightsDatePopover = true
            }
        } label: {
            insightsPillLabel(icon: "calendar", text: appState.insightsDateRange.title)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $showInsightsDatePopover, arrowEdge: .top) {
            VStack(spacing: 12) {
                DatePicker("", selection: $insightsCustomDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                Button(tr("Apply", "Применить")) {
                    selectInsightsDateRange(.specificDay(insightsCustomDate))
                    showInsightsDatePopover = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(MuesliTheme.accent)
                .clipShape(Capsule())
            }
            .padding(16)
        }
    }

    /// Folder filter — same pattern as the meeting header folder button.
    private var insightsFolderPill: some View {
        let currentName = appState.insightsFolderID.flatMap { id in
            appState.folders.first(where: { $0.id == id })?.name
        }
        return Menu {
            Button {
                selectInsightsFolder(nil)
            } label: {
                if appState.insightsFolderID == nil {
                    Label(tr("All folders", "Все папки"), systemImage: "checkmark")
                } else {
                    Text(tr("All folders", "Все папки"))
                }
            }
            if !appState.folders.isEmpty {
                Divider()
                ForEach(appState.folders) { folder in
                    Button {
                        selectInsightsFolder(folder.id)
                    } label: {
                        if appState.insightsFolderID == folder.id {
                            Label(folder.name, systemImage: "checkmark")
                        } else {
                            Text(folder.name)
                        }
                    }
                }
            }
        } label: {
            insightsPillLabel(icon: "folder", text: currentName ?? tr("All folders", "Все папки"))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var insightsHintsTogglePill: some View {
        let enabled = appState.config.insightsHintsEnabled
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                controller.updateConfig { $0.insightsHintsEnabled.toggle() }
            }
        } label: {
            Image(systemName: "lightbulb")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabled ? MuesliTheme.accent : MuesliTheme.textSecondary)
                .frame(width: 27, height: 27)
                .background(Circle().fill(enabled ? MuesliTheme.accentSubtle : MuesliTheme.backgroundRaised))
                .overlay(Circle().strokeBorder(enabled ? Color.clear : MuesliTheme.surfaceBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(tr("Quick prompts", "Быстрые подсказки"))
    }

    private var insightsSendButton: some View {
        let canSend = !insightsDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.insightsChatAwaiting
            && controller.insightsModelID() != nil
        return Button {
            sendInsightsMessage()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(canSend ? Color.white : MuesliTheme.textTertiary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(canSend ? MuesliTheme.accent : MuesliTheme.backgroundRaised))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help(tr("Send", "Отправить"))
    }

    // MARK: Insights — actions

    private func sendInsightsMessage() {
        let text = insightsDraft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !appState.insightsChatAwaiting else { return }
        insightsDraft = ""
        controller.sendInsightsMessage(text)
    }

    private func sendInsightsHint(_ hint: InsightsHint) {
        guard !appState.insightsChatAwaiting else { return }
        controller.sendInsightsMessage(hint.prompt)
    }

    private func selectInsightsDateRange(_ range: InsightsDateRange) {
        guard range != appState.insightsDateRange else { return }
        appState.insightsDateRange = range
        insertInsightsContextDivider()
    }

    private func selectInsightsFolder(_ id: Int64?) {
        guard id != appState.insightsFolderID else { return }
        appState.insightsFolderID = id
        insertInsightsContextDivider()
    }

    /// Marks the point in the transcript where the material a reply is
    /// grounded in changed, so a re-read of the chat shows what was in scope.
    private func insertInsightsContextDivider() {
        guard !appState.insightsChatHistory.isEmpty else { return }
        let folderName = appState.insightsFolderID.flatMap { id in
            appState.folders.first(where: { $0.id == id })?.name
        } ?? tr("All folders", "Все папки")
        let text = tr(
            "Period: \(appState.insightsDateRange.title) · Folder: \(folderName)",
            "Период: \(appState.insightsDateRange.title) · Папка: \(folderName)"
        )
        appState.insightsChatHistory.append(MeetingChatMessage(role: .system, content: text))
    }

    @ViewBuilder
    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Overview", "Обзор"))
                        .font(MuesliTheme.pageTitle())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("Your voice habits at a glance — computed on your Mac.", "Твои голосовые привычки с одного взгляда — считается на твоём Mac."))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                numberCards

                if let a = appState.overviewAnalytics, !a.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 11) {
                        weekdayCard(a)
                        meetingLengthCard(a)
                        topWordsCard(a)
                        fillerCard(a)
                    }
                } else if appState.overviewAnalyticsLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(tr("Crunching your numbers…", "Считаем твою статистику…"))
                            .font(MuesliTheme.callout())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .padding(.top, MuesliTheme.spacing8)
                } else {
                    analyticsEmptyState
                }
            }
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.vertical, MuesliTheme.spacing20)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { controller.refreshOverviewAnalytics() }
    }

    // MARK: Overview — number cards

    private var numberCards: some View {
        let a = appState.overviewAnalytics
        let d = appState.dictationStats
        let m = appState.meetingStats
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 3), spacing: 11) {
            statTile("clock.fill", .init(hex: 0x34AADC), formatMinutes(a?.totalVoiceMinutes ?? 0), tr("voice minutes", "минут голоса"))
            statTile("character.cursor.ibeam", .init(hex: 0x007AFF), formatCount(d.totalWords + m.totalWords), tr("words captured", "слов записано"))
            statTile("keyboard", .init(hex: 0x34C759), String(format: tr("≈%.1f h", "≈%.1f ч"), a?.wordsSavedTypingHours ?? 0), tr("typing saved", "сэкономлено печати"))
            statTile("person.2.fill", .init(hex: 0xAF52DE), "\(m.totalMeetings)", tr("meetings", "встреч"))
            statTile("flame.fill", .init(hex: 0xFF9500), "\(d.currentStreakDays)", tr("day streak", "серия дней"))
            statTile("gauge.with.dots.needle.33percent", .init(hex: 0xFF3B30), String(format: "%.0f", d.averageWPM), tr("avg WPM", "слов/мин"))
        }
    }

    private func statTile(_ icon: String, _ color: Color, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MuesliTheme.spacing16)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    // MARK: Overview — chart cards

    private func analyticsCard<Content: View>(_ title: String, _ subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
            }
            content()
        }
        // maxHeight: .infinity lets a card whose own content is shorter
        // (e.g. filler words with an empty-state hint) stretch to match a
        // taller sibling in the same grid row, instead of leaving its own
        // background/border shorter than the row and reading as "smaller".
        .frame(maxWidth: .infinity, minHeight: 165, maxHeight: .infinity, alignment: .topLeading)
        .padding(MuesliTheme.spacing16)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    private func weekdayCard(_ a: OverviewAnalytics) -> some View {
        analyticsCard(tr("Weekly rhythm", "Ритм недели"), tr("Voice minutes by weekday", "Минуты голоса по дням недели")) {
            Chart(a.weekday) { day in
                BarMark(
                    x: .value("Day", day.shortLabel),
                    y: .value("Minutes", day.minutes)
                )
                .foregroundStyle(Color(hex: 0x34AADC))
                .cornerRadius(4)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 105)
        }
    }

    private func meetingLengthCard(_ a: OverviewAnalytics) -> some View {
        analyticsCard(tr("Meeting length", "Длина встречи"), String(format: tr("avg %.0f min", "в среднем %.0f мин"), a.avgMeetingMinutes)) {
            if a.meetingLengthByWeek.count >= 2 {
                Chart(a.meetingLengthByWeek) { point in
                    LineMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Minutes", point.avgMinutes)
                    )
                    .foregroundStyle(Color(hex: 0x34C759))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Minutes", point.avgMinutes)
                    )
                    .foregroundStyle(Color(hex: 0x34C759))
                }
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { _ in AxisGridLine() } }
                .frame(height: 105)
            } else {
                emptyHint(tr("Not enough meetings yet for a trend.", "Пока мало встреч для тренда."))
            }
        }
    }

    private func topWordsCard(_ a: OverviewAnalytics) -> some View {
        analyticsCard(tr("Top words", "Топ слов"), tr("Most frequent across your speech", "Самые частые в твоей речи")) {
            if a.topWords.isEmpty {
                emptyHint(tr("No words yet.", "Пока нет слов."))
            } else {
                let maxCount = a.topWords.first?.count ?? 1
                // One accent color, shaded from strongest (most frequent) to
                // faintest — a rainbow across unrelated hues read as noisy;
                // shades of the same color still separate each row visually
                // while reinforcing the rank/frequency order.
                // Follows the user's chosen accent (MuesliTheme.accent),
                // not a hardcoded hex — a fixed blue here read as wrong once
                // Anna picked a different app accent (purple).
                let base = MuesliTheme.accent
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(a.topWords.prefix(8).enumerated()), id: \.element.id) { index, w in
                        HStack(spacing: 10) {
                            Text(w.word)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(MuesliTheme.textSecondary)
                                .frame(width: 96, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                Capsule()
                                    .fill(base.opacity(max(0.3, 0.95 - Double(index) * 0.09)))
                                    .frame(width: max(6, geo.size.width * CGFloat(w.count) / CGFloat(maxCount)))
                            }
                            .frame(height: 8)
                            Text("\(w.count)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func fillerCard(_ a: OverviewAnalytics) -> some View {
        analyticsCard(tr("Filler words", "Слова-паразиты"), tr("Catch your verbal habits", "Замечай речевые привычки")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(a.fillers.totalFillers)")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(String(format: tr("(%.1f%% of words)", "(%.1f%% слов)"), a.fillers.percent))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                if a.fillers.top.isEmpty {
                    emptyHint(tr("Clean speech — no fillers detected.", "Чистая речь — паразитов не найдено."))
                } else {
                    FlowWrap(a.fillers.top.map { "\($0.word) · \($0.count)" })
                }
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private var analyticsEmptyState: some View {
        VStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(tr("No analytics yet", "Пока нет аналитики"))
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text(tr("Record a meeting or dictate something — insights will appear here.", "Запиши встречу или что-нибудь продиктуй — тут появится аналитика."))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MuesliTheme.spacing24)
    }

    private func formatMinutes(_ minutes: Double) -> String {
        if minutes >= 60 {
            return String(format: tr("%.1f h", "%.1f ч"), minutes / 60)
        }
        return String(format: tr("%.0f min", "%.0f мин"), minutes)
    }

    private func formatCount(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)"
    }

    @ViewBuilder
    private var functionsContent: some View {
        // `GeometryReader` used as the OUTER container (not nested inside
        // the scrollable content) reports exactly what ITS OWN parent
        // proposes — driven purely by the window/sidebar layout — and
        // never gets inflated by what's inside the ScrollView. This
        // matters here specifically: the board's cards used to measure
        // their available width from a probe placed INSIDE the same
        // content stack as the board itself, and a vertical `ScrollView`
        // doesn't constrain its content's width to the viewport by
        // default, so the board's own ~1100pt design demand echoed back
        // as the "measured" width — a stable, window-size-INDEPENDENT
        // fixed point (1100 minus padding), not the real window width.
        // That's why nothing about the on-screen result ever changed
        // across several rounds of fixing the scale math: the input was
        // never actually connected to the window's true size. Measuring
        // out here, above the ScrollView, breaks that loop structurally.
        GeometryReader { proxy in
            // Explicit width, clamped to the page's usual 1100pt cap —
            // computed ONCE here from the real proposal, then handed down
            // as a plain value. Nothing downstream (the board, its cards)
            // can feed back into this number, unlike the old in-content
            // probe.
            let boardWidth = min(proxy.size.width - MuesliTheme.spacing24 * 2, 1100)
            // The banner's own horizontal padding (see `FeatureBanner`) eats
            // into the space available to the board's explicit-pixel-width
            // cards — compensated once here, not re-measured inside.
            let innerWidth = boardWidth - 40

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Features", "Функции"))
                            .font(MuesliTheme.pageTitle())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        Text(tr("Everything Muesli can do — and how to switch it on.", "Всё, что умеет Muesli, и как это включить."))
                            .font(MuesliTheme.callout())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // One cohesive banner surface — the main board and the
                    // permissions section used to be two independently
                    // bordered pieces (round 8 feedback: "снизу разрешения
                    // надо тоже как то пихнуть в баннер") — now nested
                    // inside a single `FeatureBanner`, matching the
                    // design-canvas mockup's two-level nesting (one outer
                    // panel, lighter cells inside it).
                    FeatureBanner {
                        mainFeaturesBoard(width: innerWidth)

                        FeaturePermissionsBoard(
                            useCoreAudioTap: appState.config.useCoreAudioTap,
                            status: permissionStatus
                        )
                    }
                    .onAppear {
                        permissionStatus.useCoreAudioTap = appState.config.useCoreAudioTap
                        permissionStatus.startPolling()
                    }
                    .onDisappear { permissionStatus.stopPolling() }
                }
                .padding(.horizontal, MuesliTheme.spacing24)
                .padding(.vertical, MuesliTheme.spacing20)
                .frame(width: proxy.size.width, alignment: .leading)
            }
        }
    }

    // MARK: - Features tour (task 5)

    /// Content per card matches the design-canvas mockup approved as
    /// "Вариант 1" ("1 — итог: мозаика, 2 колонки") — every card shows the
    /// app's actual live data (connected models, engine count, the default
    /// template's name, the real permission state) in a compact information
    /// panel, not a generic marketing subtitle with a looping demo clip.
    /// Only the two hero cards (a real on/off permission) get a status
    /// badge; the rest are single-tap navigation cards to their Settings
    /// section, mirroring the mockup's chevron affordance.
    private var dictationHeroCard: some View {
        Button {
            openSettings(.dictation)
        } label: {
            FeatureCellContainer(isHero: true) {
                FeatureCellHeader(icon: "mic.fill", title: tr("Voice dictation", "Диктовка голосом"), titleSize: 15) {
                    PermissionBadge(granted: permissionStatus.dictationGranted) { requestDictationPermissions() }
                }
                HStack {
                    Spacer(minLength: 0)
                    HotkeyGlyph(symbol: "⌥", badgeIcon: "mic.fill")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                Text(tr("Hold Right Option and speak — the text lands right at your cursor.", "Зажми Right Option и говори — текст сам встаёт у курсора."))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    private var meetingsHeroCard: some View {
        Button {
            openSettings(.meetings)
        } label: {
            FeatureCellContainer(isHero: true) {
                FeatureCellHeader(icon: "person.2.fill", title: tr("Meetings, summarized", "Встречи в готовых заметках"), titleSize: 15) {
                    PermissionBadge(granted: permissionStatus.meetingsGranted) { requestMeetingsPermissions() }
                }
                Text(tr("A meeting → a ready recap", "Встреча → готовая сводка"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(tr("Microphone and screen audio. You just talk — the note builds itself, in your template.", "Микрофон и звук с экрана. Ты просто разговариваешь — заметка соберётся сама, по шаблону."))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var connectModelCard: some View {
        Button {
            showConnectModelSheet = true
        } label: {
            FeatureCellContainer {
                FeatureCellHeader(icon: "link", title: tr("Connect a model", "Подключить модель")) {
                    FeatureCellChevron()
                }
                Text("ChatGPT · OpenAI · OpenRouter · Ollama")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(MuesliTheme.textTertiary)

                let models = Array(controller.configuredModels(role: .textGeneration).prefix(3))
                let activeID = controller.defaultConfiguredModelID(role: .textGeneration)
                if models.isEmpty {
                    Text(tr("No model connected yet", "Пока не подключена ни одна модель"))
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(MuesliTheme.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(models) { model in
                            let isActive = model.id == activeID
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(isActive ? MuesliTheme.success : MuesliTheme.textPrimary.opacity(0.25))
                                    .frame(width: 5, height: 5)
                                Text(model.displayName)
                                    .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                                    .foregroundStyle(isActive ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    ZStack {
                        Circle().strokeBorder(MuesliTheme.textPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2]))
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .frame(width: 13, height: 13)
                    Text(tr("Add a model", "Добавить модель"))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .padding(.top, 2)
            }
        }
        .buttonStyle(.plain)
    }

    // Engine count/names are real, documented in this project's own
    // CLAUDE.md ("11 ASR models: Parakeet v3/v2, Whisper Tiny/Small/
    // Medium/Large Turbo, Cohere Transcribe, Nemotron 3.5 Multilingual,
    // SenseVoice Small, Qwen3 ASR, Indic ASR") — not invented for this card.
    private var onDeviceModelsCard: some View {
        Button {
            openSettings(.models, modelsTab: .speech)
        } label: {
            FeatureCellContainer {
                FeatureCellHeader(icon: "square.and.arrow.down.fill", title: tr("On-device", "На устройстве")) {
                    FeatureCellChevron()
                }
                Text(tr("Recognize speech as text — offline. Don't write summaries (that's the model above).", "Распознают речь в текст — офлайн. Не пишут сводку (это модель выше)."))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(MuesliTheme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("11")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("engines", "движков"))
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                HStack(spacing: 6) {
                    EngineTagPill(text: "Parakeet")
                    EngineTagPill(text: "Whisper")
                    EngineTagPill(text: "+9")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var templatesCard: some View {
        Button {
            controller.showMeetingTemplatesManager()
        } label: {
            FeatureCellContainer {
                FeatureCellHeader(icon: "square.text.square.fill", title: tr("Note templates", "Шаблоны заметок")) {
                    FeatureCellChevron()
                }
                let defaultTemplate = controller.defaultMeetingTemplate()
                HStack(spacing: 5) {
                    Text(tr("Template: ", "Шаблон: ") + defaultTemplate.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary.opacity(0.85))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(MuesliTheme.textPrimary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))

                Text(tr("Picks how every new meeting note is structured.", "Определяет, как оформляется каждая новая заметка о встрече."))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var meetingChatCard: some View {
        Button {
            openSettings(.meetings)
        } label: {
            FeatureCellContainer {
                FeatureCellHeader(icon: "bubble.left.and.text.bubble.right.fill", title: tr("Chat with your meeting", "Чат с встречей")) {
                    FeatureCellChevron()
                }
                VStack(alignment: .leading, spacing: 6) {
                    ChatBubble(text: tr("When's the next call?", "Когда следующая созвонка?"), isMe: false)
                    ChatBubble(text: tr("Thursday at 3pm.", "В четверг в 15:00."), isMe: true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var insightsCard: some View {
        Button {
            selectedSection = .insights
        } label: {
            FeatureCellContainer {
                FeatureCellHeader(icon: "magnifyingglass", title: tr("Insights — across all meetings", "Инсайты по всем встречам")) {
                    FeatureCellChevron()
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(MuesliTheme.textTertiary)
                    Text(tr("What did we agree with the client?", "О чём договорились с клиентом?"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(MuesliTheme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))

                HStack(spacing: 6) {
                    InsightHintChip(text: tr("My tasks", "Мои задачи"))
                    InsightHintChip(text: tr("Decisions", "Решения"))
                    InsightHintChip(text: tr("Risks", "Риски"))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // Gutter between cards — matches the mockup's banner/pair `gap: 14px`.
    // Row heights are NOT forced here — each card sizes to its own content
    // via `FeatureCellContainer`'s `minHeight` floor (a floor, not a
    // ceiling); forcing a fixed height per row was tuned for the old
    // gif-demo-era content and left new, much lighter content (a badge, a
    // short list, a few chips) stranded in oversized, visibly stretched
    // cards — exactly the "некрасиво расширено" feedback this fixes.
    private static let boardSpacing: CGFloat = 14

    /// Vertical mosaic, approved on the design canvas ("Вариант 1"): two
    /// full-width hero rows for the two flagship features (dictation,
    /// meetings — the only two with a real on/off permission), then two
    /// medium-card pairs (connect-a-model + on-device models; templates +
    /// meeting-chat), then Insights promoted to its own full-width row
    /// (the one card left without a natural pair, and the next most-used
    /// feature after the two heroes), and finally the four icon+toggle
    /// utility cards as a 2×2 grid instead of one cramped four-across row.
    /// Widths are computed EXPLICITLY from `width` (not left to automatic
    /// HStack negotiation) — not SwiftUI's `Grid`/`.gridCellColumns`
    /// (confirmed buggy for inconsistent per-row spans in an earlier pass
    /// on this same board).
    ///
    /// `width` is passed in from `functionsContent`'s outer
    /// `GeometryReader`, NOT measured locally in here — an earlier version
    /// had its own width probe living inside this same view tree, and its
    /// "measured" value turned out to just be this board's own ~1100pt
    /// design width echoing back (a vertical `ScrollView` doesn't clamp
    /// its content's width to the viewport by default), a fixed point
    /// completely disconnected from the real window size. Every fix to
    /// the probe/consumption logic kept failing identically because the
    /// INPUT itself was circular. Taking `width` as a plain parameter from
    /// outside this view's own subtree removes that loop structurally.
    ///
    /// A true proportional "zoom out" (shrinking fonts/icons too, via
    /// `.scaleEffect`) was attempted per explicit feedback and abandoned —
    /// `.scaleEffect` composed unreliably with the rest of this layout.
    /// Columns resize directly from `width` instead: text/icons stay their
    /// natural size, but nothing can overflow, since every card's width is
    /// computed to literally sum to the available space.
    @ViewBuilder
    private func mainFeaturesBoard(width: CGFloat) -> some View {
        let half = (width - Self.boardSpacing) / 2

        VStack(spacing: Self.boardSpacing) {
            dictationHeroCard
                .frame(width: width)

            meetingsHeroCard
                .frame(width: width)

            HStack(alignment: .top, spacing: Self.boardSpacing) {
                connectModelCard.frame(width: half)
                onDeviceModelsCard.frame(width: half)
            }

            HStack(alignment: .top, spacing: Self.boardSpacing) {
                templatesCard.frame(width: half)
                meetingChatCard.frame(width: half)
            }

            insightsCard
                .frame(width: width)

            HStack(alignment: .top, spacing: Self.boardSpacing) {
                smartCleanupCard.frame(width: half)
                voiceCommandsCard.frame(width: half)
            }

            HStack(alignment: .top, spacing: Self.boardSpacing) {
                screenVideoCard.frame(width: half)
                dictionaryCard.frame(width: half)
            }
        }
    }

    private func requestDictationPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        if !CGRequestListenEventAccess() {
            openSettings(.dictation)
        }
    }

    private func requestMeetingsPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        CGRequestScreenCaptureAccess()
    }

    private func openSettings(_ section: SettingsSection, modelsTab: ModelsTab? = nil) {
        if let modelsTab {
            appState.modelsTab = modelsTab
        }
        appState.settingsSection = section
        appState.selectedTab = .settings
    }

    // Small icon(+toggle) tiles — no preview clips, just icon + toggle
    // where the feature has a real on/off setting (Smart cleanup, Voice
    // commands, Screen video all map straight to a config boolean already
    // used in Settings). Dictionary has no on/off state, so it stays a
    // simple navigate card. Folded into the same mosaic as the flagship
    // cards above (round 6: per a bento-dashboard layout reference, these
    // read as one cohesive board of proportionally-sized tiles rather than
    // two separate sections split by a "MORE" heading).
    private var smartCleanupCard: FeatureCard {
        FeatureCard(
            accent: MuesliTheme.accent,
            icon: "wand.and.stars",
            title: tr("Smart cleanup", "Умная чистка"),
            subtitle: tr("“um, so like” → “So,”", "«эээ ну как бы» → «Итак,»"),
            actions: [
                FeatureAction(label: tr("Set up", "Настроить"), isPrimary: true) {
                    openSettings(.models, modelsTab: .cleanup)
                }
            ],
            compact: true,
            toggle: FeatureToggle(isOn: appState.config.enablePostProcessor) {
                controller.setPostProcessorEnabled(!appState.config.enablePostProcessor)
            }
        )
    }

    private var voiceCommandsCard: FeatureCard {
        FeatureCard(
            accent: MuesliTheme.accent,
            icon: "cursorarrow.rays",
            title: tr("Voice commands", "Голосовые команды"),
            subtitle: tr("Tell your Mac what to do, hands-free.", "Управляй Mac голосом, без рук."),
            actions: [
                FeatureAction(label: tr("Set up", "Настроить"), isPrimary: true) {
                    openSettings(.computerUse)
                }
            ],
            compact: true,
            toggle: FeatureToggle(isOn: appState.config.enableComputerUsePlanner) {
                controller.updateConfig { $0.enableComputerUsePlanner = !$0.enableComputerUsePlanner }
            }
        )
    }

    private var screenVideoCard: FeatureCard {
        FeatureCard(
            accent: MuesliTheme.accent,
            icon: "display",
            title: tr("Screen video with sound", "Видео экрана со звуком"),
            subtitle: tr("Record the screen together with the audio, replay it on the meeting page.", "Записывай экран вместе со звуком, пересматривай на странице встречи."),
            actions: [
                FeatureAction(label: tr("Meeting settings", "Настройки встреч"), isPrimary: true) {
                    openSettings(.meetings)
                }
            ],
            compact: true,
            toggle: FeatureToggle(isOn: appState.config.enableMeetingScreenVideo) {
                controller.updateConfig { $0.enableMeetingScreenVideo = !$0.enableMeetingScreenVideo }
            }
        )
    }

    private var dictionaryCard: FeatureCard {
        let entries = appState.config.customWords.prefix(2)
        let subtitle: String
        if entries.isEmpty {
            subtitle = tr("Custom words for names and terms transcription often gets wrong.", "Свои слова для имён и терминов, которые транскрипция часто путает.")
        } else {
            subtitle = entries
                .map { "«\($0.word)» → \($0.replacement ?? $0.word)" }
                .joined(separator: " · ")
        }
        return FeatureCard(
            accent: MuesliTheme.accent,
            icon: "character.book.closed.fill",
            title: tr("Dictionary", "Словарь"),
            subtitle: subtitle,
            actions: [
                FeatureAction(label: tr("Open", "Открыть"), isPrimary: true) {
                    openSettings(.dictionary)
                }
            ],
            compact: true
        )
    }

    // MARK: - iPhone bridge (moved from the Dictations page)

    private var bridgeState: ICloudBridgeState {
        appState.iCloudBridgeState
    }

    private var iPhoneBridgeCard: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing8) {
                BridgeSyncIcon(
                    systemName: bridgeIcon,
                    isAnimating: bridgeSyncIconIsAnimating,
                    font: .system(size: 15, weight: .semibold)
                )
                    .foregroundStyle(bridgeIconColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bridgeTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(bridgeSubtitle)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: MuesliTheme.spacing8) {
                Button {
                    bridgePrimaryAction()
                } label: {
                    HStack(spacing: 6) {
                        Text(bridgeButtonTitle)
                            .lineLimit(1)
                        BridgeSyncIcon(
                            systemName: bridgeButtonIcon,
                            isAnimating: bridgeButtonIconIsAnimating,
                            font: .system(size: 11, weight: .semibold)
                        )
                    }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(MuesliTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)
                .disabled(bridgeActionDisabled)
                .help(bridgeButtonHelp)

                if shouldShowBridgeHandoffButton {
                    Button {
                        isBridgeQRCodePresented = true
                        TelemetryDeck.signal("bridge_qr_shown", parameters: ["platform": "macos"])
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .frame(width: 26, height: 26)
                            .background(MuesliTheme.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    .buttonStyle(.plain)
                    .help(tr("Show iPhone setup QR", "Показать QR для настройки iPhone"))
                }

                Spacer(minLength: 0)
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .onAppear {
            guard !bridgePromptSeen else { return }
            bridgePromptSeen = true
            TelemetryDeck.signal("bridge_prompt_seen", parameters: ["platform": "macos"])
        }
    }

    private var shouldShowBridgeHandoffButton: Bool {
        guard appState.config.iCloudSyncEnabled else { return false }
        switch bridgeState {
        case .needsICloud, .error:
            return false
        case .active:
            return appState.iCloudBridgeCompanionDeviceName == nil
        case .notConfigured, .checkingICloud, .syncing:
            return false
        }
    }

    private var bridgeSyncIconIsAnimating: Bool {
        isBridgeSyncWorking && bridgeIcon == "arrow.triangle.2.circlepath"
    }

    private var bridgeButtonIconIsAnimating: Bool {
        isBridgeSyncWorking && bridgeButtonIcon == "arrow.triangle.2.circlepath"
    }

    private var isBridgeSyncWorking: Bool {
        bridgeState == .checkingICloud || bridgeState == .syncing
    }

    private var bridgeIcon: String {
        switch bridgeState {
        case .active:
            return "checkmark.icloud"
        case .checkingICloud, .syncing:
            return "arrow.triangle.2.circlepath"
        case .needsICloud, .error:
            return "exclamationmark.icloud"
        case .notConfigured:
            return "iphone.gen3"
        }
    }

    private var bridgeIconColor: Color {
        switch bridgeState {
        case .active:
            return MuesliTheme.success
        case .needsICloud, .error:
            return MuesliTheme.transcribing
        default:
            return MuesliTheme.accent
        }
    }

    private var bridgeTitle: String {
        switch bridgeState {
        case .active:
            guard let deviceName = appState.iCloudBridgeCompanionDeviceName else {
                if let lastSyncedAt = appState.iCloudLastSyncedAt {
                    return tr("iCloud sync active · \(relativeSyncTime(lastSyncedAt))", "Синхронизация iCloud активна · \(relativeSyncTime(lastSyncedAt))")
                }
                return tr("iCloud sync active", "Синхронизация iCloud активна")
            }
            if let lastSyncedAt = appState.iCloudLastSyncedAt {
                return tr("Synced with \(deviceName) · \(relativeSyncTime(lastSyncedAt))", "Синхронизировано с \(deviceName) · \(relativeSyncTime(lastSyncedAt))")
            }
            return tr("Synced with \(deviceName)", "Синхронизировано с \(deviceName)")
        case .checkingICloud, .syncing:
            return tr("Setting up private iCloud sync", "Настройка приватной синхронизации iCloud")
        case .needsICloud:
            return tr("Sign in to iCloud to sync", "Войдите в iCloud для синхронизации")
        case .error:
            return tr("iPhone sync needs attention", "Синхронизация с iPhone требует внимания")
        case .notConfigured:
            return tr("Use Muesli on iPhone", "Используйте Muesli на iPhone")
        }
    }

    private var bridgeSubtitle: String {
        switch bridgeState {
        case .active:
            if let deviceName = appState.iCloudBridgeCompanionDeviceName {
                return tr("Private iCloud text sync is on with \(deviceName). Audio stays local.", "Приватная синхронизация текста через iCloud включена с \(deviceName). Аудио остаётся на устройстве.")
            }
            return tr("Scan the QR code to connect your iPhone. Audio stays local.", "Отсканируйте QR-код, чтобы подключить iPhone. Аудио остаётся на устройстве.")
        case .checkingICloud:
            return tr("Checking this Mac's iCloud account...", "Проверка учётной записи iCloud на этом Mac...")
        case .syncing:
            return tr("Creating the sync channel and pulling your latest text records.", "Создание канала синхронизации и загрузка последних текстовых записей.")
        case .needsICloud, .error:
            return appState.iCloudBridgeMessage ?? tr("Open iCloud settings, then try again.", "Откройте настройки iCloud и повторите попытку.")
        case .notConfigured:
            return tr("Your Muesli history follows you through private iCloud. Audio stays local.", "История Muesli следует за вами через приватный iCloud. Аудио остаётся на устройстве.")
        }
    }

    private var bridgeButtonTitle: String {
        switch bridgeState {
        case .active:
            return tr("Sync", "Синхронизировать")
        case .checkingICloud, .syncing:
            return tr("Syncing", "Синхронизация")
        case .needsICloud, .error:
            return tr("Try again", "Повторить")
        case .notConfigured:
            return tr("Set up private iCloud sync", "Настроить синхронизацию iCloud")
        }
    }

    private var bridgeButtonIcon: String {
        switch bridgeState {
        case .notConfigured:
            return "icloud"
        default:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var bridgeActionDisabled: Bool {
        bridgeState == .checkingICloud || bridgeState == .syncing
    }

    private var bridgeButtonHelp: String {
        switch bridgeState {
        case .active:
            return tr("Sync text with iCloud", "Синхронизировать текст через iCloud")
        case .checkingICloud, .syncing:
            return tr("Sync setup is in progress", "Идёт настройка синхронизации")
        default:
            return tr("Set up private iCloud text sync", "Настроить приватную синхронизацию текста через iCloud")
        }
    }

    private func bridgePrimaryAction() {
        switch bridgeState {
        case .active:
            controller.performICloudSync()
        case .checkingICloud, .syncing:
            break
        default:
            controller.enableIPhoneBridgeSync()
        }
    }

    private func relativeSyncTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Vertical mosaic card primitives (design-canvas "Вариант 1")
//
// The approved mockup's cards aren't icon+subtitle+demo-clip panels — each
// one is a small information display (a permission badge, a connected-model
// list, an engine count, a template chip, a chat preview, a search prompt).
// These primitives are the shared visual language every card in
// `mainFeaturesBoard` is built from, matching the mockup's `.cell`/`.row-top`/
// `.granted`/`.chev` styles one-to-one.

private struct FeatureCellContainer<Content: View>: View {
    var isHero: Bool = false
    @ViewBuilder var content: () -> Content

    /// A floor, not a forced height — content is free to grow past it, but
    /// a content-light card (e.g. Insights alone in its full-width row)
    /// doesn't collapse to near-nothing next to a taller sibling.
    private var minHeight: CGFloat { isHero ? 150 : 110 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(isHero ? MuesliTheme.spacing20 : MuesliTheme.spacing16)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                    .fill(MuesliTheme.cellFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
    }
}

/// The outer "banner" surface the whole Функции board (and, folded in,
/// the permissions section) lives inside — matches the design-canvas
/// mockup's two-level nesting: one soft-gradient bordered panel, with
/// lighter `FeatureCellContainer` cells nested inside it.
private struct FeatureBanner<Content: View>: View {
    @ViewBuilder var content: () -> Content
    private static var cornerRadius: CGFloat { 28 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [MuesliTheme.bannerFillTop, MuesliTheme.bannerFillBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
    }
}

private struct FeatureCellHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var titleSize: CGFloat = 13.5
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(MuesliTheme.textPrimary.opacity(0.07))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary.opacity(0.82))
            }
            .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            trailing()
        }
    }
}

private struct PermissionBadge: View {
    let granted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(granted ? tr("Granted", "Разрешена") : tr("Grant access", "Выдать доступ"))
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(granted ? MuesliTheme.success : MuesliTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(granted ? MuesliTheme.success.opacity(0.12) : MuesliTheme.textPrimary.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(granted ? MuesliTheme.success.opacity(0.3) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FeatureCellChevron: View {
    var body: some View {
        ZStack {
            Circle().fill(MuesliTheme.textPrimary.opacity(0.05))
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .frame(width: 20, height: 20)
    }
}

/// The hotkey glyph on the Dictation hero card — a big rounded tile with the
/// literal key symbol, badged with a small mic icon. Stands in for the
/// mockup's "⌥" key-hero illustration; no demo video.
private struct HotkeyGlyph: View {
    let symbol: String
    let badgeIcon: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MuesliTheme.textPrimary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(MuesliTheme.accent.opacity(0.45), lineWidth: 1.5)
                        .padding(-6)
                )
                .frame(width: 68, height: 68)
            Text(symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(MuesliTheme.textPrimary.opacity(0.92))
                .frame(width: 68, height: 68)

            ZStack {
                Circle().fill(MuesliTheme.accent)
                Image(systemName: badgeIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
            }
            .frame(width: 22, height: 22)
            .offset(x: 6, y: 6)
        }
        .padding(.bottom, 6)
    }
}

private struct EngineTagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(MuesliTheme.textPrimary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }
}

private struct InsightHintChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(MuesliTheme.textPrimary.opacity(0.05)))
            .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }
}

private struct ChatBubble: View {
    let text: String
    let isMe: Bool

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 24) }
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(MuesliTheme.textPrimary.opacity(0.9))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isMe ? MuesliTheme.accent.opacity(0.32) : MuesliTheme.textPrimary.opacity(0.07))
                )
            if !isMe { Spacer(minLength: 24) }
        }
    }
}

private struct BridgeSyncIcon: View {
    let systemName: String
    let isAnimating: Bool
    let font: Font
    @State private var rotationDegrees = 0.0

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .symbolRenderingMode(.hierarchical)
            .rotationEffect(.degrees(rotationDegrees))
            .onAppear {
                updateRotation(animated: false)
            }
            .onChange(of: isAnimating) { _, _ in
                updateRotation(animated: true)
            }
    }

    private func updateRotation(animated: Bool) {
        guard isAnimating else {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    rotationDegrees = 0
                }
            } else {
                rotationDegrees = 0
            }
            return
        }

        rotationDegrees = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rotationDegrees = 360
        }
    }
}

private struct IPhoneBridgeQRCodeSheet: View {
    let deepLinkURL: URL
    let installURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var didCopySetupLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    Text(tr("Open Muesli on iPhone", "Откройте Muesli на iPhone"))
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("Scan this after installing the iPhone app. The QR only opens setup; private iCloud does the actual sync.", "Отсканируйте после установки приложения на iPhone. QR-код только открывает настройку; синхронизацию выполняет приватный iCloud."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: MuesliTheme.spacing16) {
                QRCodeImage(payload: deepLinkURL.absoluteString)
                    .frame(width: 148, height: 148)
                    .padding(MuesliTheme.spacing8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    Label(tr("Same iCloud account", "Одна учётная запись iCloud"), systemImage: "icloud")
                    Label(tr("Text sync only", "Синхронизация только текста"), systemImage: "text.badge.checkmark")
                    Label(tr("Audio stays local", "Аудио остаётся на устройстве"), systemImage: "lock")
                }
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
            }

            HStack(spacing: MuesliTheme.spacing8) {
                Button(tr("Open iPhone app page", "Открыть страницу приложения для iPhone")) {
                    NSWorkspace.shared.open(installURL)
                }
                .buttonStyle(.bordered)

                Button(didCopySetupLink ? tr("Copied!", "Скопировано!") : tr("Copy setup link", "Копировать ссылку настройки")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(deepLinkURL.absoluteString, forType: .string)
                    didCopySetupLink = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1500))
                        didCopySetupLink = false
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(MuesliTheme.spacing20)
        .frame(width: 430)
        .background(MuesliTheme.backgroundBase)
    }
}

private struct QRCodeImage: View {
    let payload: String
    @State private var cachedImage: NSImage?

    var body: some View {
        Group {
            if let image = cachedImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        }
        .accessibilityLabel(tr("iPhone sync setup QR code", "QR-код настройки синхронизации iPhone"))
        .onAppear {
            if cachedImage == nil {
                cachedImage = makeQRCodeImage(payload: payload)
            }
        }
    }

    private func makeQRCodeImage(payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else {
            return nil
        }

        let representation = NSCIImageRep(ciImage: outputImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
