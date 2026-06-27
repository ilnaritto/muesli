import Foundation
import Testing
import MuesliCore
@testable import MuesliNativeApp

@Suite("Meeting resume policy")
struct MeetingResumePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("a completed meeting that just ended can be resumed")
    func completedRecentlyCanResume() {
        let endedAt = now.addingTimeInterval(-60 * 60)  // 1h ago
        #expect(MeetingResumePolicy.canResume(status: .completed, endedAt: endedAt, now: now))
    }

    @Test("a completed meeting older than the window cannot be resumed")
    func completedStaleCannotResume() {
        let endedAt = now.addingTimeInterval(-(MeetingResumePolicy.resumeWindow + 60))
        #expect(!MeetingResumePolicy.canResume(status: .completed, endedAt: endedAt, now: now))
    }

    @Test("the window boundary is exclusive")
    func windowBoundaryIsExclusive() {
        let endedAt = now.addingTimeInterval(-MeetingResumePolicy.resumeWindow)
        #expect(!MeetingResumePolicy.canResume(status: .completed, endedAt: endedAt, now: now))
    }

    @Test("non-completed meetings cannot be resumed even within the window")
    func nonCompletedCannotResume() {
        let endedAt = now.addingTimeInterval(-60)
        for status in [MeetingStatus.recording, .processing, .noteOnly, .failed] {
            #expect(!MeetingResumePolicy.canResume(status: status, endedAt: endedAt, now: now))
        }
    }

    @Test("combined transcript keeps the prior text and appends the new with a separator")
    func combinedTranscriptAppends() {
        let combined = MeetingResumePolicy.combinedResumeTranscript(prior: "first half", new: "second half")
        #expect(combined == "first half\(MeetingResumePolicy.resumeSeparator)second half")
        #expect(combined.contains("first half"))
        #expect(combined.contains("second half"))
    }

    @Test("combined transcript returns the prior unchanged when nothing new was captured")
    func combinedTranscriptNoNewContent() {
        #expect(MeetingResumePolicy.combinedResumeTranscript(prior: "only half", new: "   \n ") == "only half")
        #expect(MeetingResumePolicy.combinedResumeTranscript(prior: "only half", new: "") == "only half")
    }

    private func makeResult(start: Date, end: Date) -> MeetingSessionResult {
        MeetingSessionResult(
            title: "M",
            originalTitle: "M",
            calendarEventID: nil,
            startTime: start,
            endTime: end,
            durationSeconds: end.timeIntervalSince(start),
            rawTranscript: "new segment",
            formattedNotes: "notes",
            retainedRecordingURL: nil,
            retainedRecordingError: nil,
            systemRecordingURL: nil,
            templateSnapshot: MeetingTemplates.auto.snapshot
        )
    }

    @Test("resume override preserves the original start and spans the duration")
    func resumeOverridePreservesOriginalStart() {
        let originalStart = Date(timeIntervalSince1970: 1_000_000)
        let resumeStart = originalStart.addingTimeInterval(3600)      // resumed 1h later
        let resumeEnd = resumeStart.addingTimeInterval(30)            // recorded 30s
        let resumed = makeResult(start: resumeStart, end: resumeEnd)

        let merged = resumed.overriding(
            startTime: originalStart,
            rawTranscript: "old\(MeetingResumePolicy.resumeSeparator)new",
            formattedNotes: "merged"
        )

        #expect(merged.startTime == originalStart)                    // original date preserved, not the resume moment
        #expect(merged.endTime == resumeEnd)                          // end is the resumed stop
        #expect(merged.durationSeconds == resumeEnd.timeIntervalSince(originalStart))  // span: start_time + duration == real end
        #expect(merged.rawTranscript == "old\(MeetingResumePolicy.resumeSeparator)new")
        #expect(merged.formattedNotes == "merged")
    }

    @Test("override without a start time leaves timing untouched")
    func overrideWithoutStartKeepsTiming() {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let result = makeResult(start: start, end: start.addingTimeInterval(45))

        let overridden = result.overriding(rawTranscript: "z", formattedNotes: "w")

        #expect(overridden.startTime == start)
        #expect(overridden.durationSeconds == 45)
        #expect(overridden.rawTranscript == "z")
    }
}
