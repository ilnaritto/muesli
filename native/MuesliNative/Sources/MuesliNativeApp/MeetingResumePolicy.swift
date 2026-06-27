import Foundation
import MuesliCore

/// Decides whether a finished meeting may be resumed (reopened to append more
/// recording onto the same meeting row).
///
/// Resume is only offered for a short window after a meeting ends so it stays an
/// "accidental stop / same sitting" recovery, not a way to retroactively merge a
/// days-old or recurring meeting (see `Context/prd-120-resume-followup.md`).
enum MeetingResumePolicy {
    /// How long after a meeting ends the Resume action remains available.
    /// Anchored to the meeting's end time (`start_time + duration_seconds`), which
    /// is fixed at finalization and immune to later note edits.
    static let resumeWindow: TimeInterval = 5 * 60 * 60  // 5 hours

    /// - Parameters:
    ///   - status: the meeting's current status; only `.completed` meetings resume.
    ///   - endedAt: when the meeting finished (`start_time + duration_seconds`).
    ///   - now: the current time (injectable for tests).
    ///   - window: the resume window (defaults to ``resumeWindow``).
    static func canResume(
        status: MeetingStatus,
        endedAt: Date,
        now: Date = Date(),
        window: TimeInterval = resumeWindow
    ) -> Bool {
        guard status == .completed else { return false }
        return now.timeIntervalSince(endedAt) < window
    }

    /// Separator inserted between the prior transcript and the newly recorded one
    /// when a meeting is resumed (Approach A — concatenate, see the PRD).
    static let resumeSeparator = "\n\n— Resumed —\n\n"

    /// Concatenates the prior transcript with the newly recorded one. If nothing
    /// new was captured (empty/whitespace), the prior transcript is returned
    /// unchanged so a no-op resume never appends a dangling separator.
    static func combinedResumeTranscript(prior: String, new: String) -> String {
        guard !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return prior }
        return prior + resumeSeparator + new
    }
}
