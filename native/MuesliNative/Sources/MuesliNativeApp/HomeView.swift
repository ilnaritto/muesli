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
    @State private var insightsPeriod: InsightsPeriod = .week
    @State private var bridgePromptSeen = false
    @State private var isBridgeQRCodePresented = false

    var body: some View {
        HStack(spacing: 5) {
            PrimaryColumn(appState: appState, title: tr("Home", "Главная")) {
                sectionList
            }

            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Insights (AI)

    @ViewBuilder
    private var insightsContent: some View {
        // Cached result only counts if it was generated for the current folder.
        let cached = appState.meetingInsights[insightsPeriod]
        let result = (cached?.folderID == appState.insightsFolderID) ? cached : nil
        let isGenerating = appState.insightsGenerating.contains(insightsPeriod)
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Insights", "Инсайты"))
                        .font(MuesliTheme.pageTitle())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("Let AI read across your meetings and surface what matters.", "Пусть ИИ пройдётся по твоим встречам и выделит главное."))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    periodTabsBar
                    folderDropdown
                    Spacer(minLength: 0)
                    Button {
                        controller.generateInsights(period: insightsPeriod, folderID: appState.insightsFolderID)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text(result == nil ? tr("Generate", "Собрать") : tr("Refresh", "Обновить"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: insightsControlHeight)
                        .background(Capsule().fill(MuesliTheme.accent))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)
                }

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(tr("AI is reading your meetings…", "ИИ анализирует твои встречи…"))
                            .font(MuesliTheme.callout())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .padding(.top, MuesliTheme.spacing8)
                } else if let result {
                    insightsResultView(result)
                } else {
                    insightsIntro
                }
            }
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.vertical, MuesliTheme.spacing20)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shared height so the period tabs, folder dropdown, and action button
    /// line up as one clean control row.
    private var insightsControlHeight: CGFloat { 36 }

    /// Period selector styled like the meeting-page template tabs: an underline
    /// capsule with Day / Week / Month.
    private var periodTabsBar: some View {
        HStack(spacing: MuesliTheme.spacing16) {
            ForEach(InsightsPeriod.allCases) { period in
                periodTab(period)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: insightsControlHeight)
        .background(Capsule().fill(MuesliTheme.backgroundBase))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    private func periodTab(_ period: InsightsPeriod) -> some View {
        let isSelected = insightsPeriod == period
        return Button {
            insightsPeriod = period
        } label: {
            Text(period.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 2)
                        .fill(isSelected ? MuesliTheme.accent : Color.clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Folder filter dropdown, styled like the meeting header folder button.
    private var folderDropdown: some View {
        let currentName = appState.insightsFolderID.flatMap { id in
            appState.folders.first(where: { $0.id == id })?.name
        }
        return Menu {
            Button {
                appState.insightsFolderID = nil
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
                        appState.insightsFolderID = folder.id
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
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                Text(currentName ?? tr("All folders", "Все папки"))
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 140)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(MuesliTheme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 16)
        .frame(height: insightsControlHeight)
        .background(Capsule().fill(MuesliTheme.backgroundBase))
        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
        .contentShape(Capsule())
    }

    @ViewBuilder
    private func insightsResultView(_ result: InsightsResult) -> some View {
        if let error = result.errorMessage {
            insightsMessage(icon: "exclamationmark.triangle.fill", color: MuesliTheme.recording, text: error)
        } else if result.isEmptyPeriod {
            insightsMessage(icon: "calendar", color: MuesliTheme.textTertiary, text: tr("No meetings in this period yet.", "За этот период встреч пока нет."))
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 11) {
                ForEach(result.blocks) { block in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: block.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(RoundedRectangle(cornerRadius: 8).fill(block.color))
                            Text(block.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MuesliTheme.textPrimary)
                        }
                        ChatMarkdownText(markdown: block.markdown)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(MuesliTheme.spacing16)
                    .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
                    .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
                }
            }
        }
    }

    private var insightsIntro: some View {
        VStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(hex: 0x5856D6))
            Text(tr("Your meeting briefing", "Сводка по встречам"))
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text(tr("Pick a period and hit Generate — AI gathers your digest, action items, decisions, and open questions in one pass.", "Выбери период и нажми «Собрать» — ИИ соберёт дайджест, задачи, решения и незакрытые вопросы за один проход."))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MuesliTheme.spacing24)
    }

    private func insightsMessage(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(MuesliTheme.spacing16)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
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

                // Flagship features — 2 per row, larger.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 11) {
                    ForEach(flagshipFeatures) { $0 }
                }

                // Secondary features — 3 per row, compact.
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

    private func openSettings(_ section: SettingsSection) {
        appState.settingsSection = section
        appState.selectedTab = .settings
    }

    private var flagshipFeatures: [IdentifiedView] {
        [
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0xFF3B30),
                icon: "mic.fill",
                title: tr("Voice dictation", "Диктовка голосом"),
                subtitle: tr("Forget the keyboard. Hold your hotkey, speak the way you think — polished text appears under your cursor in any app, instantly.", "Забудь про клавиатуру. Зажми клавишу, говори как думаешь — готовый текст мгновенно появляется под курсором в любом приложении."),
                actions: [
                    FeatureAction(label: tr("Set hotkey", "Настроить клавишу"), systemImage: "keyboard", isPrimary: true) {
                        openSettings(.shortcuts)
                    }
                ]
            )),
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0x34C759),
                icon: "person.2.fill",
                title: tr("Meetings, summarized", "Встречи в готовых заметках"),
                subtitle: tr("Muesli listens to you and everyone else, then hands you a clean recap — decisions, action items, agreements — in your own template.", "Muesli слушает и тебя, и собеседников, а после встречи выдаёт аккуратную сводку — решения, задачи, договорённости — по твоему шаблону."),
                actions: [
                    FeatureAction(label: tr("Templates", "Шаблоны"), systemImage: "square.text.square.fill", isPrimary: true) {
                        controller.showMeetingTemplatesManager()
                    },
                    FeatureAction(label: tr("Recording", "Запись"), systemImage: "gearshape.fill") {
                        openSettings(.meetings)
                    }
                ]
            )),
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0x5856D6),
                icon: "bubble.left.and.text.bubble.right.fill",
                title: tr("Chat with your meeting", "Чат с встречей"),
                subtitle: tr("Stop re-reading transcripts. Just ask — “what did we decide on the budget?” — and get an answer grounded in that exact meeting.", "Не перечитывай транскрипт. Просто спроси — «что решили по бюджету?» — и получи ответ строго по этой встрече."),
                actions: [
                    FeatureAction(label: tr("Connect a model", "Подключить модель"), systemImage: "sparkles", isPrimary: true) {
                        openSettings(.meetings)
                    }
                ]
            )),
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0xFF9500),
                icon: "display",
                title: tr("Screen video with sound", "Видео экрана со звуком"),
                subtitle: tr("Record the screen together with the audio — demos, calls, walkthroughs — and replay it right on the meeting page.", "Записывай экран вместе со звуком — демо, созвоны, разборы — и пересматривай прямо на странице встречи."),
                actions: [
                    FeatureAction(label: tr("Enable in settings", "Включить в настройках"), systemImage: "gearshape.fill", isPrimary: true) {
                        openSettings(.meetings)
                    }
                ]
            )),
        ]
    }

    private var compactFeatures: [IdentifiedView] {
        [
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
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0x34AADC),
                icon: "iphone",
                title: tr("iPhone bridge", "iPhone-мост"),
                subtitle: tr("Dictate on iPhone — it lands on your Mac.", "Диктуй на iPhone — записи прилетают на Mac."),
                actions: [
                    FeatureAction(label: bridgeButtonTitle, isPrimary: true) {
                        bridgePrimaryAction()
                    }
                ],
                compact: true
            )),
            IdentifiedView(FeatureCard(
                accent: Color(hex: 0x8E8E93),
                icon: "lock.fill",
                title: tr("Private by design", "Приватность"),
                subtitle: tr("Speech-to-text runs on your Mac — data stays with you.", "Речь в текст — на твоём Mac, данные остаются у тебя."),
                actions: [],
                compact: true
            )),
        ]
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
