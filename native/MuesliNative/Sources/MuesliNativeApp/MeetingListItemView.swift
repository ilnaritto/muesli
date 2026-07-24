import SwiftUI
import MuesliCore

struct MeetingListItemView: View {
    let record: MeetingRecord
    let isSelected: Bool
    let folders: [MeetingFolder]
    let isCompact: Bool
    private let folderByID: [Int64: MeetingFolder]
    private let folderIDsWithChildren: Set<Int64>
    let onSelect: () -> Void
    let onMove: (Int64?) -> Void
    let onCreateFolderAndMove: ((String) -> Void)?
    let onDelete: (() -> Void)?
    @State private var isHovering = false
    @State private var showDeleteConfirmation = false
    @State private var showFolderPopover = false
    @State private var showNewFolderPrompt = false
    @State private var newFolderName = ""

    init(
        record: MeetingRecord,
        isSelected: Bool,
        folders: [MeetingFolder],
        isCompact: Bool = false,
        onSelect: @escaping () -> Void,
        onMove: @escaping (Int64?) -> Void,
        onCreateFolderAndMove: ((String) -> Void)?,
        onDelete: (() -> Void)?
    ) {
        self.record = record
        self.isSelected = isSelected
        self.folders = folders
        self.isCompact = isCompact
        self.folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        self.folderIDsWithChildren = Set(folders.compactMap(\.parentID))
        self.onSelect = onSelect
        self.onMove = onMove
        self.onCreateFolderAndMove = onCreateFolderAndMove
        self.onDelete = onDelete
    }

