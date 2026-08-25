import SwiftUI
import MuesliCore

/// What kind of recording (if any) backs a meeting — single source of truth
/// for the media icon shown in the meeting header and the meetings list.
/// Always checks the file on disk, not just the stored path: a recording can
/// be deleted manually after the meeting was saved.
enum MeetingMediaKind {
    case video
    case audio
    case imported
    case notesOnly

    var symbol: String {
        switch self {
        case .video: return "video.fill"
        case .audio: return "waveform"
        case .imported: return "square.and.arrow.down"
        case .notesOnly: return "person.2.fill"
        }
    }

    var help: String {
        switch self {
        case .video: return tr("Video meeting", "Встреча с видео")
        case .audio: return tr("Audio meeting", "Аудиовстреча")
        case .imported: return tr("Imported audio", "Импортированное аудио")
        case .notesOnly: return tr("Notes only", "Только заметки")
        }
    }

    static func resolve(_ meeting: MeetingRecord) -> MeetingMediaKind {
        if let videoPath = meeting.savedVideoPath,
           !videoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           FileManager.default.fileExists(atPath: videoPath) {
            return .video
        }
        if let recordingPath = meeting.savedRecordingPath,
           !recordingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           FileManager.default.fileExists(atPath: recordingPath) {
            return meeting.source == .audioImport ? .imported : .audio
        }
        return .notesOnly
    }
}
