// Purpose: Live meeting feed (transcript + inline manual notes) during active recording
// Created: 2026-05-22

import SwiftUI

private struct LiveTranscriptGroup: Identifiable {
    // Stable ID: sequential index of the group in arrival order.
    // Using a deterministic Int instead of UUID prevents SwiftUI from treating
    // every group as removed+reinserted on each transcript update.
    let id: Int
    let speaker: String?
    let isUser: Bool
    let lines: [String]
    let timestamp: String?
}

/// One row in the merged live feed: either a group of consecutive
/// same-speaker transcript lines, or a single manual note. Notes never
/// merge into a speech group — they always stand alone (task 12).
private enum LiveFeedEntry: Identifiable {
    case speech(LiveTranscriptGroup)
    case note(id: Int, timestamp: String?, text: String)

    var id: String {
        switch self {
        case .speech(let group): return "speech-\(group.id)"
        case .note(let id, _, _): return "note-\(id)"
        }
    }

    var timestamp: String? {
        switch self {
        case .speech(let group): return group.timestamp
        case .note(_, let timestamp, _): return timestamp
        }
    }
}

/// Task 12: "Online" and "Notes" tabs merged into one screen — the live
/// transcript feed with a note composer pinned below it. A sent note is
/// spliced into the feed at its own timeline position (by timestamp), not
/// appended to a separate document.
///
/// Also serves as the isolation boundary for `appState.liveMeetingTranscript`:
/// it's read only inside this view's own body/computed properties, so
/// MeetingDetailView's body (which just passes `appState` through by
/// reference) doesn't re-evaluate on every transcript chunk (~5s).
struct LiveMeetingFeedView: View {
    let appState: AppState
    let transcriptPrefix: String
    @Binding var manualNotes: String
    let onNotesChanged: (String) -> Void

    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @State private var entries: [LiveFeedEntry] = []

    private var transcript: String {
        MeetingResumePolicy.combinedResumeTranscript(
            prior: transcriptPrefix,
            new: appState.liveMeetingTranscript
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if entries.isEmpty {
                            Text(tr("Waiting for speech…", "Ожидание речи…"))
                                .font(MuesliTheme.body())
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .padding(MuesliTheme.spacing16)
                        } else {
                            ForEach(entries) { entry in
                                feedRow(for: entry)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("liveFeedBottom")
                        }
                    }
                    .padding(.horizontal, MuesliTheme.spacing16)
                    .padding(.vertical, MuesliTheme.spacing8)
                }
                .onChange(of: transcript) { _, newTranscript in
                    rebuildEntries(transcript: newTranscript, notes: manualNotes)
                    scrollToBottom(proxy)
                }
                .onChange(of: manualNotes) { _, newNotes in
                    rebuildEntries(transcript: transcript, notes: newNotes)
                    scrollToBottom(proxy)
                }
                .onAppear {
                    // @State is freshly initialized on each tab/pane switch,
                    // so this catches up with anything that arrived elsewhere.
                    rebuildEntries(transcript: transcript, notes: manualNotes)
                    DispatchQueue.main.async {
                        proxy.scrollTo("liveFeedBottom", anchor: .bottom)
                    }
                }
            }

            composer
                .padding(.horizontal, MuesliTheme.spacing16)
                .padding(.vertical, MuesliTheme.spacing12)
        }
    }

    // MARK: - Composer (same idiom as the meeting chat: growing field + round send button)

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 11) {
            TextField(
                tr("Add a note…", "Добавить заметку…"),
                text: $draft,
                axis: .vertical
            )
            .font(MuesliTheme.callout())
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused($inputFocused)
            .onSubmit(sendNote)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 20).fill(MuesliTheme.backgroundBase))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))

            Button(action: sendNote) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSendNote ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(canSendNote ? MuesliTheme.accentSubtle : MuesliTheme.backgroundBase))
                    .overlay(Circle().strokeBorder(canSendNote ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSendNote)
            .help(tr("Add note", "Добавить заметку"))
        }
    }

    private var canSendNote: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendNote() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        // Same "[HH:MM:SS] " bracket format the live transcript itself uses
        // (MuesliController.onChunkTranscribed) so notes interleave with
        // transcript lines in correct chronological order when sorted.
        let line = "[\(Self.currentTimestampLabel())] \(text)"
        let updated = manualNotes.isEmpty ? line : manualNotes + "\n" + line
        manualNotes = updated
        onNotesChanged(updated)
    }

    private static func currentTimestampLabel() -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.hour, .minute, .second], from: Date())
        return String(format: "%02d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
    }

    // MARK: - Timeline merge

    private func rebuildEntries(transcript: String, notes: String) {
        let transcriptMessages = TranscriptChatMessage.messages(from: transcript)
        let noteMessages = TranscriptChatMessage.messages(from: notes)

        enum Raw {
            case speech(TranscriptChatMessage)
            case note(TranscriptChatMessage)

            var timestamp: String? {
                switch self {
                case .speech(let msg): return msg.timestamp
                case .note(let msg): return msg.timestamp
                }
            }
        }
        var raw: [Raw] = transcriptMessages.map { .speech($0) } + noteMessages.map { .note($0) }
        // Stable sort (guaranteed since Swift 5): entries with equal or
        // missing timestamps keep their original relative order, so two
        // already-chronological lists merge correctly.
        raw.sort { lhs, rhs in
            switch (lhs.timestamp, rhs.timestamp) {
            case let (a?, b?): return a < b
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return false
            }
        }

        var built: [LiveFeedEntry] = []
        var noteID = 0
        for item in raw {
            switch item {
            case .note(let msg):
                built.append(.note(id: noteID, timestamp: msg.timestamp, text: msg.text))
                noteID += 1
            case .speech(let msg):
                if case .speech(let lastGroup)? = built.last, lastGroup.speaker == msg.speaker {
                    let merged = LiveTranscriptGroup(
                        id: lastGroup.id,
                        speaker: lastGroup.speaker,
                        isUser: lastGroup.isUser,
                        lines: lastGroup.lines + [msg.text],
                        timestamp: lastGroup.timestamp
                    )
                    built[built.count - 1] = .speech(merged)
                } else {
                    built.append(.speech(LiveTranscriptGroup(
                        id: built.count,
                        speaker: msg.speaker,
                        isUser: msg.isUser,
                        lines: [msg.text],
                        timestamp: msg.timestamp
                    )))
                }
            }
        }
        entries = built
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("liveFeedBottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func feedRow(for entry: LiveFeedEntry) -> some View {
        switch entry {
        case .speech(let group):
            TranscriptSpeakerRow(
                speaker: group.speaker,
                timestamp: group.timestamp,
                lines: group.lines,
                isUser: group.isUser
            )
        case .note(_, let timestamp, let text):
            noteRow(timestamp: timestamp, text: text)
        }
    }

    private func noteRow(timestamp: String?, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(MuesliTheme.accentSubtle))

            VStack(alignment: .leading, spacing: 3) {
                if let timestamp {
                    Text(timestamp)
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(MuesliTheme.accentSubtle)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
    }
}
