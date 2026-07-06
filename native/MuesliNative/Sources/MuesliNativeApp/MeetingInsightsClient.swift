import Foundation
import SwiftUI
import MuesliCore

enum InsightsPeriod: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return tr("Today", "Сегодня")
        case .week: return tr("This week", "Эта неделя")
        case .month: return tr("This month", "Этот месяц")
        }
    }

    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 31
        }
    }
}

/// One rendered insight card (markdown body) with a colored icon tile.
struct InsightBlock: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let markdown: String
    let icon: String
    let color: Color
}

struct InsightsResult: Sendable {
    var blocks: [InsightBlock] = []
    var errorMessage: String? = nil
    var isEmptyPeriod: Bool = false
    /// Folder the result was generated for (nil = all folders). Used to decide
    /// whether a cached result still matches the current filter.
    var folderID: Int64? = nil
}

/// Runs ONE aggregate LLM pass over the meeting summaries in a period, on the
/// user's selected meeting-summary backend, and splits the markdown answer
/// into cards (Digest / Your tasks / Decisions / Might have missed).
enum MeetingInsightsClient {
    /// Section markers the model is asked to use, mapped to card title + icon tile.
    private static let sections: [(key: String, title: String, icon: String, color: Color)] = [
        ("DIGEST", tr("Digest", "Дайджест"), "text.alignleft", Color(hex: 0x007AFF)),
        ("TASKS", tr("Your action items", "Твои задачи"), "checklist", Color(hex: 0x34C759)),
        ("DECISIONS", tr("Decisions", "Решения"), "checkmark.seal.fill", Color(hex: 0xAF52DE)),
        ("MISSED", tr("Might have missed", "Возможно, упустил"), "exclamationmark.circle.fill", Color(hex: 0xFF9500)),
    ]

    static func generate(meetings: [MeetingDigestInput], config: AppConfig) async -> InsightsResult {
        guard !meetings.isEmpty else {
            return InsightsResult(isEmptyPeriod: true)
        }

        let language = L10n.shared.isRussian ? "Russian" : "English"
        let system = """
        You are an executive assistant analyzing a set of meetings that belong to ONE person. \
        From the meeting summaries provided, produce a crisp, useful briefing. \
        Write everything in \(language). Use markdown bullets. Do not invent facts — rely only on the material. \
        Return EXACTLY these four sections, each starting with its marker on its own line, in this order:

        ###DIGEST### — 3-5 sentences: what these meetings were about and where things landed.
        ###TASKS### — action items and follow-ups that belong to this person, as bullets ("- …"). If none, write "None.".
        ###DECISIONS### — concrete decisions that were made, as bullets. If none, write "None.".
        ###MISSED### — open questions, unresolved threads, or things worth returning to, as bullets. If none, write "None.".

        Output only these sections and their content — no preamble.
        """

        var lines: [String] = []
        for meeting in meetings {
            lines.append("## \(meeting.date) — \(meeting.title)")
            lines.append(meeting.summary)
            lines.append("")
        }
        let user = "Here are \(meetings.count) meetings:\n\n" + lines.joined(separator: "\n")

        do {
            let answer = try await MeetingChatClient.complete(system: system, user: user, config: config)
            return InsightsResult(blocks: parse(answer))
        } catch {
            let message = (error as? MeetingSummaryError)?.errorDescription ?? error.localizedDescription
            return InsightsResult(errorMessage: message)
        }
    }

    private static func parse(_ answer: String) -> [InsightBlock] {
        var blocks: [InsightBlock] = []
        for (index, section) in sections.enumerated() {
            let startMarker = "###\(section.key)###"
            guard let startRange = answer.range(of: startMarker) else { continue }
            let afterStart = startRange.upperBound
            // Body runs until the next section marker (or end of string).
            var end = answer.endIndex
            for next in sections[(index + 1)...] {
                if let r = answer.range(of: "###\(next.key)###", range: afterStart..<answer.endIndex) {
                    end = r.lowerBound
                    break
                }
            }
            let body = String(answer[afterStart..<end])
                .trimmingCharacters(in: CharacterSet(charactersIn: " —-\n\r\t"))
            if !body.isEmpty {
                blocks.append(InsightBlock(title: section.title, markdown: body, icon: section.icon, color: section.color))
            }
        }
        // Fallback: model ignored markers — show the whole answer as one card.
        if blocks.isEmpty {
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(InsightBlock(title: tr("Insights", "Инсайты"), markdown: trimmed, icon: "sparkles", color: MuesliTheme.accent))
            }
        }
        return blocks
    }
}

/// Compact per-meeting input for the aggregate pass.
struct MeetingDigestInput: Sendable {
    let date: String
    let title: String
    let summary: String
}
