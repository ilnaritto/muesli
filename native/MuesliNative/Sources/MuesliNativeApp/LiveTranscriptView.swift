// Purpose: Scrolling live transcript view with auto-scroll during active meetings
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

struct LiveTranscriptView: View {
    let transcript: String
    @State private var groups: [LiveTranscriptGroup] = []
    // Tracks how many characters of transcript have been parsed into groups.
    // On each onChange we only parse the new suffix, keeping updates O(k)
    // where k = lines in the new chunk rather than O(n) for the full history.
    @State private var parsedLength: Int = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if groups.isEmpty {
                        Text(tr("Waiting for speech…", "Ожидание речи…"))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .padding(MuesliTheme.spacing16)
                    } else {
                        ForEach(groups) { group in
                            liveBubble(for: group)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("liveTranscriptBottom")
                    }
                }
                .padding(.horizontal, MuesliTheme.spacing16)
                .padding(.vertical, MuesliTheme.spacing8)
            }
            .onChange(of: transcript) { _, newTranscript in
                mergeNewContent(from: newTranscript)
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("liveTranscriptBottom", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // @State is freshly initialized on each tab switch, so this
                // catches up with any chunks that arrived on another tab.
                mergeNewContent(from: transcript)
                DispatchQueue.main.async {
                    proxy.scrollTo("liveTranscriptBottom", anchor: .bottom)
                }
            }
        }
    }

    private func mergeNewContent(from newTranscript: String) {
        if newTranscript.count < parsedLength {
            groups = []
            parsedLength = 0
        }
        guard newTranscript.count > parsedLength else {
            return
        }
        let startIndex = newTranscript.index(newTranscript.startIndex, offsetBy: parsedLength)
        parsedLength = newTranscript.count

        let newMessages = TranscriptChatMessage.messages(from: String(newTranscript[startIndex...]))
        for msg in newMessages {
            if let last = groups.last, last.speaker == msg.speaker {
                groups[groups.count - 1] = LiveTranscriptGroup(
                    id: last.id,
                    speaker: last.speaker,
                    isUser: last.isUser,
                    lines: last.lines + [msg.text],
                    timestamp: last.timestamp
                )
            } else {
                groups.append(LiveTranscriptGroup(
                    id: groups.count,
                    speaker: msg.speaker,
                    isUser: msg.isUser,
                    lines: [msg.text],
                    timestamp: msg.timestamp
                ))
            }
        }
    }

    // Task 11: same TranscriptSpeakerRow as the finished-meeting transcript
    // (MeetingDetailView.swift) — avatar + name/time + plain text, one
    // shared view for both live and post-meeting reading.
    @ViewBuilder
    private func liveBubble(for group: LiveTranscriptGroup) -> some View {
        TranscriptSpeakerRow(
            speaker: group.speaker,
            timestamp: group.timestamp,
            lines: group.lines,
            isUser: group.isUser
        )
    }
}
