import AVKit
import SwiftUI
import MuesliCore

private enum MeetingDocumentMode: Hashable {
    case notes
    case transcript
}

private enum RecordingContentMode: Hashable {
    case notes
    case live
}

private enum ManualNotesSaveStatus {
    case saved
    case saving

    var label: String {
        switch self {
        case .saved: return tr("Saved", "Сохранено")
        case .saving: return tr("Saving...", "Сохранение...")
        }
    }
}

// Wrapper views that isolate observation of liveMeetingTranscript.
// Without these, MeetingDetailView.body would observe the property and
// re-evaluate on every chunk (every ~5s), re-rendering the entire detail view.
// Each wrapper is the sole observer — MeetingDetailView passes appState by
// reference and never reads liveMeetingTranscript in its own body.
private struct LiveTranscriptSection: View {
    let appState: AppState
    let transcriptPrefix: String

    var body: some View {
        LiveTranscriptView(
            transcript: MeetingResumePolicy.combinedResumeTranscript(
                prior: transcriptPrefix,
                new: appState.liveMeetingTranscript
            )
        )
    }
}

struct MeetingDetailView: View {
    let meeting: MeetingRecord?
    let controller: MuesliController
    let appState: AppState
    let onBack: (() -> Void)?
    let backLabel: String
    @State private var isSummarizing = false
    @State private var isRetranscribing = false
    @State private var isEditingNotes = false
    @State private var isEditingTranscript = false
    @State private var editableTitle: String
    @State private var editableNotes: String
    @State private var editableTranscript: String
    @State private var editableManualNotes: String
    @State private var loadedMeetingID: Int64?
    @State private var manualNotesSaveStatus: ManualNotesSaveStatus = .saved
    @State private var manualEditorCommand: MarkdownEditorCommand?
    @State private var pendingTemplateID: String
    @State private var documentMode: MeetingDocumentMode
    @State private var showTranscriptSearch = false
    @State private var isAIChatMode = false
    @State private var recordingMode: RecordingContentMode = .notes
    @State private var titleSaveTask: DispatchWorkItem?
    @State private var notesSaveTask: DispatchWorkItem?
    @State private var transcriptSaveTask: DispatchWorkItem?
    @State private var manualNotesSaveStatusTask: DispatchWorkItem?
    @State private var summaryErrorMessage: String?
    @State private var retranscriptionErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var transcriptResummaryPromptMeetingID: Int64?
    @State private var transcriptEditOriginalTranscript: String?
    @State private var transcriptEditHadStructuredNotes = false
    @State private var showFolderPopover = false
    @State private var showNewFolderPrompt = false
    @State private var newFolderName = ""
    @State private var isMediaPanelOpen = false
    /// Actual rendered height of the floating header — replaces hand-tuned
    /// clearance constants now that the media panel height is dynamic.
    @State private var floatingHeaderMeasuredHeight: CGFloat?

    init(
        meeting: MeetingRecord?,
        controller: MuesliController,
        appState: AppState,
        onBack: (() -> Void)? = nil,
        backLabel: String = tr("Back to Meetings", "Назад к встречам")
    ) {
        self.meeting = meeting
        self.controller = controller
        self.appState = appState
        self.onBack = onBack
        self.backLabel = backLabel
        let initialTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        _editableTitle = State(initialValue: meeting?.title ?? "")
        _editableNotes = State(initialValue: meeting.map { Self.notesContent(for: $0) } ?? "")
        _editableTranscript = State(initialValue: meeting?.rawTranscript ?? "")
        _editableManualNotes = State(initialValue: meeting?.manualNotes ?? "")
        _loadedMeetingID = State(initialValue: meeting?.id)
        _pendingTemplateID = State(initialValue: initialTemplateID)
        _documentMode = State(initialValue: meeting.map(Self.defaultDocumentMode(for:)) ?? .notes)
    }

    var body: some View {
        Group {
            if let meeting {
                Group {
                    if showsManualNotesEditor(for: meeting) {
                        VStack(alignment: .leading, spacing: 0) {
                            header(meeting)
                            content(for: meeting)
                        }
                    } else {
                        // Completed meetings: floating Telegram-style header —
                        // the content scrolls behind the pill and the tabs row.
                        ZStack(alignment: .top) {
                            if isAIChatMode {
                                MeetingAIChatPage(meeting: meeting, controller: controller, appState: appState)
                                    // Per-meeting identity: the draft resets on
                                    // switch, while the conversation itself is
                                    // kept in AppState keyed by meeting id.
                                    .id(meeting.id)
                                    .padding(.top, floatingHeaderClearance(for: meeting) + MuesliTheme.spacing8)
                            } else if isMediaPanelOpen, hasPlayableMedia(meeting) {
                                mediaPage(for: meeting)
                                    .padding(.top, floatingHeaderClearance(for: meeting) + MuesliTheme.spacing8)
                            } else if isEditingNotes || isEditingTranscript {
                                editingPage(for: meeting)
                                    .padding(.top, floatingHeaderClearance(for: meeting) + MuesliTheme.spacing8)
                            } else if hasCompletedExtras(meeting) {
                                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                                    completedExtras(meeting)
                                    content(for: meeting)
                                }
                                .padding(.top, floatingHeaderClearance(for: meeting))
                            } else {
                                // The scroll frame reaches the very top of the pane;
                                // the margin lives INSIDE the scroll view, so text
                                // travels behind the floating pill and tabs.
                                content(for: meeting)
                                    .contentMargins(.top, floatingHeaderClearance(for: meeting) + MuesliTheme.spacing8, for: .scrollContent)
                            }

                            headerBackdropGradient(for: meeting)
                            floatingHeader(meeting)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { height in
                                    floatingHeaderMeasuredHeight = height
                                }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            VStack(spacing: MuesliTheme.spacing8) {
                                if isEditingNotes || isEditingTranscript {
                                    // Editing: only the finish-editing checkmark.
                                    editChip(for: meeting)
                                } else if isOverlayPageOpen(meeting) {
                                    // Chat/video pages: the chips act on the
                                    // summary/transcript text and don't belong here.
                                    EmptyView()
                                } else {
                                    editChip(for: meeting)
                                    if documentMode == .notes {
                                        regenerateChip(for: meeting)
                                    }
                                    copyChip(for: meeting)
                                }
                            }
                            .padding(.top, MuesliTheme.spacing12)
                            .padding(.leading, MuesliTheme.spacing12)
                            // While editing, the checkmark keeps an equal gap
                            // from the right and bottom edges; otherwise the
                            // bottom gap mirrors the header's top offset.
                            .padding(.trailing, isEditingNotes || isEditingTranscript ? 20 : MuesliTheme.spacing12)
                            .padding(.bottom, isEditingNotes || isEditingTranscript ? 20 : 15)
                        }
                    }
                }
                .onChange(of: meeting.id) { _, _ in
                    syncLocalState(with: meeting)
                }
                .onChange(of: meeting.status) { _, _ in
                    syncLocalState(with: meeting)
                }
                .onChange(of: meeting.manualNotes) { _, _ in
                    syncManualNotesState(with: meeting)
                }
                .onChange(of: appState.config.customMeetingTemplates) { _, _ in
                    syncPendingTemplateSelectionIfNeeded(for: meeting)
                }
            } else {
                VStack(spacing: MuesliTheme.spacing12) {
                    Text(tr("No meeting selected", "Встреча не выбрана"))
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textSecondary)
                    Text(tr("Choose a meeting from the Meetings browser to open it here.", "Выберите встречу в списке встреч, чтобы открыть её здесь."))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert(tr("Couldn't Save Summary", "Не удалось сохранить сводку"), isPresented: summaryErrorBinding) {
            Button(tr("OK", "ОК"), role: .cancel) {
                summaryErrorMessage = nil
            }
        } message: {
            Text(summaryErrorMessage ?? tr("The updated meeting notes could not be saved.", "Не удалось сохранить обновлённые заметки встречи."))
        }
        .alert(tr("Couldn't Re-transcribe Meeting", "Не удалось повторно транскрибировать встречу"), isPresented: retranscriptionErrorBinding) {
            Button(tr("OK", "ОК"), role: .cancel) {
                retranscriptionErrorMessage = nil
            }
        } message: {
            Text(retranscriptionErrorMessage ?? tr("The saved recording could not be re-transcribed.", "Не удалось повторно транскрибировать сохранённую запись."))
        }
        .alert(tr("Re-summarize Notes?", "Пересоздать сводку заметок?"), isPresented: transcriptResummaryPromptBinding) {
            Button(tr("Re-summarize", "Пересоздать сводку")) {
                resummarizeAfterTranscriptEdit()
            }
            Button(tr("Not Now", "Не сейчас"), role: .cancel) {
                transcriptResummaryPromptMeetingID = nil
            }
        } message: {
            Text(tr("Your transcript edits may change the generated notes. Re-summarize now to update them from the edited transcript.", "Изменения транскрипта могут повлиять на созданные заметки. Пересоздайте сводку, чтобы обновить их по отредактированному транскрипту."))
        }
        .alert(tr("Delete Meeting", "Удалить встречу"), isPresented: $showDeleteConfirmation) {
            Button(tr("Delete", "Удалить"), role: .destructive) {
                if let meeting {
                    controller.deleteMeeting(id: meeting.id)
                }
            }
            Button(tr("Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Are you sure you want to delete this meeting? Saved notes, transcript, and any retained recording will be removed.", "Вы действительно хотите удалить эту встречу? Сохранённые заметки, транскрипт и запись будут удалены."))
        }
    }

    @ViewBuilder
    private func header(_ meeting: MeetingRecord) -> some View {
        let appliedTemplate = controller.meetingTemplateSnapshot(for: meeting)
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(backLabel)
                            .font(MuesliTheme.callout())
                    }
                    .foregroundStyle(MuesliTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            headerRow(meeting, appliedTemplate: appliedTemplate)

            if meeting.status == .recording {
                contentTabsCard(meeting)
            }

            if let savedRecordingPath = meeting.savedRecordingPath,
               FileManager.default.fileExists(atPath: savedRecordingPath) {
                MeetingRecordingPlayerView(recordingPath: savedRecordingPath)
            }

            activeMeetingAudioWarningBanner(for: meeting)
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, MuesliTheme.spacing8)
    }

