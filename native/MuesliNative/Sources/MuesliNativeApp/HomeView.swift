import AppKit
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
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
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
                .foregroundStyle(MuesliTheme.accent)
                .cornerRadius(4)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 130)
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
                    .foregroundStyle(MuesliTheme.accent)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Minutes", point.avgMinutes)
                    )
                    .foregroundStyle(MuesliTheme.accent)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { _ in AxisGridLine() } }
                .frame(height: 130)
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
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(a.topWords.prefix(8)) { w in
                        HStack(spacing: 8) {
                            Text(w.word)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MuesliTheme.textSecondary)
                                .frame(width: 92, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                Capsule()
                                    .fill(MuesliTheme.accent.opacity(0.7))
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
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Features", "Функции"))
                        .font(MuesliTheme.pageTitle())
                        .foregroundStyle(MuesliTheme.textPrimary)

                    Text(tr("Everything Muesli can do — and how to switch it on.", "Всё, что умеет Muesli, и как это включить."))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Task 5: onboarding-style tour, in new-user order — replaces
                // the flagship grid. 3 per row per feedback (one full-width
                // banner per row needed too much scrolling). Same 11pt rhythm
                // (task 4) as the compact grid below.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 3), spacing: 11) {
                    ForEach(featureTourBanners) { $0 }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 3), spacing: 11) {
                    ForEach(compactFeatures) { $0 }
                }
            }
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.vertical, MuesliTheme.spacing20)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Features tour (task 5)

    /// New-user order: dictation → meetings → templates → meeting chat →
    /// Insights chat → models, per spec. Images are optional (see
    /// FeatureTourBanner) — ships without real screenshots for now; drop
    /// PNGs into assets/features-tour/ and the banners pick them up.
    private var featureTourBanners: [IdentifiedView] {
        [
            IdentifiedView(FeatureTourBanner(
                assetName: "dictation",
                icon: "mic.fill",
                accent: Color(hex: 0xFF3B30),
                title: tr("Voice dictation", "Диктовка голосом"),
                description: tr("Hold your hotkey, speak, release — text appears under your cursor.", "Зажми клавишу, говори, отпусти — текст появится под курсором."),
                action: FeatureAction(label: tr("Set up dictation", "Настроить диктовку"), systemImage: "keyboard") {
                    openSettings(.dictation)
                }
            )),
            IdentifiedView(FeatureTourBanner(
                assetName: "meetings",
                icon: "person.2.fill",
                accent: Color(hex: 0x34C759),
                title: tr("Meetings, summarized", "Встречи в готовых заметках"),
                description: tr("Muesli listens, then hands you a clean recap in your own template.", "Muesli слушает встречу, а после выдаёт аккуратную сводку по твоему шаблону."),
                action: FeatureAction(label: tr("Meeting settings", "Настройки встреч"), systemImage: "gearshape.fill") {
                    openSettings(.meetings)
                }
            )),
            IdentifiedView(FeatureTourBanner(
                assetName: "templates",
                icon: "square.text.square.fill",
                accent: Color(hex: 0xAF52DE),
                title: tr("Note templates", "Шаблоны заметок"),
                description: tr("Choose how notes are structured, or write your own prompt.", "Выбери, как оформлять заметки, или напиши свой шаблон и промпт."),
                action: FeatureAction(label: tr("Manage templates", "Управление шаблонами"), systemImage: "square.text.square.fill") {
                    controller.showMeetingTemplatesManager()
                }
            )),
            IdentifiedView(FeatureTourBanner(
                assetName: "meeting-chat",
                icon: "bubble.left.and.text.bubble.right.fill",
                accent: Color(hex: 0x5856D6),
                title: tr("Chat with your meeting", "Чат с встречей"),
                description: tr("Ask any meeting a question, get an answer grounded in it.", "Задай вопрос по встрече — получи ответ строго по этому разговору."),
                action: FeatureAction(label: tr("Connect a model", "Подключить модель"), systemImage: "sparkles") {
                    openSettings(.meetings)
                }
            )),
            IdentifiedView(FeatureTourBanner(
                assetName: "insights",
                icon: "sparkles",
                accent: Color(hex: 0x5856D6),
                title: tr("Insights — ask across all meetings", "Инсайты — вопросы по всем встречам"),
                description: tr("One chat that reads every meeting in the period you pick.", "Один чат, который читает сразу все встречи за выбранный период."),
                action: FeatureAction(label: tr("Open Insights", "Открыть Инсайты"), systemImage: "sparkles") {
                    selectedSection = .insights
                }
            )),
            IdentifiedView(FeatureTourBanner(
                assetName: "models",
                icon: "square.and.arrow.down.fill",
                accent: Color(hex: 0x007AFF),
                title: tr("On-device models", "Модели на устройстве"),
                description: tr("11 speech models, all offline — nothing leaves your Mac.", "11 моделей распознавания, всё офлайн — ничего не уходит в облако."),
                action: FeatureAction(label: tr("Manage models", "Управление моделями"), systemImage: "square.and.arrow.down.fill") {
                    openSettings(.models)
                }
            )),
        ]
    }

    private func openSettings(_ section: SettingsSection) {
        appState.settingsSection = section
        appState.selectedTab = .settings
    }

    private var compactFeatures: [IdentifiedView] {
        let cards: [IdentifiedView] = [
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0xAF52DE),
                icon: "square.text.square.fill",
                title: tr("Templates & language", "Шаблоны и язык"),
                subtitle: tr("Your own note formats, in your language.", "Свои форматы заметок — хоть русский, хоть английский."),
                actions: [
                    FeatureAction(label: tr("Open", "Открыть"), isPrimary: true) {
                        controller.showMeetingTemplatesManager()
                    }
                ],
                compact: true
            )),
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0x007AFF),
                icon: "square.and.arrow.down.fill",
                title: tr("On-device models", "Модели на устройстве"),
                subtitle: tr("11 speech models, all offline — nothing leaves your Mac.", "11 моделей распознавания, всё офлайн — ничего не уходит в облако."),
                actions: [
                    FeatureAction(label: tr("Manage", "Управление"), isPrimary: true) {
                        openSettings(.models)
                    }
                ],
                compact: true
            )),
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0x00C7BE),
                icon: "wand.and.stars",
                title: tr("Smart cleanup", "Умная чистка"),
                subtitle: tr("Drops the “ums”, fixes casing, formats lists.", "Убирает «эээ», ставит регистр, оформляет списки."),
                actions: [
                    FeatureAction(label: tr("Set up", "Настроить"), isPrimary: true) {
                        openSettings(.models)
                    }
                ],
                compact: true
            )),
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0xFF2D55),
                icon: "cursorarrow.rays",
                title: tr("Voice commands", "Голосовые команды"),
                subtitle: tr("Tell your Mac what to do, hands-free.", "Управляй Mac голосом, без рук."),
                actions: [
                    FeatureAction(label: tr("Set up", "Настроить"), isPrimary: true) {
                        openSettings(.computerUse)
                    }
                ],
                compact: true
            )),
            // Task 5 point 7: minor items, compact — moved out of the
            // flagship tour above.
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0xFF9500),
                icon: "display",
                title: tr("Screen video with sound", "Видео экрана со звуком"),
                subtitle: tr("Record the screen together with the audio, replay it on the meeting page.", "Записывай экран вместе со звуком, пересматривай на странице встречи."),
                actions: [
                    FeatureAction(label: tr("Enable", "Включить"), isPrimary: true) {
                        openSettings(.meetings)
                    }
                ],
                compact: true
            )),
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0x30B0C7),
                icon: "character.book.closed.fill",
                title: tr("Dictionary", "Словарь"),
                subtitle: tr("Custom words for names and terms transcription often gets wrong.", "Свои слова для имён и терминов, которые транскрипция часто путает."),
                actions: [
                    FeatureAction(label: tr("Open", "Открыть"), isPrimary: true) {
                        openSettings(.dictionary)
                    }
                ],
                compact: true
            )),
        ]
        // TODO(sync): re-enable when the iPhone app ships — see SettingsView.sectionListPane,
        // where the Sync settings section is hidden the same way.
        return cards
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
