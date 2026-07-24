import AppKit
import SwiftUI
import MuesliCore

/// Left column of the meetings master-detail split: compact Coming Up,
/// recording banners, folder filter menu, and the meeting list.
struct MeetingsListPane: View {
    static let paneWidth: CGFloat = 320

    let appState: AppState
    let controller: MuesliController

    @State private var showNewFolderPrompt = false
    @State private var newFolderName = ""
    @State private var folderToRename: MeetingFolder?
    @State private var renameFolderName = ""
    @State private var folderToDelete: MeetingFolder?
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool

    private var scopedMeetings: [MeetingRecord] {
        appState.meetingRows
    }

    private var filteredMeetings: [MeetingRecord] {
        let base = MeetingBrowserLogic.filteredMeetings(
            from: scopedMeetings,
            filter: .all,
            sort: .newestFirst
        )
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(query)
                || meeting.formattedNotes.localizedCaseInsensitiveContains(query)
                || meeting.manualNotes.localizedCaseInsensitiveContains(query)
                || meeting.rawTranscript.localizedCaseInsensitiveContains(query)
        }
    }

    private var folderTree: FolderTreePresentation {
        FolderTreePresentation(folders: appState.folders, collapsedFolderIDs: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned header: search + folder tabs stay put, the list scrolls below.
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                searchBar
                folderTabs
            }
            .padding(.horizontal, 10)
            .padding(.top, MuesliTheme.spacing12)

            // The divider hugs the tabs so the selected-tab underline merges into it.
            Rectangle()
                .fill(MuesliTheme.surfaceBorder.opacity(0.7))
                .frame(height: 1)

            scrollingList
        }
    }

    private var scrollingList: some View {
        ScrollView {
                LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    if !appState.upcomingCalendarEvents.isEmpty {
                        compactComingUp
                    }

                    if appState.isMeetingStarting {
                        MeetingPreparationBanner(
                            status: appState.meetingStartStatus,
                            onCancel: { controller.cancelMeetingPreparation() }
                        )
                    }


                    if filteredMeetings.isEmpty {
                        compactEmptyState
                    } else {
                        meetingRows
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, MuesliTheme.spacing12)
        }
        .onChange(of: appState.focusSearchField) { _, shouldFocus in
            if shouldFocus, appState.selectedTab == .meetings {
                isSearchFocused = true
                appState.focusSearchField = false
            }
        }
        .alert(tr("New Folder", "Новая папка"), isPresented: $showNewFolderPrompt) {
            TextField(tr("Folder name", "Название папки"), text: $newFolderName)
            Button(tr("Cancel", "Отмена"), role: .cancel) { newFolderName = "" }
            Button(tr("Create", "Создать")) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                newFolderName = ""
                guard !trimmed.isEmpty else { return }
                if let id = controller.createFolder(name: trimmed) {
                    controller.showMeetingsHome(folderID: id)
                }
            }
        }
        .alert(
            tr("Rename \"\(folderToRename?.name ?? "")\"", "Переименовать «\(folderToRename?.name ?? "")»"),
            isPresented: Binding(
                get: { folderToRename != nil },
                set: { if !$0 { folderToRename = nil } }
            )
        ) {
            TextField(tr("Folder name", "Название папки"), text: $renameFolderName)
            Button(tr("Cancel", "Отмена"), role: .cancel) { folderToRename = nil }
            Button(tr("Rename", "Переименовать")) {
                let trimmed = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let folder = folderToRename, !trimmed.isEmpty {
                    controller.renameFolder(id: folder.id, name: trimmed)
                }
                folderToRename = nil
            }
        }
        .alert(
            tr("Delete \"\(folderToDelete?.name ?? "")\"?", "Удалить «\(folderToDelete?.name ?? "")»?"),
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            )
        ) {
            Button(tr("Cancel", "Отмена"), role: .cancel) {
                folderToDelete = nil
            }
            Button(tr("Delete", "Удалить"), role: .destructive) {
                if let folder = folderToDelete {
                    controller.deleteFolder(id: folder.id)
                    controller.showMeetingsHome(folderID: appState.selectedFolderID)
                }
                folderToDelete = nil
            }
        } message: {
            let directCount = folderToDelete.map { folder in
                appState.directMeetingCountsByFolder[folder.id] ?? 0
            } ?? 0
            if directCount > 0 {
                Text(tr("\(directCount) meeting\(directCount == 1 ? "" : "s") in this folder will be moved to Unfiled. Subfolders will be kept.", "Встреч в этой папке: \(directCount). Они будут перемещены в «Без папки». Вложенные папки сохранятся."))
            } else {
                Text(tr("This folder will be permanently removed. Subfolders will be kept.", "Эта папка будет удалена навсегда. Вложенные папки сохранятся."))
            }
        }
    }

    // MARK: - Search

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

    // MARK: - Folder tabs (Telegram style)

    @ViewBuilder
    private var folderTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MuesliTheme.spacing16) {
                    folderTab(id: nil, name: tr("All", "Все"))
                    ForEach(folderTree.visibleFolders) { folder in
                        folderTab(id: folder.id, name: folder.name)
                            .contextMenu {
                                Button(tr("Rename", "Переименовать")) {
                                    renameFolderName = folder.name
                                    folderToRename = folder
                                }
                                if folder.parentID != nil {
                                    Button(tr("Move to Top Level", "На верхний уровень")) {
                                        controller.moveFolder(id: folder.id, toParent: nil)
                                    }
                                }
                                Divider()
                                Button(tr("Delete", "Удалить"), role: .destructive) {
                                    folderToDelete = folder
                                }
                            }
                    }
                }
                .padding(.leading, 2)
                .padding(.trailing, 34)
        }
        .overlay(alignment: .trailing) {
            folderPlusOverlay
        }
    }

    /// Fixed "+" pinned to the right edge of the folder tabs row.
    /// Tabs scrolling underneath fade out through the gradient so long
    /// folder names never blend into the icon.
    private var folderPlusOverlay: some View {
        HStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: MuesliTheme.backgroundBase.opacity(0), location: 0),
                    .init(color: MuesliTheme.backgroundBase, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 24)
            .allowsHitTesting(false)

            Button {
                newFolderName = ""
                showNewFolderPrompt = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    // Lift the icon so it sits on the folder-name baseline,
                    // not centered over the underline zone below the text.
                    .offset(y: -4)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity)
            .background(MuesliTheme.backgroundBase)
            .help(tr("New folder", "Новая папка"))
        }
    }

    private func folderTab(id: Int64?, name: String) -> some View {
        let isSelected = appState.selectedFolderID == id
        return Button {
            controller.showMeetingsHome(folderID: id)
        } label: {
            VStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 3)
                UnevenRoundedRectangle(
                    topLeadingRadius: 2,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 2
                )
                .fill(isSelected ? MuesliTheme.accent : Color.clear)
                .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Meeting rows (grouped by day, flat with separators)

    private var groupedMeetings: [(header: String, records: [MeetingRecord])] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        var groups: [(header: String, records: [MeetingRecord])] = []
        var currentDayStart: Date?
        var currentRecords: [MeetingRecord] = []
        var currentHeader = ""

        for record in filteredMeetings {
            let date = MeetingBrowserLogic.parseDate(record.startTime) ?? now
            let dayStart = calendar.startOfDay(for: date)

            if dayStart != currentDayStart {
                if !currentRecords.isEmpty {
                    groups.append((header: currentHeader, records: currentRecords))
                }
                currentDayStart = dayStart
                currentRecords = []

                if dayStart == today {
                    currentHeader = tr("TODAY", "СЕГОДНЯ")
                } else if dayStart == yesterday {
                    currentHeader = tr("YESTERDAY", "ВЧЕРА")
                } else {
                    currentHeader = Self.dayGroupFormatter.string(from: date).uppercased()
                }
            }
            currentRecords.append(record)
        }
        if !currentRecords.isEmpty {
            groups.append((header: currentHeader, records: currentRecords))
        }

        return groups
    }

    private static let dayGroupFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEE, d MMM"
        return f
    }()

    @ViewBuilder
    private var meetingRows: some View {
        ForEach(Array(groupedMeetings.enumerated()), id: \.element.header) { _, group in
            VStack(alignment: .leading, spacing: 2) {
                Text(group.header)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.leading, MuesliTheme.spacing4)
                    .padding(.top, MuesliTheme.spacing8)

                VStack(alignment: .leading, spacing: 0) {
                    let lastID = group.records.last?.id
                    let liveID = controller.activeLiveMeetingRecord()?.id
                    ForEach(group.records) { meeting in
                        if meeting.id == liveID {
                            // The active meeting renders as its own row with
                            // the recording controls inline — no separate
                            // banner card above the list.
                            liveMeetingRow(meeting)
                                .id(meeting.id)
                        } else {
                            MeetingListItemView(
                                record: meeting,
                                isSelected: appState.selectedMeetingID == meeting.id,
                                folders: appState.folders,
                                isCompact: true,
                                onSelect: { controller.showMeetingDocument(id: meeting.id) },
                                onMove: { folderID in
                                    controller.moveMeeting(id: meeting.id, toFolder: folderID)
                                },
                                onCreateFolderAndMove: { name in
                                    controller.createFolderAndMoveMeeting(name: name, meetingID: meeting.id)
                                },
                                onDelete: controller.canDeleteMeeting(meeting) ? {
                                    controller.deleteMeeting(id: meeting.id)
                                } : nil
                            )
                            .id(meeting.id)
                        }

                        if meeting.id != lastID {
                            Rectangle()
                                .fill(MuesliTheme.surfaceBorder.opacity(0.7))
                                .frame(height: 1)
                                .padding(.leading, MuesliTheme.spacing12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Compact Coming Up

    private struct UpcomingEventGroup: Identifiable {
        let id: String
        let date: Date
        let dayLabel: String
        let isToday: Bool
        let events: [UnifiedCalendarEvent]
    }

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private static let maxUpcomingEvents = 5

    private var groupedUpcomingEvents: [UpcomingEventGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let timedEvents = appState.upcomingCalendarEvents.filter {
            !$0.isAllDay && !appState.hiddenCalendarEventIDs.contains($0.id)
        }
        let grouped = Dictionary(grouping: timedEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }

        let sortedDates = grouped.keys.sorted()
        var result: [UpcomingEventGroup] = []
        var remaining = Self.maxUpcomingEvents

        for date in sortedDates {
            guard remaining > 0 else { break }
            let sortedEvents = grouped[date]!.sorted { $0.startDate < $1.startDate }
            let limitedEvents = Array(sortedEvents.prefix(remaining))
            remaining -= limitedEvents.count

            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isTomorrow = calendar.date(byAdding: .day, value: 1, to: today).map { calendar.isDate(date, inSameDayAs: $0) } ?? false
            let dayLabel: String
            if isToday {
                dayLabel = tr("Today", "Сегодня")
            } else if isTomorrow {
                dayLabel = tr("Tomorrow", "Завтра")
            } else {
                dayLabel = Self.dayHeaderFormatter.string(from: date)
            }
            result.append(UpcomingEventGroup(
                id: date.description,
                date: date,
                dayLabel: dayLabel,
                isToday: isToday,
                events: limitedEvents
            ))
        }

        return result
    }

    @ViewBuilder
    private var compactComingUp: some View {
        let groups = groupedUpcomingEvents
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text(tr("Coming Up", "Предстоящие"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .textCase(.uppercase)

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.dayLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(group.isToday ? MuesliTheme.accent : MuesliTheme.textSecondary)
                        ForEach(group.events) { event in
                            compactEventRow(event, isToday: group.isToday)
                        }
                    }
                }

                if appState.isGoogleCalendarAuthenticated {
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 8))
                            Text(tr("Add Google to macOS Calendar for real-time sync", "Добавьте Google в Календарь macOS для синхронизации"))
                                .font(.system(size: 9))
                                .lineLimit(2)
                        }
                        .foregroundStyle(MuesliTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(MuesliTheme.spacing12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func compactEventRow(_ event: UnifiedCalendarEvent, isToday: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isToday ? MuesliTheme.accent : MuesliTheme.textSecondary.opacity(0.4))
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineLimit(1)
                Text("\(Self.timeFormatter.string(from: event.startDate)) – \(Self.timeFormatter.string(from: event.endDate))")
                    .font(.system(size: 10))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            Spacer(minLength: 4)

            if let meetingURL = event.meetingURL,
               !appState.isMeetingRecording,
               !appState.isMeetingStarting {
                Button {
                    controller.joinAndRecord(title: event.title, meetingURL: meetingURL, endDate: event.endDate)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 18)
                        .background(Color(nsColor: NSColor(red: 0.20, green: 0.72, blue: 0.53, alpha: 1.0)))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(tr("Join & Record", "Присоединиться и записать"))
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    controller.hideCalendarEvent(event)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary.opacity(0.6))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(tr("Hide from Coming Up", "Скрыть из предстоящих"))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(tr("All Meetings", "Все встречи")) {
                controller.createMeetingFromCalendarEvent(event, folderID: nil)
            }
            if !appState.folders.isEmpty {
                Divider()
                ForEach(appState.folders) { folder in
                    Button(folder.name) {
                        controller.createMeetingFromCalendarEvent(event, folderID: folder.id)
                    }
                }
            }
        }
    }

    // MARK: - Active meeting row (inline banner replacement)

    /// The live meeting's list row: title + status with the recording
    /// controls inline, styled like a regular row.
    @ViewBuilder
    private func liveMeetingRow(_ meeting: MeetingRecord) -> some View {
        let isSelected = appState.selectedMeetingID == meeting.id
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: MuesliTheme.spacing8) {
                Circle()
                    .fill(activeMeetingStatusColor(for: meeting))
                    .frame(width: 8, height: 8)
                Text(meeting.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)

                if meeting.status == .recording {
                    Button {
                        controller.toggleMeetingRecordingPause()
                    } label: {
                        Image(systemName: appState.isMeetingRecordingPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(appState.isMeetingRecordingPaused ? MuesliTheme.backgroundBase : MuesliTheme.textPrimary)
                            .frame(width: 26, height: 24)
                            .background(appState.isMeetingRecordingPaused ? MuesliTheme.accent : MuesliTheme.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.isMeetingRecording)
                    .help(appState.isMeetingRecordingPaused ? tr("Resume", "Продолжить") : tr("Pause", "Пауза"))

                    Button {
                        controller.stopMeetingRecording()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 24)
                            .background(MuesliTheme.recording)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.isMeetingRecording)
                    .help(tr("Stop", "Стоп"))
                }
            }

            // Same fixed preview zone as regular rows so heights line up.
            Text(activeMeetingStatusText(for: meeting))
                .font(MuesliTheme.caption())
                .foregroundStyle(isSelected ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                .lineLimit(2)
                .frame(height: 30, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MuesliTheme.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(isSelected ? MuesliTheme.selectionFill : Color.clear)
                .padding(.vertical, 3)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            controller.showMeetingDocument(id: meeting.id)
        }
    }

    private func activeMeetingStatusText(for meeting: MeetingRecord) -> String {
        guard meeting.status == .recording else { return tr("Finalizing notes", "Завершение заметок") }
        return appState.isMeetingRecordingPaused ? tr("Recording paused", "Запись приостановлена") : tr("Recording now", "Идёт запись")
    }

    private func activeMeetingStatusColor(for meeting: MeetingRecord) -> Color {
        guard meeting.status == .recording else { return MuesliTheme.accent }
        return appState.isMeetingRecordingPaused ? MuesliTheme.transcribing : MuesliTheme.recording
    }

    // MARK: - Empty state

    @ViewBuilder
    private var compactEmptyState: some View {
        VStack(alignment: .center, spacing: MuesliTheme.spacing8) {
            Image(systemName: appState.selectedFolderID == nil ? "person.2.wave.2" : "folder")
                .font(.system(size: 24, weight: .thin))
                .foregroundStyle(MuesliTheme.textTertiary)

            Text(appState.selectedFolderID == nil ? tr("No meetings yet", "Пока нет встреч") : tr("No meetings in this folder", "В этой папке нет встреч"))
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textSecondary)

            Text(
                appState.selectedFolderID == nil
                    ? tr("Start a recording from the menu bar to create your first meeting note.", "Начните запись из строки меню, чтобы создать первую заметку встречи.")
                    : tr("Choose another folder or move a meeting here from the browser.", "Выберите другую папку или переместите сюда встречу из списка.")
            )
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textTertiary)
            .multilineTextAlignment(.center)
        }
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .padding(.top, MuesliTheme.spacing8)
    }
}

/// The "+" quick-actions menu shown in the primary column header
/// on the Meetings tab.
struct MeetingsHeaderControls: View {
    let appState: AppState
    let controller: MuesliController

    private var busy: Bool { appState.isMeetingRecording || appState.isMeetingStarting }

    var body: some View {
        HStack(spacing: 2) {
            // Start an audio meeting.
            Button {
                controller.startQuickNoteMeeting()
            } label: {
                headerIcon("waveform")
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .help(tr("New meeting (audio)", "Новая встреча (аудио)"))

            // Start a meeting recorded with screen video.
            Button {
                _ = controller.startForegroundMeetingRecording(withScreenVideo: true)
            } label: {
                headerIcon("video")
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .help(tr("Meeting with video", "Встреча с видео"))

            // Import an existing audio or video file as a meeting.
            // The icon is drawn as a plain image (identical to the two buttons
            // on its left); an invisible Menu is overlaid to catch the click.
            // A borderless Menu label would otherwise re-tint and shift the glyph.
            headerIcon("square.and.arrow.down")
                .overlay(
                    Menu {
                        Button {
                            controller.importAudioFile()
                        } label: {
                            Label(tr("Import Audio", "Импорт аудио"), systemImage: "waveform")
                        }
                        .disabled(busy)
                        Button {
                            controller.importVideoFile()
                        } label: {
                            Label(tr("Import Video", "Импорт видео"), systemImage: "video")
                        }
                        .disabled(busy)
                    } label: {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                )
                // The arrow-in-box glyph optically sits a touch low; nudge it up.
                .offset(y: -1)
                .help(tr("Import audio or video", "Импорт аудио или видео"))
        }
    }

    private func headerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MuesliTheme.textSecondary)
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
    }
}