    private var currentFolderName: String? {
        guard let fid = record.folderID else { return nil }
        guard let folder = folderByID[fid] else { return nil }
        // Build breadcrumb path: "Grandparent / Parent / Folder"
        var parts: [String] = [folder.name]
        var current = folder.parentID
        var seen: Set<Int64> = [folder.id]
        while let pid = current, let parent = folderByID[pid], seen.insert(pid).inserted {
            parts.insert(parent.name, at: 0)
            current = parent.parentID
        }
        return parts.joined(separator: " / ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : MuesliTheme.spacing8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.title)
                    .font(isCompact ? .system(size: 13, weight: .medium) : MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineLimit(isCompact ? 1 : 2)

                Spacer(minLength: 4)

                if isCompact {
                    HStack(spacing: MuesliTheme.spacing4) {
                        if record.status != .completed {
                            statusBadge
                        }
                        Text(formatDurationShort())
                            .font(MuesliTheme.caption())
                            .foregroundStyle(isSelected ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 6) {
                        if !folders.isEmpty {
                            folderMenuButton
                        }
                        if onDelete != nil {
                            deleteButton
                        }
                    }
                }
            }

            if !isCompact {
                HStack(spacing: MuesliTheme.spacing4) {
                    if record.status != .completed {
                        statusBadge
                        Text("\u{2022}")
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    Text(formatMeta())
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)

                    if let sourceIndicator = sourceIndicator {
                        sourceIndicator
                    }

                    // Current folder badge
                    if let name = currentFolderName {
                        Text("\u{2022}")
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                        HStack(spacing: 2) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text(name)
                                .font(MuesliTheme.caption())
                        }
                        .foregroundStyle(MuesliTheme.accent.opacity(0.8))
                    }
                }
            }

            if isCompact {
                // A fixed two-line preview area keeps every row the same height.
                Text(previewText())
                    .font(MuesliTheme.caption())
                    .foregroundStyle(isSelected ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(previewText())
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(isCompact ? MuesliTheme.spacing12 : MuesliTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isCompact {
                // Inset vertically so the selection fill never touches the
                // hairline separators between rows.
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isSelected ? MuesliTheme.selectionFill : Color.clear)
                    .padding(.vertical, 3)
            } else {
                RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                    .fill(isSelected ? MuesliTheme.surfaceSelected : MuesliTheme.backgroundRaised)
            }
        }
        .overlay {
            if !isCompact {
                RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                    .strokeBorder(
                        isSelected ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder,
                        lineWidth: 1
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .contextMenu {
            if !folders.isEmpty || onCreateFolderAndMove != nil {
                Menu(tr("Add to Folder", "Добавить в папку")) {
                    Button {
                        onMove(nil)
                    } label: {
                        if record.folderID == nil {
                            Label(tr("Unfiled", "Без папки"), systemImage: "checkmark")
                        } else {
                            Text(tr("Unfiled", "Без папки"))
                        }
                    }
                    if !folders.isEmpty {
                        Divider()
                        ForEach(folders) { folder in
                            Button {
                                onMove(folder.id)
                            } label: {
                                if record.folderID == folder.id {
                                    Label(folderBreadcrumb(folder), systemImage: "checkmark")
                                } else {
                                    Text(folderBreadcrumb(folder))
                                }
                            }
                        }
                    }
                    if onCreateFolderAndMove != nil {
                        Divider()
                        Button(tr("New Folder...", "Новая папка...")) {
                            newFolderName = ""
                            showNewFolderPrompt = true
                        }
                    }
                }
            }
            if onDelete != nil {
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(tr("Delete", "Удалить"), systemImage: "trash")
                }
            }
        }
        .alert(tr("New Folder", "Новая папка"), isPresented: $showNewFolderPrompt) {
            TextField(tr("Folder name", "Название папки"), text: $newFolderName)
            Button(tr("Create", "Создать")) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onCreateFolderAndMove?(trimmed)
                }
            }
            Button(tr("Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Create a new folder and move this meeting into it.", "Создать новую папку и переместить в неё эту встречу."))
        }
        .alert(tr("Delete Meeting", "Удалить встречу"), isPresented: $showDeleteConfirmation) {
            Button(tr("Delete", "Удалить"), role: .destructive) { onDelete?() }
            Button(tr("Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Are you sure you want to delete this meeting? Saved notes, transcript, and any retained recording will be removed.", "Удалить эту встречу? Сохранённые заметки, транскрипт и оставленная запись будут удалены."))
        }
    }

    // MARK: - Folder menu button

    private func folderBreadcrumb(_ folder: MeetingFolder) -> String {
        var parts: [String] = [folder.name]
        var current = folder.parentID
        var seen: Set<Int64> = [folder.id]
        while let pid = current, let parent = folderByID[pid], seen.insert(pid).inserted {
            parts.insert(parent.name, at: 0)
            current = parent.parentID
        }
        return parts.joined(separator: " / ")
    }

    @ViewBuilder
    private var folderMenuButton: some View {
        Button {
            showFolderPopover.toggle()
        } label: {
            Image(systemName: record.folderID != nil ? "folder.fill" : "folder.badge.plus")
                .font(.system(size: 11))
                .foregroundStyle(
                    record.folderID != nil
                        ? MuesliTheme.accent
                        : (isHovering ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                )
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("Move to folder", "Переместить в папку"))
        .popover(isPresented: $showFolderPopover, arrowEdge: isCompact ? .trailing : .leading) {
            VStack(alignment: .leading, spacing: 0) {
                folderPopoverRow(icon: "tray", label: tr("Unfiled", "Без папки"), isActive: record.folderID == nil) {
                    onMove(nil)
                    showFolderPopover = false
                }
                Divider().padding(.vertical, 4)
                ForEach(folders) { folder in
                    let hasChildren = folderIDsWithChildren.contains(folder.id)
                    folderPopoverRow(
                        icon: hasChildren ? "folder.fill" : "folder",
                        label: folderBreadcrumb(folder),
                        isActive: record.folderID == folder.id
                    ) {
                        onMove(folder.id)
                        showFolderPopover = false
                    }
                }
                if onCreateFolderAndMove != nil {
                    Divider().padding(.vertical, 4)
                    folderPopoverRow(icon: "folder.badge.plus", label: tr("New Folder...", "Новая папка...")) {
                        showFolderPopover = false
                        newFolderName = ""
                        showNewFolderPrompt = true
                    }
                }
            }
            .padding(8)
        }
    }

    /// Compact-row duration: seconds under a minute, "X min" under an hour,
    /// "h:mm" from an hour up.
    private func formatDurationShort() -> String {
        let total = Int(record.durationSeconds.rounded())
        if total >= 3600 {
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            return String(format: "%d:%02d", hours, minutes)
        }
        if total >= 60 {
            return tr("\(total / 60) min", "\(total / 60) мин")
        }
        return tr("\(total) sec", "\(total) сек")
    }

    @ViewBuilder
    private func folderPopoverRow(icon: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(label)
                    .font(MuesliTheme.callout())
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundStyle(
                    isHovering
                        ? MuesliTheme.recording.opacity(0.85)
                        : MuesliTheme.textTertiary
                )
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        .help(tr("Delete meeting", "Удалить встречу"))
    }

    // MARK: - Formatting

    private var statusBadge: some View {
        Text(record.status.displayLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(record.status.displayColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(record.status.displayColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var sourceIndicator: AnyView? {
        if let label = SyncOriginDisplay.badgeLabel(forMeetingSource: record.source) {
            return AnyView(SyncOriginBadge(label: label))
        }
        if isImportedAudio {
            return AnyView(sourceBadge(icon: "square.and.arrow.down", label: tr("Imported", "Импортировано"), help: tr("Imported audio", "Импортированное аудио")))
        }
        if hasSavedRecording {
            return AnyView(sourceBadge(icon: "waveform", label: tr("Recording", "Запись"), help: tr("Saved recording available", "Доступна сохранённая запись")))
        }
        return nil
    }

    private var isImportedAudio: Bool {
        record.source == .audioImport || hasLegacyImportedRecordingPath
    }

    private var hasLegacyImportedRecordingPath: Bool {
        guard let savedRecordingPath = record.savedRecordingPath else { return false }
        let filename = URL(fileURLWithPath: savedRecordingPath).lastPathComponent
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}_.+_[0-9A-Fa-f]{8}\.wav$"#
        return filename.range(of: pattern, options: .regularExpression) != nil
    }

    private var hasSavedRecording: Bool {
        guard let savedRecordingPath = record.savedRecordingPath else { return false }
        return !savedRecordingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sourceBadge(icon: String, label: String, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isImportedAudio ? MuesliTheme.accent : MuesliTheme.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isImportedAudio ? MuesliTheme.accent : MuesliTheme.textSecondary).opacity(0.12))
        .clipShape(Capsule())
        .help(help)
        .accessibilityLabel(help)
    }

    private func formatMeta() -> String {
        let time = MeetingBrowserLogic.formatStartTime(record.startTime)
        let duration = formatDuration(record.durationSeconds)
        return "\(time)  \u{2022}  \(duration)"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            return tr("\(rounded / 3600)h \((rounded % 3600) / 60)m", "\(rounded / 3600) ч \((rounded % 3600) / 60) мин")
        }
        if rounded >= 60 {
            let m = rounded / 60
            let s = rounded % 60
            return s == 0 ? tr("\(m)m", "\(m) мин") : tr("\(m)m \(s)s", "\(m) мин \(s) с")
        }
        return tr("\(rounded)s", "\(rounded) с")
    }

    private func previewText() -> String {
        let source: String
        if !record.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           record.status != .completed {
            source = record.manualNotes
        } else {
            source = record.formattedNotes.isEmpty ? record.rawTranscript : SummaryLayout.plainText(record.formattedNotes)
        }
        return MeetingPreviewText.snippet(from: source)
    }

}
