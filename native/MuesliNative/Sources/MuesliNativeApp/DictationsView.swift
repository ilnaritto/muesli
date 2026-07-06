import AppKit
import SwiftUI
import MuesliCore

enum DictationFilter: Hashable {
    case all, last2Days, lastWeek, last2Weeks, lastMonth, last3Months

    var label: String {
        switch self {
        case .all: return tr("All time", "Всё время")
        case .last2Days: return tr("Last 2 days", "Последние 2 дня")
        case .lastWeek: return tr("Last week", "Последняя неделя")
        case .last2Weeks: return tr("Last 2 weeks", "Последние 2 недели")
        case .lastMonth: return tr("Last month", "Последний месяц")
        case .last3Months: return tr("Last 3 months", "Последние 3 месяца")
        }
    }
}

struct DictationsView: View {
    let appState: AppState
    let controller: MuesliController
    @State private var selectedDictationID: Int64?
    @State private var searchQuery = ""
    @State private var showDeleteConfirmation = false
    @FocusState private var isSearchFocused: Bool

    private var visibleDictations: [DictationRecord] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appState.dictationRows }
        return appState.dictationRows.filter { $0.rawText.localizedCaseInsensitiveContains(query) }
    }

    private var selectedDictation: DictationRecord? {
        guard let id = selectedDictationID else { return nil }
        return appState.dictationRows.first(where: { $0.id == id })
    }

    private var groupedDictations: [(header: String, records: [DictationRecord])] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let dateHeaderFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "EEE, d MMM"
            return f
        }()

        var groups: [(key: Date, header: String, records: [DictationRecord])] = []
        var currentDayStart: Date?
        var currentRecords: [DictationRecord] = []
        var currentHeader = ""

        for record in visibleDictations {
            let date = parseDate(record.timestamp) ?? now
            let dayStart = calendar.startOfDay(for: date)

            if dayStart != currentDayStart {
                if !currentRecords.isEmpty, let key = currentDayStart {
                    groups.append((key: key, header: currentHeader, records: currentRecords))
                }
                currentDayStart = dayStart
                currentRecords = []

                if dayStart == today {
                    currentHeader = tr("TODAY", "СЕГОДНЯ")
                } else if dayStart == yesterday {
                    currentHeader = tr("YESTERDAY", "ВЧЕРА")
                } else {
                    currentHeader = dateHeaderFormatter.string(from: date).uppercased()
                }
            }
            currentRecords.append(record)
        }
        if !currentRecords.isEmpty, let key = currentDayStart {
            groups.append((key: key, header: currentHeader, records: currentRecords))
        }

        return groups.map { (header: $0.header, records: $0.records) }
    }

    var body: some View {
        HStack(spacing: 5) {
            PrimaryColumn(appState: appState, title: tr("Dictations", "Диктовки")) {
                dictationsColumn
            } trailing: {
                addMenu
            }

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: appState.focusSearchField) { _, shouldFocus in
            if shouldFocus, appState.selectedTab == .dictations {
                isSearchFocused = true
                appState.focusSearchField = false
            }
        }
    }

    // MARK: - Left column

    @ViewBuilder
    private var dictationsColumn: some View {
        VStack(spacing: 0) {
            // Pinned header: the search field stays put, the list scrolls below.
            searchBar
                .padding(.horizontal, 10)
                .padding(.top, MuesliTheme.spacing12)
                .padding(.bottom, MuesliTheme.spacing8)

            Rectangle()
                .fill(MuesliTheme.surfaceBorder.opacity(0.7))
                .frame(height: 1)

            scrollingList
        }
    }

    @ViewBuilder
    private var scrollingList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                if appState.config.resolvedOnboardingUseCase.includesVoiceNotes {
                    voiceNoteButton
                }

                if visibleDictations.isEmpty {
                    columnEmptyState
                } else {
                    ForEach(Array(groupedDictations.enumerated()), id: \.element.header) { _, group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.header)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .padding(.leading, MuesliTheme.spacing4)
                                .padding(.top, MuesliTheme.spacing8)

                            VStack(spacing: 0) {
                                let lastID = group.records.last?.id
                                ForEach(group.records) { record in
                                    dictationCompactRow(record)
                                    if record.id != lastID {
                                        Rectangle()
                                            .fill(MuesliTheme.surfaceBorder.opacity(0.7))
                                            .frame(height: 1)
                                            .padding(.leading, MuesliTheme.spacing12)
                                    }
                                }
                            }
                        }
                    }

                    // Infinite scroll trigger
                    if appState.hasMoreDictations {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                controller.loadMoreDictations()
                            }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, MuesliTheme.spacing12)
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(MuesliTheme.textTertiary)
            TextField(tr("Search...", "Поиск..."), text: $searchQuery)
                .font(MuesliTheme.callout())
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .overlay(
            Capsule()
                .strokeBorder(MuesliTheme.surfaceBorder.opacity(0.7), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func dictationCompactRow(_ record: DictationRecord) -> some View {
        let isSelected = selectedDictationID == record.id
        Button {
            selectedDictationID = record.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: MuesliTheme.spacing8) {
                    Text(dictationTitle(record))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)
                    if record.source == "cua" {
                        Text("CUA")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(MuesliTheme.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(MuesliTheme.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if let badge = SyncOriginDisplay.badgeLabel(forDictationSource: record.source) {
                        SyncOriginBadge(label: badge)
                    }
                    Spacer(minLength: 4)
                    Text(formatTimeOnly(record.timestamp))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                Text(record.rawText.isEmpty ? tr("(empty)", "(пусто)") : record.rawText)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(MuesliTheme.spacing12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // Inset vertically so the selection fill never touches the
                // hairline separators between rows.
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isSelected ? MuesliTheme.selectionFill : Color.clear)
                    .padding(.vertical, 3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                controller.copyToClipboard(record.rawText)
            } label: {
                Label(tr("Copy", "Копировать"), systemImage: "doc.on.doc")
            }
            if record.computerUseTrace != nil {
                Button {
                    controller.copyToClipboard(ComputerUseTraceFormatter.debugText(for: record))
                } label: {
                    Label(tr("Copy CUA Trace", "Копировать трассировку CUA"), systemImage: "list.bullet.clipboard")
                }
            }
            Divider()
            Button(role: .destructive) {
                if selectedDictationID == record.id {
                    selectedDictationID = nil
                }
                controller.deleteDictation(id: record.id)
            } label: {
                Label(tr("Delete", "Удалить"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var columnEmptyState: some View {
        VStack(alignment: .center, spacing: MuesliTheme.spacing8) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 24, weight: .thin))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(tr("No dictations yet", "Диктовок пока нет"))
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text(emptyStateInstruction)
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity)
        .padding(.top, MuesliTheme.spacing8)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let record = selectedDictation {
            VStack(alignment: .leading, spacing: 9) {
                // Header row: date pill stretching, copy/delete chips at right —
                // same layout language as the meeting page header.
                HStack(spacing: 11) {
                    // Title pill mirroring the meeting header: round icon,
                    // date as the title, small meta line underneath.
                    HStack(spacing: MuesliTheme.spacing8) {
                        ZStack {
                            Circle()
                                .fill(MuesliTheme.accentSubtle)
                            Image(systemName: "text.bubble")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MuesliTheme.accent)
                        }
                        .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(dictationTitle(record))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MuesliTheme.textPrimary)
                                .lineLimit(1)
                            Text(dictationMetaLine(record))
                                .font(.system(size: 10))
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(MuesliTheme.backgroundBase))
                    .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))

                    Button {
                        controller.copyToClipboard(record.rawText)
                    } label: {
                        detailChipIcon("doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help(tr("Copy text", "Копировать текст"))

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        detailChipIcon("trash", tint: MuesliTheme.recording)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Delete dictation", "Удалить диктовку"))
                }

                // Where the text was pasted, as its own block.
                if !record.appContext.isEmpty {
                    metaChip(icon: "macwindow", text: tr("Pasted into: \(record.appContext)", "Вставлено в: \(record.appContext)"))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                        Text(record.rawText)
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if record.computerUseTrace != nil {
                            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                                Text(tr("Computer Use trace", "Трассировка Computer Use"))
                                    .font(MuesliTheme.headline())
                                    .foregroundStyle(MuesliTheme.textSecondary)
                                Text(ComputerUseTraceFormatter.debugText(for: record))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(MuesliTheme.textSecondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(MuesliTheme.spacing12)
                                    .background(MuesliTheme.backgroundRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                            }
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, MuesliTheme.spacing12)
                    .padding(.bottom, MuesliTheme.spacing24)
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.top, 15)
            .alert(tr("Delete Dictation", "Удалить диктовку"), isPresented: $showDeleteConfirmation) {
                Button(tr("Delete", "Удалить"), role: .destructive) {
                    selectedDictationID = nil
                    controller.deleteDictation(id: record.id)
                }
                Button(tr("Cancel", "Отмена"), role: .cancel) {}
            } message: {
                Text(tr("This dictation will be permanently removed.", "Эта диктовка будет удалена навсегда."))
            }
        } else {
            VStack(spacing: MuesliTheme.spacing12) {
                Image(systemName: "mic")
                    .font(.system(size: 42, weight: .thin))
                    .foregroundStyle(MuesliTheme.textTertiary)
                Text(tr("Select a dictation", "Выберите диктовку"))
                    .font(MuesliTheme.title3())
                    .foregroundStyle(MuesliTheme.textSecondary)
                Text(tr("Choose a record from the list to see the full text.", "Выберите запись из списка, чтобы увидеть полный текст."))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Capsule chip in the meeting-page plashka style.
    @ViewBuilder
    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .lineLimit(1)
        }
        .foregroundStyle(MuesliTheme.textSecondary)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Capsule().fill(MuesliTheme.backgroundBase))
        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    /// Circular 40pt icon chip, same as the meeting header chips.
    private func detailChipIcon(_ systemName: String, tint: Color? = nil) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint ?? MuesliTheme.textSecondary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(MuesliTheme.backgroundBase))
            .overlay(Circle().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
            .contentShape(Circle())
    }

    /// Pill title: the first few words of the dictation stand in for a name.
    private func dictationTitle(_ record: DictationRecord) -> String {
        let words = record.rawText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return tr("(empty)", "(пусто)") }
        var title = words.prefix(4).joined(separator: " ")
        if title.count > 40 {
            title = String(title.prefix(40))
        }
        if words.count > 4 || title.count < record.rawText.trimmingCharacters(in: .whitespacesAndNewlines).count {
            title += "…"
        }
        return title
    }

    /// Small meta line under the pill title: recorded at • duration • words • WPM.
    private func dictationMetaLine(_ record: DictationRecord) -> String {
        var parts: [String] = [
            formatFullDate(record.timestamp),
            formatDuration(record.durationSeconds),
            tr("words: \(record.wordCount)", "слов: \(record.wordCount)"),
        ]
        if record.durationSeconds > 1 {
            let wpm = Int((Double(record.wordCount) / (record.durationSeconds / 60)).rounded())
            parts.append(tr("\(wpm) WPM", "\(wpm) слов/мин"))
        }
        return parts.joined(separator: "  \u{2022}  ")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 60 {
            let m = rounded / 60
            let s = rounded % 60
            return s == 0 ? tr("\(m)m", "\(m) мин") : tr("\(m)m \(s)s", "\(m) мин \(s) с")
        }
        return tr("\(rounded)s", "\(rounded) с")
    }

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    private func formatFullDate(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return raw }
        return Self.fullDateFormatter.string(from: date)
    }

    private var emptyStateInstruction: String {
        appState.config.resolvedOnboardingUseCase.includesVoiceNotes
            ? tr("Click Record Voice Note to capture your first note", "Нажмите «Записать голосовую заметку», чтобы создать первую заметку")
            : tr("Hold \(appState.config.dictationHotkey.label) to start dictating", "Удерживайте \(appState.config.dictationHotkey.label), чтобы начать диктовку")
    }

    private var voiceNoteButton: some View {
        let isRecording = appState.isVoiceNoteRecording
        return Button {
            controller.toggleVoiceNoteRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(isRecording ? tr("Stop Voice Note", "Остановить голосовую заметку") : tr("Record Voice Note", "Записать голосовую заметку"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isRecording ? MuesliTheme.recording : MuesliTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .disabled(appState.dictationState == .transcribing)
        .opacity(appState.dictationState == .transcribing ? 0.55 : 1)
    }

    @ViewBuilder
    private var addMenu: some View {
        Menu {
            Button {
                controller.toggleVoiceNoteRecording()
            } label: {
                Label(tr("New Dictation", "Новая диктовка"), systemImage: "text.bubble")
            }
            .disabled(appState.dictationState != .idle)
            Divider()
            Button {
                controller.importDictationAudioFile()
            } label: {
                Label(tr("Import Audio", "Импорт аудио"), systemImage: "square.and.arrow.down")
            }
            .disabled(appState.dictationState != .idle)
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(tr("Import audio as dictation", "Импорт аудио как диктовки"))
    }

    // MARK: - Date parsing

    private static let parsers: [DateFormatterProtocol] = {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        let local1: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            return f
        }()
        let local2: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f
        }()
        return [iso1, iso2, local1, local2]
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "hh:mm a"
        return f
    }()

    private func parseDate(_ raw: String) -> Date? {
        for parser in Self.parsers {
            if let date = parser.date(from: raw) {
                return date
            }
        }
        return nil
    }

    private func formatTimeOnly(_ raw: String) -> String {
        guard let date = parseDate(raw) else {
            let clean = raw.replacingOccurrences(of: "T", with: " ")
            return clean.count > 5 ? String(clean.suffix(8).prefix(5)) : clean
        }
        return Self.timeFormatter.string(from: date)
    }
}

private protocol DateFormatterProtocol {
    func date(from string: String) -> Date?
}

extension DateFormatter: DateFormatterProtocol {}
extension ISO8601DateFormatter: DateFormatterProtocol {}