    /// Summarize CTA for completed meetings — rendered at the top of the
    /// scrolling area, below the floating header. The recording player lives
    /// in the collapsible media panel of the floating header now.
    @ViewBuilder
    private func completedExtras(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            if isRawTranscript(meeting), documentMode == .notes {
                transcriptCTA
            }
        }
        .padding(.horizontal, MuesliTheme.spacing12)
    }

    // MARK: - Telegram-style header (pill + circular chips)

    /// Vertical space the scrolling content leaves for the floating header.
    private func floatingHeaderClearance(for meeting: MeetingRecord) -> CGFloat {
        if let measured = floatingHeaderMeasuredHeight {
            return measured
        }
        let base: CGFloat = (onBack != nil ? 28 : 0) + 114
        guard isMediaPanelOpen else { return base }
        // Fallbacks until the first measurement arrives.
        if existingVideoPath(for: meeting) != nil { return base + 265 }
        if existingRecordingPath(for: meeting) != nil { return base + 85 }
        return base
    }

    private func hasCompletedExtras(_ meeting: MeetingRecord) -> Bool {
        isRawTranscript(meeting) && documentMode == .notes
    }

    /// Path of the saved recording if the file actually exists on disk.
    private func existingRecordingPath(for meeting: MeetingRecord) -> String? {
        guard let path = meeting.savedRecordingPath,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    /// Path of the saved screen video if the file actually exists on disk.
    private func existingVideoPath(for meeting: MeetingRecord) -> String? {
        guard let path = meeting.savedVideoPath,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    private func hasPlayableMedia(_ meeting: MeetingRecord) -> Bool {
        existingRecordingPath(for: meeting) != nil || existingVideoPath(for: meeting) != nil
    }

    /// True while the chat or media page replaces the notes/transcript content.
    private func isOverlayPageOpen(_ meeting: MeetingRecord) -> Bool {
        isAIChatMode || (isMediaPanelOpen && hasPlayableMedia(meeting))
    }

    /// Soft fade under the floating pills so text scrolling behind them
    /// dims out instead of glowing through.
    private func headerBackdropGradient(for meeting: MeetingRecord) -> some View {
        LinearGradient(
            stops: [
                .init(color: MuesliTheme.backgroundDeep.opacity(0.7), location: 0),
                .init(color: MuesliTheme.backgroundDeep.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: floatingHeaderClearance(for: meeting) + 20)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func floatingHeader(_ meeting: MeetingRecord) -> some View {
        let appliedTemplate = controller.meetingTemplateSnapshot(for: meeting)
        VStack(alignment: .leading, spacing: 9) {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(backLabel)
                            .font(MuesliTheme.callout())
                    }
                    .foregroundStyle(MuesliTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            headerRow(meeting, appliedTemplate: appliedTemplate)

            templateTabsRow(meeting)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        // The pane now reaches the window's top edge; the chips' bottom gap
        // mirrors this same offset.
        .padding(.top, 15)
    }

    @ViewBuilder
    private func headerRow(_ meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        // The title pill stretches to fill leftover width, so every gap in
        // the row is the same 11pt.
        HStack(spacing: 11) {
            headerPill(meeting)

            if showsManualNotesEditor(for: meeting) {
                recordingControlGroup(for: meeting)
            } else {
                headerFolderButton(for: meeting)
                headerSearchButton(for: meeting)
                headerMoreMenu(for: meeting, appliedTemplate: appliedTemplate)
            }
        }
    }

    @ViewBuilder
    private func headerPill(_ meeting: MeetingRecord) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            ZStack {
                Circle()
                    .fill(MuesliTheme.accentSubtle)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 0) {
                MarqueeTitleTextField(
                    text: $editableTitle,
                    onSubmit: {
                        controller.updateMeetingTitle(id: meeting.id, title: editableTitle)
                    },
                    onTextChange: {
                        debounceSaveTitle(meetingID: meeting.id)
                    },
                    titleFont: .system(size: 13, weight: .semibold),
                    minHeight: 16
                )
                Text(formatMetaShort(meeting))
                    .font(.system(size: 10))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Capsule().fill(MuesliTheme.backgroundBase))
        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    /// A standalone circular action chip, Telegram-style.
    private func headerIcon(_ systemName: String, active: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(active ? MuesliTheme.accent : MuesliTheme.textSecondary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(active ? MuesliTheme.accentSubtle : MuesliTheme.backgroundBase))
            .overlay(Circle().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
            .contentShape(Circle())
    }

    /// A solid accent action chip — used for confirm actions (e.g. the
    /// finish-editing checkmark), distinct from the subtle active-tab look.
    private func solidHeaderIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(MuesliTheme.accent))
            .contentShape(Circle())
    }

    private func copyChip(for meeting: MeetingRecord) -> some View {
        Button {
            controller.copyToClipboard(activeCopyText(for: meeting))
        } label: {
            headerIcon("doc.on.doc")
        }
        .buttonStyle(.plain)
        .help(copyButtonLabel)
    }

    /// Toggles notes/transcript editing; shows a checkmark while editing.
    private func editChip(for meeting: MeetingRecord) -> some View {
        Button {
            performEditToggle(for: meeting)
        } label: {
            if isEditingNotes || isEditingTranscript {
                solidHeaderIcon("checkmark")
            } else {
                headerIcon("pencil")
            }
        }
        .buttonStyle(.plain)
        .disabled(isRetranscribing && !isEditingNotes && !isEditingTranscript)
        .help(editButtonLabel)
    }

    /// Manual regeneration — tabs themselves never re-call the LLM for a
    /// summary that already exists.
    private func regenerateChip(for meeting: MeetingRecord) -> some View {
        Button {
            selectAndApplyTemplate(id: pendingTemplateID, for: meeting)
        } label: {
            headerIcon("arrow.triangle.2.circlepath")
        }
        .buttonStyle(.plain)
        .disabled(isSummarizing || isRetranscribing)
        .help(tr("Regenerate summary", "Пересоздать сводку"))
    }

    /// AI-chat chip, media chip, transcript chip, and the tabs capsule
    /// stretching to the right edge.
    @ViewBuilder
    private func templateTabsRow(_ meeting: MeetingRecord) -> some View {
        HStack(spacing: 11) {
            headerAIChatButton
            if hasPlayableMedia(meeting) {
                mediaChip(for: meeting)
            }
            transcriptChip(for: meeting)
            templateTabsCapsule(meeting)
        }
    }

    /// Shows the raw transcript instead of the template notes.
    private func transcriptChip(for meeting: MeetingRecord) -> some View {
        Button {
            isAIChatMode = false
            isMediaPanelOpen = false
            documentMode = .transcript
        } label: {
            headerIcon(
                "text.alignleft",
                active: !isOverlayPageOpen(meeting) && documentMode == .transcript
            )
        }
        .buttonStyle(.plain)
        .disabled(isEditingNotes || isEditingTranscript)
        .help(tr("Transcript", "Транскрипт"))
    }

    /// Toggles the playback panel below the tabs row: a video icon when a
    /// screen recording exists, a waveform icon for audio-only meetings.
    private func mediaChip(for meeting: MeetingRecord) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isMediaPanelOpen.toggle()
                if isMediaPanelOpen { isAIChatMode = false }
            }
        } label: {
            headerIcon(
                existingVideoPath(for: meeting) != nil ? "video" : "waveform",
                active: isMediaPanelOpen
            )
        }
        .buttonStyle(.plain)
        .help(tr("Meeting recording", "Запись встречи"))
    }

    /// Full playback page shown instead of the notes/transcript content.
    /// Video keeps its own aspect ratio and fits the available area; a text
    /// button below reveals the file in Finder.
    @ViewBuilder
    private func mediaPage(for meeting: MeetingRecord) -> some View {
        VStack(spacing: MuesliTheme.spacing16) {
            if let videoPath = existingVideoPath(for: meeting) {
                MeetingVideoPanel(videoPath: videoPath)
                mediaFinderButton(path: videoPath)
            } else if let audioPath = existingRecordingPath(for: meeting) {
                MeetingRecordingPlayerView(recordingPath: audioPath)
                    .padding(MuesliTheme.spacing8)
                    .background(RoundedRectangle(cornerRadius: 20).fill(MuesliTheme.backgroundBase))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
                    .frame(maxWidth: 760)
                mediaFinderButton(path: audioPath)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Align with the floating header plashki above (leading 6 / trailing 8).
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.bottom, MuesliTheme.spacing16)
    }

    /// Full-page summary/transcript editor shown instead of the content:
    /// a single rounded input block (same style as the template prompt
    /// editor) pinned below the header rows and stretching to the bottom.
    @ViewBuilder
    private func editingPage(for meeting: MeetingRecord) -> some View {
        Group {
            if isEditingNotes {
                TextEditor(text: $editableNotes)
                    .font(.system(size: 13, design: .monospaced))
                    .onChange(of: editableNotes) { _, _ in
                        debounceSaveNotes(meetingID: meeting.id)
                    }
            } else {
                TextEditor(text: $editableTranscript)
                    .font(.system(size: 14))
                    .onChange(of: editableTranscript) { _, _ in
                        debounceSaveTranscript(meetingID: meeting.id)
                    }
            }
        }
        .foregroundStyle(MuesliTheme.textPrimary)
        .scrollContentBackground(.hidden)
        .padding(MuesliTheme.spacing16)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Align with the floating header plashki above (leading 6 / trailing 8);
        // bottom gap mirrors the header's 15pt top offset.
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.bottom, 15)
    }

    private func mediaFinderButton(path: String) -> some View {
        Button {
            controller.revealMeetingRecordingInFinder(path: path)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                Text(tr("Show in Finder", "Показать в Finder"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(MuesliTheme.backgroundBase))
            .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func templateTabsCapsule(_ meeting: MeetingRecord) -> some View {
        HStack(alignment: .center, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: MuesliTheme.spacing16) {
                    // One unified list: an edited built-in keeps its slot and
                    // shows the customized name in place.
                    ForEach(controller.enabledMeetingTemplates()) { template in
                        templateTab(id: template.id, title: template.title, for: meeting)
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 70)
                .frame(height: 40)
            }

            if isRetranscribing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(tr("Re-transcribing...", "Повторная транскрипция..."))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .padding(.trailing, MuesliTheme.spacing12)
            }
        }
        .frame(height: 40)
        .background(Capsule().fill(MuesliTheme.backgroundBase))
        .overlay(alignment: .trailing) {
            templateGearOverlay
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    /// Fixed gear pinned inside the right edge of the tabs capsule; tabs
    /// scrolling underneath fade out through the gradient (same pattern as
    /// the folder tabs in the meetings list). Opens the templates manager.
    private var templateGearOverlay: some View {
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
                controller.showMeetingTemplatesManager()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    // 40pt zone flush with the capsule edge: the glyph center
                    // lands 20pt from the right, on the same vertical axis as
                    // the "⋯" chip above.
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(MuesliTheme.backgroundBase)
            .help(tr("Manage templates", "Управление шаблонами"))
        }
        .frame(height: 40)
    }

    /// A tab that selects the notes view; the template only generates when the
    /// meeting has no summary for it yet — otherwise the cached one is restored.
    @ViewBuilder
    private func templateTab(id: String, title: String, for meeting: MeetingRecord) -> some View {
        let isBuiltIn = MeetingTemplates.builtIns.contains { $0.id == id }
        let hasCustomEntry = controller.customMeetingTemplates().contains { $0.id == id }
        contentTab(title, isSelected: !isOverlayPageOpen(meeting) && documentMode == .notes && pendingTemplateID == id) {
            isAIChatMode = false
            isMediaPanelOpen = false
            if documentMode == .notes, pendingTemplateID == id { return }
            documentMode = .notes
            if pendingTemplateID != id {
                switchToTemplate(id: id, for: meeting)
            }
        }
        .disabled(isEditingNotes || isEditingTranscript || isSummarizing)
        .contextMenu {
            if id != MeetingTemplates.autoID {
                Button(tr("Edit…", "Редактировать…")) {
                    controller.showMeetingTemplateEditor(templateID: id)
                }
                if isBuiltIn, hasCustomEntry {
                    Button(tr("Reset to Default", "Сбросить к стандартному")) {
                        controller.resetBuiltInMeetingTemplate(id: id)
                    }
                }
                if !isBuiltIn, hasCustomEntry {
                    Divider()
                    Button(tr("Delete", "Удалить"), role: .destructive) {
                        controller.deleteCustomMeetingTemplate(id: id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func headerFolderButton(for meeting: MeetingRecord) -> some View {
        let currentFolderName = meeting.folderID.flatMap { id in
            appState.folders.first(where: { $0.id == id })?.name
        }
        Menu {
            Button {
                controller.moveMeeting(id: meeting.id, toFolder: nil)
            } label: {
                if meeting.folderID == nil {
                    Label(tr("Unfiled", "Без папки"), systemImage: "checkmark")
                } else {
                    Text(tr("Unfiled", "Без папки"))
                }
            }
            if !appState.folders.isEmpty {
                Divider()
                ForEach(appState.folders) { folder in
                    Button {
                        controller.moveMeeting(id: meeting.id, toFolder: folder.id)
                    } label: {
                        if meeting.folderID == folder.id {
                            Label(folder.name, systemImage: "checkmark")
                        } else {
                            Text(folder.name)
                        }
                    }
                }
            }
            Divider()
            Button(tr("New Folder...", "Новая папка...")) {
                newFolderName = ""
                showNewFolderPrompt = true
            }
        } label: {
            if let currentFolderName {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                    Text(currentFolderName)
                        .font(.system(size: 11, weight: .regular))
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(MuesliTheme.textSecondary)
            } else {
                // No folder yet: a bare circular chip, same look as the search chip.
                Image(systemName: "folder")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Padding must live OUTSIDE the Menu: the borderless menu style strips
        // padding applied inside the label, which left the capsule edge-to-edge.
        .padding(.horizontal, currentFolderName == nil ? 0 : 18)
        .frame(height: 40)
        .frame(minWidth: 40)
        .background(Capsule().fill(MuesliTheme.backgroundBase))
        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
        .contentShape(Capsule())
        .help(tr("Move to folder", "Переместить в папку"))
        .alert(tr("New Folder", "Новая папка"), isPresented: $showNewFolderPrompt) {
            TextField(tr("Folder name", "Название папки"), text: $newFolderName)
            Button(tr("Create", "Создать")) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                controller.createFolderAndMoveMeeting(name: trimmed, meetingID: meeting.id)
            }
            Button(tr("Cancel", "Отмена"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func headerSearchButton(for meeting: MeetingRecord) -> some View {
        Button {
            showTranscriptSearch = true
        } label: {
            headerIcon("magnifyingglass")
        }
        .buttonStyle(.plain)
        .help(tr("Search transcript", "Поиск по транскрипту"))
        .popover(isPresented: $showTranscriptSearch, arrowEdge: .bottom) {
            TranscriptSearchPopover(transcript: meeting.rawTranscript)
        }
    }

    private var headerAIChatButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isAIChatMode.toggle()
                if isAIChatMode { isMediaPanelOpen = false }
            }
        } label: {
            headerIcon("bubble.left.and.text.bubble.right", active: isAIChatMode)
        }
        .buttonStyle(.plain)
        .help(tr("Chat with AI about this meeting", "Чат с ИИ по этой встрече"))
    }

    @ViewBuilder
    private func headerMoreMenu(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        Menu {
            if controller.canResumeFinishedMeeting(meeting),
               !appState.isMeetingRecording,
               !appState.isMeetingStarting,
               !isEditingNotes,
               !isEditingTranscript,
               !isSummarizing,
               !isRetranscribing {
                Button {
                    controller.resumeFinishedMeeting(meetingID: meeting.id)
                } label: {
                    Label(tr("Resume Recording", "Возобновить запись"), systemImage: "record.circle")
                }
            }

            Button {
                runResummarize(for: meeting)
            } label: {
                Label(tr("Re-summarize", "Пересоздать сводку"), systemImage: "sparkles")
            }
            .disabled(isSummarizing || isEditingNotes || isEditingTranscript)

            if meeting.savedRecordingPath != nil, !isRetranscribing {
                Button {
                    startRetranscription(for: meeting)
                } label: {
                    Label(tr("Re-transcribe", "Транскрибировать заново"), systemImage: "arrow.clockwise")
                }
                .disabled(meeting.status == .recording || meeting.status == .processing || isEditingNotes || isEditingTranscript)
            }

            if let savedRecordingPath = meeting.savedRecordingPath {
                Button {
                    controller.revealMeetingRecordingInFinder(path: savedRecordingPath)
                } label: {
                    Label(tr("Show Recording", "Показать запись"), systemImage: "folder")
                }
            }

            Menu {
                Button {
                    MeetingExporter.export(
                        meeting: meeting,
                        content: documentMode == .transcript ? .transcript : .notes
                    )
                } label: {
                    Label(
                        documentMode == .transcript ? tr("Export Transcript", "Экспорт транскрипта") : tr("Export Notes", "Экспорт заметок"),
                        systemImage: documentMode == .transcript ? "text.quote" : "doc.text"
                    )
                }
                Button {
                    MeetingExporter.export(meeting: meeting, content: .fullMeeting)
                } label: {
                    Label(tr("Export Full Meeting", "Экспорт всей встречи"), systemImage: "doc.on.doc")
                }
            } label: {
                Label(tr("Export", "Экспорт"), systemImage: "square.and.arrow.up")
            }
            .disabled(isEditingNotes || isEditingTranscript)

            if controller.canDeleteMeeting(meeting) {
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(tr("Delete Meeting", "Удалить встречу"), systemImage: "trash")
                }
            }
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

    @ViewBuilder
    private func contentTabsCard(_ meeting: MeetingRecord) -> some View {
        HStack(alignment: .center, spacing: MuesliTheme.spacing16) {
            if showsManualNotesEditor(for: meeting) {
                contentTab(tr("Notes", "Заметки"), isSelected: recordingMode == .notes) {
                    recordingMode = .notes
                }
                contentTab(tr("Live", "Онлайн"), isSelected: recordingMode == .live) {
                    recordingMode = .live
                }
            } else {
                contentTab(tr("Summary", "Сводка"), isSelected: documentMode == .notes) {
                    documentMode = .notes
                }
                .disabled(isEditingNotes || isEditingTranscript)
                contentTab(tr("Transcript", "Транскрипт"), isSelected: documentMode == .transcript) {
                    documentMode = .transcript
                }
                .disabled(isEditingNotes || isEditingTranscript)
            }

            Spacer(minLength: 0)

            if isSummarizing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(tr("Summarizing...", "Создание сводки..."))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .padding(.bottom, 8)
            } else if isRetranscribing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(tr("Re-transcribing...", "Повторная транскрипция..."))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .frame(height: 40)
        .background(Capsule().fill(MuesliTheme.backgroundBase))
        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    private func contentTab(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Text is vertically centered in the row; the underline hugs the
            // bottom edge regardless of the row height.
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
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

    private func performEditToggle(for meeting: MeetingRecord) {
        if isEditingNotes {
            notesSaveTask?.cancel()
            notesSaveTask = nil
            controller.updateMeetingNotes(id: meeting.id, notes: editableNotes)
            isEditingNotes = false
        } else if isEditingTranscript {
            guard !isRetranscribing else { return }
            transcriptSaveTask?.cancel()
            transcriptSaveTask = nil
            let shouldPromptForResummary = Self.shouldPromptForTranscriptResummary(
                hadStructuredNotes: transcriptEditHadStructuredNotes,
                originalTranscript: transcriptEditOriginalTranscript,
                editedTranscript: editableTranscript
            )
            controller.updateMeetingTranscript(id: meeting.id, transcript: editableTranscript)
            isEditingTranscript = false
            transcriptEditOriginalTranscript = nil
            transcriptEditHadStructuredNotes = false
            if shouldPromptForResummary {
                transcriptResummaryPromptMeetingID = meeting.id
            }
        } else if documentMode == .transcript {
            editableTranscript = meeting.rawTranscript
            transcriptEditOriginalTranscript = meeting.rawTranscript
            transcriptEditHadStructuredNotes = meeting.notesState == .structuredNotes
            isEditingTranscript = true
        } else {
            documentMode = .notes
            editableNotes = Self.notesContent(for: meeting)
            isEditingNotes = true
        }
    }

    private func summaryCompletion(for meeting: MeetingRecord) -> (Result<Void, Error>) -> Void {
        { [meeting] result in
            isSummarizing = false
            switch result {
            case .success:
                if let updated = controller.meeting(id: meeting.id) {
                    syncLocalState(with: updated)
                }
            case .failure(let error):
                syncPendingTemplateSelectionIfNeeded(
                    for: controller.meeting(id: meeting.id) ?? meeting
                )
                summaryErrorMessage = error.localizedDescription
            }
        }
    }

    private func runResummarize(for meeting: MeetingRecord) {
        isSummarizing = true
        controller.resummarize(meeting: meeting, completion: summaryCompletion(for: meeting))
    }

    /// Switching tabs restores an already generated summary from the store;
    /// only a template that was never generated for this meeting calls the LLM.
    private func switchToTemplate(id: String, for meeting: MeetingRecord) {
        let cached = meeting.templateSummaries[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached, !cached.isEmpty {
            pendingTemplateID = id
            controller.applyStoredMeetingSummary(
                meetingID: meeting.id,
                templateID: id,
                notes: meeting.templateSummaries[id] ?? ""
            )
        } else {
            selectAndApplyTemplate(id: id, for: meeting)
        }
    }

    /// Generates the summary for the given template — used for first-time
    /// generation and for the explicit regenerate chip.
    private func selectAndApplyTemplate(id: String, for meeting: MeetingRecord) {
        pendingTemplateID = id
        isSummarizing = true
        controller.applyMeetingTemplate(id: id, to: meeting, completion: summaryCompletion(for: meeting))
    }

    /// Full-page state shown while a summary is being generated.
    private func summaryGenerationPlaceholder(for meeting: MeetingRecord) -> some View {
        VStack(spacing: MuesliTheme.spacing12) {
            ProgressView()
            Text(tr("Generating summary...", "Создание сводки..."))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text(resolvedPendingTemplateDefinition(for: meeting).title)
                .font(.system(size: 11))
                .foregroundStyle(MuesliTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatMetaShort(_ meeting: MeetingRecord) -> String {
        let time = MeetingBrowserLogic.formatStartTime(meeting.startTime)
        let duration = formatDuration(meeting.durationSeconds)
        return "\(time)  \u{2022}  \(duration)"
    }

    @ViewBuilder
    private func content(for meeting: MeetingRecord) -> some View {
        if showsManualNotesEditor(for: meeting) {
            if meeting.status == .recording {
                let isManualNotesEditable = canEditManualNotes(for: meeting)
                let persistedNotes = Self.notesContent(for: meeting)
                let hasPersistedNotes = !meeting.formattedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ZStack {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        if hasPersistedNotes {
                            MeetingNotesView(markdown: persistedNotes)
                                .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                                .background(MuesliTheme.backgroundBase)
                                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                            manualNotesToolbar(for: meeting)
                                .disabled(!isManualNotesEditable)
                            MarkdownRichTextEditor(
                                text: $editableManualNotes,
                                command: $manualEditorCommand,
                                shouldFocus: isManualNotesEditable,
                                isEditable: isManualNotesEditable,
                                onTextChange: { notes in
                                    guard isManualNotesEditable else { return }
                                    saveManualNotes(meetingID: meeting.id, notes: notes)
                                }
                            )
                            .background(MuesliTheme.backgroundBase)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                            .overlay(
                                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                            )
                            .frame(maxHeight: hasPersistedNotes ? 260 : .infinity)
                        }
                        .frame(maxWidth: 980, maxHeight: hasPersistedNotes ? nil : .infinity, alignment: .topLeading)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(recordingMode == .notes ? 1 : 0)
                    .allowsHitTesting(recordingMode == .notes)
                    .accessibilityHidden(recordingMode != .notes)

                    LiveTranscriptSection(appState: appState, transcriptPrefix: meeting.rawTranscript)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(recordingMode == .live ? 1 : 0)
                        .allowsHitTesting(recordingMode == .live)
                        .accessibilityHidden(recordingMode != .live)

                }
            } else {
                let isManualNotesEditable = canEditManualNotes(for: meeting)
                VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                    manualNotesToolbar(for: meeting)
                        .disabled(!isManualNotesEditable)

                    MarkdownRichTextEditor(
                        text: $editableManualNotes,
                        command: $manualEditorCommand,
                        shouldFocus: false,
                        isEditable: isManualNotesEditable,
                        onTextChange: { notes in
                            guard isManualNotesEditable else { return }
                            saveManualNotes(meetingID: meeting.id, notes: notes)
                        }
                    )
                    .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                    .background(MuesliTheme.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 40)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        } else {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                ZStack(alignment: .topLeading) {
                    if isSummarizing {
                        summaryGenerationPlaceholder(for: meeting)
                            .opacity(documentMode == .notes ? 1 : 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(documentMode != .notes)
                    } else {
                        MeetingNotesView(markdown: Self.notesContent(for: meeting))
                            .opacity(documentMode == .notes ? 1 : 0)
                            .allowsHitTesting(documentMode == .notes)
                            .accessibilityHidden(documentMode != .notes)
                    }

                    MeetingTranscriptView(transcript: meeting.rawTranscript)
                        .opacity(documentMode == .transcript ? 1 : 0)
                        .allowsHitTesting(documentMode == .transcript)
                        .accessibilityHidden(documentMode != .transcript)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: 1080, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var documentModePicker: some View {
        Picker("", selection: $documentMode) {
            Text(tr("Notes", "Заметки")).tag(MeetingDocumentMode.notes)
            Text(tr("Transcript", "Транскрипт")).tag(MeetingDocumentMode.transcript)
        }
        .pickerStyle(.segmented)
        .tint(MuesliTheme.accent)
        .frame(width: 220)
        .disabled(isEditingNotes || isEditingTranscript)
    }

    private var recordingModePicker: some View {
        Picker("", selection: $recordingMode) {
            Text(tr("Notes", "Заметки")).tag(RecordingContentMode.notes)
            Text(tr("Live", "Онлайн")).tag(RecordingContentMode.live)
        }
        .pickerStyle(.segmented)
        .tint(MuesliTheme.accent)
        .frame(width: 180)
    }

    private func showsManualNotesEditor(for meeting: MeetingRecord) -> Bool {
        switch meeting.status {
        case .recording, .processing, .noteOnly, .failed:
            return true
        case .completed:
            return false
        }
    }

    private func canEditManualNotes(for meeting: MeetingRecord) -> Bool {
        meeting.status == .recording || meeting.status == .noteOnly || meeting.status == .failed
    }

    private func isPreparingThisMeeting(_ meeting: MeetingRecord) -> Bool {
        meeting.status == .recording
            && appState.isMeetingStarting
            && !appState.isMeetingRecording
    }

    @ViewBuilder
    private func headerActions(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MuesliTheme.spacing8) {
                resumeChooserIfAvailable(for: meeting)
                templateMenu(for: meeting, appliedTemplate: appliedTemplate)
                exportMenu(for: meeting)
                summaryAction(for: meeting)
                editButton(for: meeting)
                moreActionsMenu(for: meeting)
            }

            VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                HStack(spacing: MuesliTheme.spacing8) {
                    resumeChooserIfAvailable(for: meeting)
                    templateMenu(for: meeting, appliedTemplate: appliedTemplate)
                    exportMenu(for: meeting)
                    summaryAction(for: meeting)
                }
                HStack(spacing: MuesliTheme.spacing8) {
                    editButton(for: meeting)
                    moreActionsMenu(for: meeting)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryAction(for meeting: MeetingRecord) -> some View {
        if isSummarizing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(tr("Summarizing...", "Создание сводки..."))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .padding(.horizontal, MuesliTheme.spacing8)
        } else {
            iconButton("sparkles", label: primarySummaryActionLabel(for: meeting)) {
                isSummarizing = true
                let completion: (Result<Void, Error>) -> Void = { [meeting] result in
                    isSummarizing = false
                    switch result {
                    case .success:
                        if let updated = controller.meeting(id: meeting.id) {
                            syncLocalState(with: updated)
                        }
                    case .failure(let error):
                        syncPendingTemplateSelectionIfNeeded(
                            for: controller.meeting(id: meeting.id) ?? meeting
                        )
                        summaryErrorMessage = error.localizedDescription
                    }
                }
                if hasPendingTemplateChange(for: meeting) {
                    controller.applyMeetingTemplate(id: pendingTemplateID, to: meeting, completion: completion)
                } else {
                    controller.resummarize(meeting: meeting, completion: completion)
                }
            }
        }
    }

    @ViewBuilder
    private func editButton(for meeting: MeetingRecord) -> some View {
        iconButton(
            isEditingNotes || isEditingTranscript ? "checkmark.circle" : "pencil",
            label: editButtonLabel
        ) {
            if isEditingNotes {
                notesSaveTask?.cancel()
                notesSaveTask = nil
                controller.updateMeetingNotes(id: meeting.id, notes: editableNotes)
                isEditingNotes = false
            } else if isEditingTranscript {
                guard !isRetranscribing else { return }
                transcriptSaveTask?.cancel()
                transcriptSaveTask = nil
                let shouldPromptForResummary = Self.shouldPromptForTranscriptResummary(
                    hadStructuredNotes: transcriptEditHadStructuredNotes,
                    originalTranscript: transcriptEditOriginalTranscript,
                    editedTranscript: editableTranscript
                )
                controller.updateMeetingTranscript(id: meeting.id, transcript: editableTranscript)
                isEditingTranscript = false
                transcriptEditOriginalTranscript = nil
                transcriptEditHadStructuredNotes = false
                if shouldPromptForResummary {
                    transcriptResummaryPromptMeetingID = meeting.id
                }
            } else if documentMode == .transcript {
                editableTranscript = meeting.rawTranscript
                transcriptEditOriginalTranscript = meeting.rawTranscript
                transcriptEditHadStructuredNotes = meeting.notesState == .structuredNotes
                isEditingTranscript = true
            } else {
                documentMode = .notes
                editableNotes = Self.notesContent(for: meeting)
                isEditingNotes = true
            }
        }
        .disabled(isRetranscribing && !isEditingNotes && !isEditingTranscript)
    }

    @ViewBuilder
    private func retranscribeAction(for meeting: MeetingRecord) -> some View {
        if meeting.savedRecordingPath != nil {
            if isRetranscribing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(tr("Re-transcribing...", "Повторная транскрипция..."))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .padding(.horizontal, MuesliTheme.spacing8)
            } else {
                iconButton("arrow.clockwise", label: tr("Re-transcribe", "Транскрибировать заново")) {
                    startRetranscription(for: meeting)
                }
                .disabled(meeting.status == .recording || meeting.status == .processing || isEditingNotes || isEditingTranscript)
            }
        }
    }

    private func startRetranscription(for meeting: MeetingRecord) {
        isRetranscribing = true
        controller.retranscribe(meeting: meeting) { [meeting] result in
            isRetranscribing = false
            switch result {
            case .success:
                if let updated = controller.meeting(id: meeting.id) {
                    syncLocalState(with: updated)
                }
            case .failure(let error):
                retranscriptionErrorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func templateMenu(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        Menu {
            Button {
                pendingTemplateID = MeetingTemplates.autoID
            } label: {
                templateMenuItem(
                    title: MeetingTemplates.auto.title,
                    systemImage: MeetingTemplates.auto.icon,
                    isSelected: pendingTemplateID == MeetingTemplates.autoID
                )
            }

            Section(tr("Built-in Templates", "Встроенные шаблоны")) {
                ForEach(controller.builtInMeetingTemplates()) { template in
                    Button {
                        pendingTemplateID = template.id
                    } label: {
                        templateMenuItem(
                            title: template.title,
                            systemImage: template.icon,
                            isSelected: pendingTemplateID == template.id
                        )
                    }
                }
            }

            if !controller.customOnlyMeetingTemplates().isEmpty {
                Section(tr("Custom Templates", "Пользовательские шаблоны")) {
                    ForEach(controller.customOnlyMeetingTemplates()) { template in
                        Button {
                            pendingTemplateID = template.id
                        } label: {
                            let resolved = MeetingTemplates.customDefinition(from: template)
                            templateMenuItem(
                                title: template.name,
                                systemImage: resolved.icon,
                                isSelected: pendingTemplateID == template.id
                            )
                        }
                    }
                }
            }

            Divider()

            Button(tr("Manage Templates…", "Управление шаблонами…")) {
                controller.showMeetingTemplatesManager()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName(forSelectionOn: meeting, appliedTemplate: appliedTemplate))
                    .font(.system(size: 10))
                Text(labelForSelection(on: meeting, appliedTemplate: appliedTemplate))
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, 5)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func contentToolbar(for meeting: MeetingRecord) -> some View {
        HStack {
            Spacer()

            retranscribeAction(for: meeting)

            Button(action: {
                controller.copyToClipboard(activeCopyText(for: meeting))
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text(copyButtonLabel)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MuesliTheme.textPrimary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .fill(MuesliTheme.accent.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    @ViewBuilder
    private func manualNotesToolbar(for meeting: MeetingRecord) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            if canEditManualNotes(for: meeting) {
                Text(manualNotesSaveStatus.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }

            Spacer()

            markdownToolbarButton(systemImage: "textformat.size", label: tr("Heading", "Заголовок")) {
                manualEditorCommand = MarkdownEditorCommand(kind: .heading)
            }
            markdownToolbarButton(systemImage: "bold", label: tr("Bold", "Полужирный")) {
                manualEditorCommand = MarkdownEditorCommand(kind: .bold)
            }
            markdownToolbarButton(systemImage: "list.bullet", label: tr("Bullet", "Список")) {
                manualEditorCommand = MarkdownEditorCommand(kind: .bullet)
            }
            markdownToolbarButton(systemImage: "checklist", label: tr("Checkbox", "Флажок")) {
                manualEditorCommand = MarkdownEditorCommand(kind: .checkbox)
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    @ViewBuilder
    private func statusChip(for meeting: MeetingRecord) -> some View {
        let isPreparing = isPreparingThisMeeting(meeting)
        let isPaused = meeting.status == .recording && appState.isMeetingRecordingPaused
        let label = isPreparing ? tr("Preparing", "Подготовка") : isPaused ? tr("Paused", "Пауза") : meeting.status.displayLabel
        let color = isPreparing || isPaused ? MuesliTheme.transcribing : meeting.status.displayColor
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .padding(.horizontal, MuesliTheme.spacing8)
        .padding(.vertical, 6)
        .background(MuesliTheme.surfacePrimary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func recordingControlGroup(for meeting: MeetingRecord) -> some View {
        if meeting.status == .recording {
            if isPreparingThisMeeting(meeting) {
                meetingPreparationControlGroup(for: meeting)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        statusChip(for: meeting)
                        pauseResumeRecordingButton
                        stopRecordingButton
                        discardRecordingButton
                    }
                    .recordingControlsBackground()

                    VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                        statusChip(for: meeting)
                        HStack(spacing: MuesliTheme.spacing8) {
                            pauseResumeRecordingButton
                            stopRecordingButton
                            discardRecordingButton
                        }
                        .recordingControlsBackground()
                    }
                }
            }
        } else if controller.canDeleteMeeting(meeting), meeting.status == .noteOnly || meeting.status == .failed {
            HStack(spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                deleteButton
            }
        } else {
            statusChip(for: meeting)
        }
    }

    /// The resume control only makes sense on a finished meeting when no other
    /// recording/editing workflow is active.
    @ViewBuilder
    private func resumeChooserIfAvailable(for meeting: MeetingRecord) -> some View {
        if controller.canResumeFinishedMeeting(meeting),
           !appState.isMeetingRecording,
           !appState.isMeetingStarting,
           !isEditingNotes,
           !isEditingTranscript,
           !isSummarizing,
           !isRetranscribing {
            resumeRecordingButton(for: meeting)
        }
    }

    @ViewBuilder
    private func meetingPreparationControlGroup(for meeting: MeetingRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                meetingPreparationStatus
                cancelMeetingPreparationButton
            }
            .recordingControlsBackground()

            VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                HStack(spacing: MuesliTheme.spacing8) {
                    meetingPreparationStatus
                    cancelMeetingPreparationButton
                }
                .recordingControlsBackground()
            }
        }
    }

    @ViewBuilder
    private func markdownToolbarButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MuesliTheme.textSecondary)
            .frame(width: 34, height: 30)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    @ViewBuilder
    private func exportMenu(for meeting: MeetingRecord) -> some View {
        let currentContent: MeetingExportContent = documentMode == .transcript ? .transcript : .notes
        let currentLabel = documentMode == .transcript ? tr("Export Transcript", "Экспорт транскрипта") : tr("Export Notes", "Экспорт заметок")
        Menu {
            Button {
                MeetingExporter.export(meeting: meeting, content: currentContent)
            } label: {
                Label(currentLabel, systemImage: documentMode == .transcript ? "text.quote" : "doc.text")
            }
            Button {
                MeetingExporter.export(meeting: meeting, content: .fullMeeting)
            } label: {
                Label(tr("Export Full Meeting", "Экспорт всей встречи"), systemImage: "doc.on.doc")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                Text(tr("Export", "Экспорт"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(MuesliTheme.accent.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isEditingNotes || isEditingTranscript)
    }

    @ViewBuilder
    private func moreActionsMenu(for meeting: MeetingRecord) -> some View {
        if meeting.savedRecordingPath != nil || controller.canDeleteMeeting(meeting) {
            Menu {
                if let savedRecordingPath = meeting.savedRecordingPath {
                    Button {
                        controller.revealMeetingRecordingInFinder(path: savedRecordingPath)
                    } label: {
                        Label(tr("Show Recording", "Показать запись"), systemImage: "folder")
                    }
                }

                if controller.canDeleteMeeting(meeting) {
                    if meeting.savedRecordingPath != nil {
                        Divider()
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label(tr("Delete Meeting", "Удалить встречу"), systemImage: "trash")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(width: 30, height: 28)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(tr("More actions", "Другие действия"))
        }
    }

    private func templateMenuItem(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : systemImage)
                .frame(width: 12)
            Text(title)
        }
    }

    @ViewBuilder
    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, 5)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        iconButton("trash", label: tr("Delete", "Удалить")) {
            showDeleteConfirmation = true
        }
    }

    private var meetingPreparationStatus: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
                .accessibilityLabel(tr("Preparing transcription", "Подготовка транскрипции"))
            Text(appState.meetingStartStatus ?? tr("Meeting transcription will start shortly.", "Транскрипция встречи скоро начнётся."))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 7)
        .background(MuesliTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var cancelMeetingPreparationButton: some View {
        iconButton("xmark", label: tr("Cancel", "Отмена")) {
            controller.cancelMeetingPreparation()
        }
        .help(tr("Cancel meeting preparation", "Отменить подготовку встречи"))
    }

    private var pauseResumeRecordingButton: some View {
        let isPaused = appState.isMeetingRecordingPaused
        return Button {
            controller.toggleMeetingRecordingPause()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(isPaused ? tr("Resume", "Возобновить") : tr("Pause", "Пауза"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isPaused ? MuesliTheme.backgroundBase : MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(isPaused ? MuesliTheme.accent : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(isPaused ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!appState.isMeetingRecording)
        .help(isPaused ? tr("Resume recording", "Возобновить запись") : tr("Pause recording", "Приостановить запись"))
    }

    /// Shown on a finished meeting when no recording is active. Appends the next
    /// recording segment to this existing meeting artifact.
    @ViewBuilder
    private func resumeRecordingButton(for meeting: MeetingRecord) -> some View {
        Button {
            controller.resumeFinishedMeeting(meetingID: meeting.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "record.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(tr("Resume", "Возобновить"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(MuesliTheme.backgroundBase)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(MuesliTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(tr("Resume recording", "Возобновить запись"))
    }

    private var stopRecordingButton: some View {
        Button {
            if let meeting {
                flushTitleSave(meetingID: meeting.id)
            }
            controller.stopMeetingRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(tr("Stop", "Стоп"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(MuesliTheme.recording)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .disabled(!appState.isMeetingRecording)
        .help(tr("Stop recording", "Остановить запись"))
    }

    private var discardRecordingButton: some View {
        iconButton("xmark", label: tr("Discard", "Сбросить")) {
            controller.discardMeetingWithConfirmation()
        }
    }

    @ViewBuilder
    private func templateChip(for snapshot: MeetingTemplateSnapshot) -> some View {
        HStack(spacing: 5) {
            Image(systemName: iconName(for: snapshot))
                .font(.system(size: 10))
            Text(snapshot.name)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(MuesliTheme.accent)
        .padding(.horizontal, MuesliTheme.spacing8)
        .padding(.vertical, 4)
        .background(MuesliTheme.accentSubtle)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func folderPill(for meeting: MeetingRecord) -> some View {
        let currentFolder = meeting.folderID.flatMap { fid in
            appState.folders.first(where: { $0.id == fid })
        }
        let hasFolder = currentFolder != nil
        Button {
            showFolderPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: hasFolder ? "folder.fill" : "folder.badge.plus")
                    .font(.system(size: 10))
                Text(currentFolder?.name ?? tr("Add to folder", "Добавить в папку"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hasFolder ? MuesliTheme.accent : MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, 4)
            .background(hasFolder ? MuesliTheme.accentSubtle : MuesliTheme.backgroundRaised)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(hasFolder ? Color.clear : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(hasFolder ? tr("Change folder", "Изменить папку") : tr("Add to folder", "Добавить в папку"))
        .popover(isPresented: $showFolderPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if !appState.folders.isEmpty {
                    ForEach(appState.folders) { folder in
                        let isActive = meeting.folderID == folder.id
                        folderPopoverRow(icon: "folder", label: folder.name, isActive: isActive) {
                            controller.moveMeeting(id: meeting.id, toFolder: isActive ? nil : folder.id)
                            showFolderPopover = false
                        }
                    }
                    Divider().padding(.vertical, 4)
                }
                folderPopoverRow(icon: "folder.badge.plus", label: tr("New Folder...", "Новая папка...")) {
                    showFolderPopover = false
                    newFolderName = ""
                    showNewFolderPrompt = true
                }
            }
            .padding(8)
            .frame(minWidth: 200)
        }
        .alert(tr("New Folder", "Новая папка"), isPresented: $showNewFolderPrompt) {
            TextField(tr("Folder name", "Имя папки"), text: $newFolderName)
            Button(tr("Create", "Создать")) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                controller.createFolderAndMoveMeeting(name: trimmed, meetingID: meeting.id)
            }
            Button(tr("Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Create a new folder and move this meeting into it.", "Создать новую папку и переместить в неё эту встречу."))
        }
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

    private var transcriptCTA: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            if hasApiKey {
                Image(systemName: "sparkles")
                    .foregroundStyle(MuesliTheme.accent)
                Text(tr("Use \(primarySummaryActionLabel) to turn this raw transcript into AI meeting notes and a cleaned-up title.", "Нажмите «\(primarySummaryActionLabel)», чтобы превратить необработанный транскрипт в заметки встречи и аккуратный заголовок."))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            } else {
                Image(systemName: "key.fill")
                    .foregroundStyle(MuesliTheme.accent)
                Text(tr("Add your API key in Settings to generate meeting notes", "Добавьте API-ключ в настройках, чтобы создавать заметки встреч"))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                Spacer()
                Button(tr("Open Settings", "Открыть настройки")) {
                    controller.openHistoryWindow(tab: .settings)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
    }

    @ViewBuilder
    private func activeMeetingAudioWarningBanner(for meeting: MeetingRecord) -> some View {
        if meeting.status == .recording,
           let warning = appState.activeMeetingAudioWarning,
           warning.meetingID == meeting.id {
            HStack(alignment: .top, spacing: MuesliTheme.spacing8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text(warning.message)
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Spacer(minLength: MuesliTheme.spacing8)
            }
            .padding(MuesliTheme.spacing12)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var hasApiKey: Bool {
        let config = appState.config
        if appState.selectedMeetingSummaryBackend == .chatGPT {
            return appState.isChatGPTAuthenticated
        } else if appState.selectedMeetingSummaryBackend == .openAI {
            return !config.openAIAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
        } else if appState.selectedMeetingSummaryBackend == .ollama {
            return true
        } else if appState.selectedMeetingSummaryBackend == .lmStudio {
            return MeetingSummaryClient.lmStudioHasRequiredSettings(config: config)
        } else if appState.selectedMeetingSummaryBackend == .customLLM {
            return MeetingSummaryClient.customLLMHasRequiredSettings(config: config)
        } else {
            return !config.openRouterAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] != nil
        }
    }

    private var primarySummaryActionLabel: String {
        guard let meeting else { return tr("Re-summarize", "Пересоздать сводку") }
        return primarySummaryActionLabel(for: meeting)
    }

    private var copyButtonLabel: String {
        tr("Copy", "Копировать")
    }

    private var editButtonLabel: String {
        if isEditingNotes || isEditingTranscript {
            return tr("Done", "Готово")
        }
        return documentMode == .transcript ? tr("Edit Transcript", "Редактировать транскрипт") : tr("Edit Notes", "Редактировать заметки")
    }

    private func primarySummaryActionLabel(for meeting: MeetingRecord) -> String {
        hasPendingTemplateChange(for: meeting) ? tr("Apply Template", "Применить шаблон") : tr("Re-summarize", "Пересоздать сводку")
    }

    private func activeCopyText(for meeting: MeetingRecord) -> String {
        switch documentMode {
        case .notes:
            return isEditingNotes ? editableNotes : Self.notesContent(for: meeting)
        case .transcript:
            return isEditingTranscript ? editableTranscript : meeting.rawTranscript
        }
    }

    private func isRawTranscript(_ meeting: MeetingRecord) -> Bool {
        meeting.notesState != .structuredNotes
    }

    private func hasPendingTemplateChange(for meeting: MeetingRecord) -> Bool {
        resolvedPendingTemplateDefinition(for: meeting).id != controller.meetingTemplateSnapshot(for: meeting).id
    }

    private func labelForSelection(on meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> String {
        if pendingTemplateID == appliedTemplate.id {
            return appliedTemplate.name
        }
        return resolvedPendingTemplateDefinition(for: meeting).title
    }

    private func iconName(forSelectionOn meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> String {
        if pendingTemplateID == appliedTemplate.id {
            return iconName(for: appliedTemplate)
        }
        return resolvedPendingTemplateDefinition(for: meeting).icon
    }

    private func iconName(for snapshot: MeetingTemplateSnapshot) -> String {
        switch snapshot.kind {
        case .auto:
            return MeetingTemplates.auto.icon
        case .builtin, .custom:
            return MeetingTemplates.resolveDefinition(
                id: snapshot.id,
                customTemplates: appState.config.customMeetingTemplates
            ).icon
        }
    }

    static func notesContent(for meeting: MeetingRecord) -> String {
        if meeting.status == .noteOnly {
            return meeting.manualNotes
        }
        if meeting.notesState != .structuredNotes {
            return "# \(meeting.title)\n\n## Raw Transcript\n\n\(meeting.rawTranscript)"
        }
        return meeting.formattedNotes
    }

    private static func defaultDocumentMode(for meeting: MeetingRecord) -> MeetingDocumentMode {
        if meeting.status == .noteOnly || meeting.status == .recording || meeting.status == .processing || meeting.status == .failed {
            return .notes
        }
        return meeting.notesState == .structuredNotes
            ? MeetingDocumentMode.notes
            : MeetingDocumentMode.transcript
    }

    private func debounceSaveTitle(meetingID: Int64) {
        titleSaveTask?.cancel()
        let title = editableTitle
        let c = controller
        c.cacheMeetingTitle(id: meetingID, title: title)
        let item = DispatchWorkItem { c.updateMeetingTitle(id: meetingID, title: title) }
        titleSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func flushTitleSave(meetingID: Int64) {
        titleSaveTask?.cancel()
        titleSaveTask = nil
        controller.updateMeetingTitle(id: meetingID, title: editableTitle)
    }

    private func debounceSaveNotes(meetingID: Int64) {
        notesSaveTask?.cancel()
        let notes = editableNotes
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingNotes(id: meetingID, notes: notes) }
        notesSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func debounceSaveTranscript(meetingID: Int64) {
        transcriptSaveTask?.cancel()
        let transcript = editableTranscript
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingTranscript(id: meetingID, transcript: transcript) }
        transcriptSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func saveManualNotes(meetingID: Int64, notes: String) {
        manualNotesSaveStatus = .saving
        controller.cacheMeetingManualNotes(id: meetingID, notes: notes)
        scheduleManualNotesSaveStatusCheck(meetingID: meetingID, notes: notes)
    }

    private func scheduleManualNotesSaveStatusCheck(meetingID: Int64, notes: String) {
        manualNotesSaveStatusTask?.cancel()
        let item = DispatchWorkItem {
            guard loadedMeetingID == meetingID else { return }
            guard editableManualNotes == notes else { return }
            if controller.hasPersistedMeetingManualNotes(id: meetingID, notes: notes) {
                manualNotesSaveStatus = .saved
            }
        }
        manualNotesSaveStatusTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }

    private var summaryErrorBinding: Binding<Bool> {
        Binding(
            get: { summaryErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    summaryErrorMessage = nil
                }
            }
        )
    }

    private var retranscriptionErrorBinding: Binding<Bool> {
        Binding(
            get: { retranscriptionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    retranscriptionErrorMessage = nil
                }
            }
        )
    }

    private var transcriptResummaryPromptBinding: Binding<Bool> {
        Binding(
            get: { transcriptResummaryPromptMeetingID != nil },
            set: { isPresented in
                if !isPresented {
                    transcriptResummaryPromptMeetingID = nil
                }
            }
        )
    }

    private static func shouldPromptForTranscriptResummary(
        hadStructuredNotes: Bool,
        originalTranscript: String?,
        editedTranscript: String
    ) -> Bool {
        guard hadStructuredNotes, let originalTranscript else { return false }
        return originalTranscript != editedTranscript
    }

    private func resummarizeAfterTranscriptEdit() {
        guard let meetingID = transcriptResummaryPromptMeetingID else { return }
        transcriptResummaryPromptMeetingID = nil
        guard let updatedMeeting = controller.meeting(id: meetingID) else { return }
        isSummarizing = true
        controller.resummarize(meeting: updatedMeeting) { [meetingID] result in
            isSummarizing = false
            switch result {
            case .success:
                if let refreshed = controller.meeting(id: meetingID) {
                    syncLocalState(with: refreshed)
                }
            case .failure(let error):
                summaryErrorMessage = error.localizedDescription
            }
        }
    }

    private func resolvedPendingTemplateDefinition(for meeting: MeetingRecord) -> MeetingTemplateDefinition {
        if let resolved = MeetingTemplates.resolveExactDefinition(
            id: pendingTemplateID,
            customTemplates: appState.config.customMeetingTemplates
        ) {
            return resolved
        }
        return MeetingTemplates.resolveDefinition(
            id: controller.meetingTemplateSnapshot(for: meeting).id,
            customTemplates: appState.config.customMeetingTemplates
        )
    }

    private func syncPendingTemplateSelectionIfNeeded(for meeting: MeetingRecord?) {
        guard let meeting else { return }
        guard MeetingTemplates.resolveExactDefinition(
            id: pendingTemplateID,
            customTemplates: appState.config.customMeetingTemplates
        ) == nil else {
            return
        }
        pendingTemplateID = controller.meetingTemplateSnapshot(for: meeting).id
    }

    private func syncLocalState(with meeting: MeetingRecord?) {
        let previousMeetingID = loadedMeetingID
        let meetingChanged = previousMeetingID != meeting?.id
        loadedMeetingID = meeting?.id
        editableTitle = meeting?.title ?? ""
        if meetingChanged || !isEditingNotes {
            editableNotes = meeting.map { Self.notesContent(for: $0) } ?? ""
        }
        if meetingChanged || !isEditingTranscript {
            editableTranscript = meeting?.rawTranscript ?? ""
        }
        if meetingChanged {
            editableManualNotes = meeting?.manualNotes ?? ""
            manualNotesSaveStatus = .saved
            transcriptResummaryPromptMeetingID = nil
            transcriptEditOriginalTranscript = nil
            transcriptEditHadStructuredNotes = false
        } else {
            syncManualNotesState(with: meeting)
        }
        pendingTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        if meetingChanged {
            documentMode = meeting.map(Self.defaultDocumentMode(for:)) ?? .notes
            isEditingNotes = false
            isEditingTranscript = false
            showFolderPopover = false
            showNewFolderPrompt = false
            newFolderName = ""
            isMediaPanelOpen = false
        }
    }

    private func syncManualNotesState(with meeting: MeetingRecord?) {
        let persistedManualNotes = meeting?.manualNotes ?? ""
        if manualNotesSaveStatus == .saving, editableManualNotes != persistedManualNotes {
            return
        }
        editableManualNotes = persistedManualNotes
        manualNotesSaveStatus = .saved
    }

    private func formatMeta(_ meeting: MeetingRecord) -> String {
        let time = MeetingBrowserLogic.formatStartTime(meeting.startTime)
        let duration = formatDuration(meeting.durationSeconds)
        return tr("\(time)  \u{2022}  \(duration)  \u{2022}  \(meeting.wordCount) words", "\(time)  \u{2022}  \(duration)  \u{2022}  слов: \(meeting.wordCount)")
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
}

private extension View {
    func recordingControlsBackground() -> some View {
        padding(5)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
    }
}

private struct MarqueeTitleTextField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onTextChange: () -> Void
    var titleFont: Font = Font.system(size: 30, weight: .bold)
    var minHeight: CGFloat = 38

    @State private var isHovering = false
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var marqueeOffset: CGFloat = 0
    @State private var marqueeRunID = UUID()
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        // The scrolling marquee Text lives in an overlay: overlays don't
        // participate in layout, so its fixedSize width can't inflate the
        // minimum width of the whole detail page.
        TextField(tr("Meeting Title", "Название встречи"), text: $text)
            .font(titleFont)
            .foregroundStyle(MuesliTheme.textPrimary)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .opacity(shouldShowMarquee ? 0 : 1)
            .focused($isTitleFocused)
            .onSubmit(onSubmit)
            .onChange(of: text) { _, _ in
                onTextChange()
                restartMarqueeIfNeeded()
            }
            .onChange(of: isTitleFocused) { _, _ in
                restartMarqueeIfNeeded()
            }
        .overlay(alignment: .leading) {
            Text(text.isEmpty ? tr("Meeting Title", "Название встречи") : text)
                .font(titleFont)
                .fontWeight(.bold)
                .foregroundStyle(MuesliTheme.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: marqueeOffset)
                .opacity(shouldShowMarquee ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TitleContainerWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .overlay(
            Text(text.isEmpty ? tr("Meeting Title", "Название встречи") : text)
                .font(titleFont)
                .fontWeight(.bold)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TitleContentWidthPreferenceKey.self, value: proxy.size.width)
                    }
                )
                .allowsHitTesting(false)
        )
        .onTapGesture {
            isTitleFocused = true
        }
        .onPreferenceChange(TitleContainerWidthPreferenceKey.self) { width in
            guard abs(containerWidth - width) > 0.5 else { return }
            containerWidth = width
            restartMarqueeIfNeeded()
        }
        .onPreferenceChange(TitleContentWidthPreferenceKey.self) { width in
            guard abs(contentWidth - width) > 0.5 else { return }
            contentWidth = width
            restartMarqueeIfNeeded()
        }
        .onHover { hovering in
            isHovering = hovering
            restartMarqueeIfNeeded()
        }
    }

    private var overflowDistance: CGFloat {
        max(contentWidth - containerWidth, 0)
    }

    private var shouldShowMarquee: Bool {
        containerWidth > 0 && isHovering && !isTitleFocused && overflowDistance > 24
    }

    private func restartMarqueeIfNeeded() {
        guard shouldShowMarquee else {
            if marqueeOffset != 0 {
                let runID = UUID()
                marqueeRunID = runID
                withAnimation(.easeOut(duration: 0.18)) {
                    marqueeOffset = 0
                }
            }
            return
        }

        let runID = UUID()
        marqueeRunID = runID

        marqueeOffset = 0
        let distance = overflowDistance + 28
        let duration = min(max(Double(distance) / 42.0, 3.0), 12.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard marqueeRunID == runID, shouldShowMarquee else { return }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                marqueeOffset = -distance
            }
        }
    }
}

private struct TitleContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TitleContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TranscriptChatMessage: Identifiable, Equatable {
    let id: Int
    let timestamp: String?
    let speaker: String?
    let text: String

    var isUser: Bool {
        speaker?.localizedCaseInsensitiveCompare("You") == .orderedSame
    }

    static func messages(from transcript: String) -> [TranscriptChatMessage] {
        let normalized = transcript.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var messages: [TranscriptChatMessage] = []
        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parsed = parseLine(line, id: messages.count)
            messages.append(parsed)
        }

        return messages
    }

    private static func parseLine(_ line: String, id: Int) -> TranscriptChatMessage {
        if line.hasPrefix("["),
           let timestampEnd = line.firstIndex(of: "]") {
            let timestamp = String(line[line.index(after: line.startIndex)..<timestampEnd])
            let remainderStart = line.index(after: timestampEnd)
            let remainder = line[remainderStart...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let speakerText = splitSpeakerAndText(remainder)
            return TranscriptChatMessage(
                id: id,
                timestamp: timestamp.isEmpty ? nil : timestamp,
                speaker: speakerText.speaker,
                text: speakerText.text
            )
        }

        let speakerText = splitSpeakerAndText(line)
        return TranscriptChatMessage(
            id: id,
            timestamp: nil,
            speaker: speakerText.speaker,
            text: speakerText.text
        )
    }

    private static func splitSpeakerAndText(_ text: String) -> (speaker: String?, text: String) {
        guard let separator = text.firstIndex(of: ":") else {
            return (nil, text)
        }

        let candidate = text[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelySpeakerLabel(candidate) else {
            return (nil, text)
        }

        let bodyStart = text.index(after: separator)
        let body = text[bodyStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (candidate, body.isEmpty ? text : body)
    }

    private static func isLikelySpeakerLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 32 else { return false }
        if label.localizedCaseInsensitiveCompare("You") == .orderedSame { return true }
        if label.localizedCaseInsensitiveCompare("Others") == .orderedSame { return true }
        if label.range(of: #"^Speaker\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }
}

private struct MeetingTranscriptView: View {
    let transcript: String
    @State private var messages: [TranscriptChatMessage]

    init(transcript: String) {
        self.transcript = transcript
        _messages = State(initialValue: TranscriptChatMessage.messages(from: transcript))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                if messages.isEmpty {
                    Text(tr("No transcript available", "Транскрипт недоступен"))
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(maxWidth: 860, alignment: .leading)
                        .padding(MuesliTheme.spacing24)
                } else {
                    ForEach(messages) { message in
                        TranscriptChatBubble(message: message)
                    }
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.vertical, MuesliTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onChange(of: transcript) { _, newTranscript in
            messages = TranscriptChatMessage.messages(from: newTranscript)
        }
    }
}

struct TranscriptChatBubble: View {
    let message: TranscriptChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: MuesliTheme.spacing8) {
            if message.isUser {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let metadata = metadata {
                    Text(metadata)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .textSelection(.enabled)
                }
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 8)
            .background(message.isUser ? MuesliTheme.accent.opacity(0.18) : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(message.isUser ? MuesliTheme.accent.opacity(0.25) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(maxWidth: 680, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser {
                Spacer(minLength: 80)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    private var metadata: String? {
        switch (message.speaker, message.timestamp) {
        case let (speaker?, timestamp?):
            return "\(speaker) \(timestamp)"
        case let (speaker?, nil):
            return speaker
        case let (nil, timestamp?):
            return timestamp
        case (nil, nil):
            return nil
        }
    }
}

private struct TranscriptSearchPopover: View {
    let transcript: String
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matches: [String] {
        guard trimmedQuery.count >= 2 else { return [] }
        return transcript
            .components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }
            .prefix(30)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(MuesliTheme.textTertiary)
                TextField(tr("Search transcript...", "Поиск по транскрипту..."), text: $query)
                    .font(MuesliTheme.callout())
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder.opacity(0.7), lineWidth: 1)
            )

            if trimmedQuery.count >= 2 {
                Text(tr("Matches: \(matches.count)", "Совпадений: \(matches.count)"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)

                if !matches.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                            ForEach(Array(matches.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(MuesliTheme.caption())
                                    .foregroundStyle(MuesliTheme.textSecondary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(MuesliTheme.spacing8)
                                    .background(MuesliTheme.backgroundRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                            }
                        }
                    }
                    // Popovers size views to their IDEAL height, and a
                    // ScrollView's ideal height is tiny — pin it explicitly.
                    .frame(height: 380)
                }
            } else {
                Text(tr("Type at least 2 characters to search the transcript.", "Введите минимум 2 символа для поиска по транскрипту."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        }
        .padding(MuesliTheme.spacing12)
        .frame(width: 340)
    }
}

/// Placeholder page for the upcoming "chat with AI about this meeting" feature.
/// Pure mock — no backend wiring yet. Shown inline instead of the notes content.
/// Compact markdown renderer for AI chat bubbles: headings, bullet and
/// numbered lists, and inline **bold** / *italic* / `code` — the same visual
/// language as the meeting summary, sized for a chat bubble.
struct ChatMarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            let lines = markdown.components(separatedBy: .newlines)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, raw in
                line(raw)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func inline(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }

    @ViewBuilder
    private func line(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Color.clear.frame(height: 4)
        } else if trimmed.hasPrefix("### ") {
            Text(Self.inline(String(trimmed.dropFirst(4))))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
        } else if trimmed.hasPrefix("## ") {
            Text(Self.inline(String(trimmed.dropFirst(3))))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
        } else if trimmed.hasPrefix("# ") {
            Text(Self.inline(String(trimmed.dropFirst(2))))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MuesliTheme.textPrimary)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            bulletRow(marker: "•", text: String(trimmed.dropFirst(2)))
        } else if let numbered = Self.numbered(trimmed) {
            bulletRow(marker: numbered.marker, text: numbered.text)
        } else {
            Text(Self.inline(trimmed))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineSpacing(2)
        }
    }

    private func bulletRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(Self.inline(text))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func numbered(_ line: String) -> (marker: String, text: String)? {
        guard let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else { return nil }
        let marker = line[..<line.index(before: range.upperBound)].trimmingCharacters(in: .whitespaces)
        let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !marker.isEmpty, !text.isEmpty else { return nil }
        return (marker, text)
    }
}

private struct MeetingAIChatPage: View {
    let meeting: MeetingRecord
    let controller: MuesliController
    let appState: AppState

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    // The conversation lives in AppState so it survives switching tabs,
    // meetings, and closing/reopening the chat page during the session.
    private var turns: [MeetingChatMessage] {
        appState.meetingChatHistories[meeting.id] ?? []
    }

    private var isAwaiting: Bool {
        appState.meetingChatAwaiting.contains(meeting.id)
    }

    var body: some View {
        VStack(spacing: MuesliTheme.spacing12) {
            ScrollViewReader { proxy in
                ScrollView {
                    if turns.isEmpty && !isAwaiting {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                            ForEach(turns) { turn in
                                bubble(turn.content, role: turn.role, isError: turn.isError)
                                    .id(turn.id)
                            }
                            if isAwaiting {
                                typingBubble
                                    .id("typing")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, MuesliTheme.spacing8)
                    }
                }
                .onChange(of: turns.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: isAwaiting) { _, _ in scrollToBottom(proxy) }
            }

            inputRow
        }
        .padding(.horizontal, MuesliTheme.spacing24)
        .padding(.bottom, MuesliTheme.spacing16)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { inputFocused = true }
    }

    // MARK: - Empty state (vertically centered)

    private var emptyState: some View {
        VStack(spacing: MuesliTheme.spacing8) {
            Spacer(minLength: 0)
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(tr("Chat with AI about this meeting", "Чат с ИИ по встрече"))
                .font(MuesliTheme.title3())
                .foregroundStyle(MuesliTheme.textPrimary)
            Text(tr("Ask questions about the conversation — the AI answers using this meeting's notes and transcript.", "Задавайте вопросы о разговоре — ИИ отвечает по заметкам и транскрипту этой встречи."))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 320)
    }

    // MARK: - Input row (send on the right, auto-growing field)

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 11) {
            growingInput

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(canSend ? MuesliTheme.accentSubtle : MuesliTheme.backgroundBase))
                    .overlay(Circle().strokeBorder(canSend ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help(tr("Send", "Отправить"))
        }
    }

    private var growingInput: some View {
        // Native vertical-axis TextField: sizes itself to one line, grows per
        // wrapped line up to 6, then scrolls. Return submits (Option+Return
        // inserts a newline) — no manual height measurement needed.
        TextField(
            tr("Message about this meeting…", "Сообщение о встрече…"),
            text: $draft,
            axis: .vertical
        )
        .font(MuesliTheme.callout())
        .textFieldStyle(.plain)
        .lineLimit(1...6)
        .focused($inputFocused)
        .onSubmit(send)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 20).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Bubbles

    private var typingBubble: some View {
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
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            Spacer(minLength: 40)
        }
    }

    @ViewBuilder
    private func bubble(_ text: String, role: MeetingChatMessage.Role, isError: Bool) -> some View {
        let isUser = role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            Group {
                if isUser || isError {
                    // The user's own text and error messages stay plain.
                    Text(text)
                        .font(MuesliTheme.callout())
                        .foregroundStyle(isUser ? .white : MuesliTheme.recording)
                } else {
                    // AI answers render markdown, like the meeting summary.
                    ChatMarkdownText(markdown: text)
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isUser ? MuesliTheme.accent.opacity(0.75) : MuesliTheme.backgroundBase)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isUser ? Color.clear : (isError ? MuesliTheme.recording.opacity(0.4) : MuesliTheme.surfaceBorder), lineWidth: 1)
            )
            if !isUser { Spacer(minLength: 40) }
        }
    }

    // MARK: - Logic

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAwaiting
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isAwaiting {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = turns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAwaiting else { return }
        draft = ""
        let meetingID = meeting.id
        appState.meetingChatHistories[meetingID, default: []]
            .append(MeetingChatMessage(role: .user, content: text))
        appState.meetingChatAwaiting.insert(meetingID)

        let history = (appState.meetingChatHistories[meetingID] ?? []).filter { !$0.isError }
        let context = MeetingChatContext(
            title: meeting.title,
            formattedNotes: meeting.formattedNotes,
            manualNotes: meeting.manualNotes,
            transcript: meeting.rawTranscript
        )
        let config = controller.config
        let appState = appState

        // Writes land in AppState, so the reply arrives even if the user
        // switches meetings or closes the chat page meanwhile.
        Task {
            do {
                let reply = try await MeetingChatClient.reply(history: history, context: context, config: config)
                await MainActor.run {
                    appState.meetingChatHistories[meetingID, default: []]
                        .append(MeetingChatMessage(role: .assistant, content: reply))
                    appState.meetingChatAwaiting.remove(meetingID)
                }
            } catch {
                let message = (error as? MeetingSummaryError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    appState.meetingChatHistories[meetingID, default: []]
                        .append(MeetingChatMessage(role: .assistant, content: message, isError: true))
                    appState.meetingChatAwaiting.remove(meetingID)
                }
            }
        }
    }
}
