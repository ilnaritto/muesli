import AVFoundation
import Foundation
import ScreenCaptureKit

/// Records the main display to a temporary video-only .mp4 during a meeting.
///
/// Runs its own SCStream independent of the system-audio path, so it works
/// whether system audio comes from ScreenCaptureKit or the CoreAudio tap.
/// After the meeting the temporary file is muxed with the saved audio mix by
/// `MeetingVideoComposer`.
final class MeetingScreenVideoRecorder: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var outputURL: URL?
    private let sampleQueue = DispatchQueue(label: "muesli.meeting.screen-video")

    /// Frame rate is deliberately low: meeting content is mostly static and
    /// the encode must not compete with live transcription for CPU.
    private static let framesPerSecond: Int32 = 10

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "MeetingScreenVideoRecorder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No display found for screen video capture"
            ])
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("muesli-meeting-video")
            .appendingPathComponent("\(UUID().uuidString).mp4")
        try FileManager.default.createDirectory(
            at: tempURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let width = display.width
        let height = display.height

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_500_000,
                AVVideoExpectedSourceFrameRateKey: Self.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: Self.framesPerSecond * 4
            ]
        ])
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw NSError(domain: "MeetingScreenVideoRecorder", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Cannot add video input to asset writer"
            ])
        }
        writer.add(videoInput)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "MeetingScreenVideoRecorder", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Asset writer failed to start"
            ])
        }

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: Self.framesPerSecond)
        config.queueDepth = 5
        config.showsCursor = true
        config.capturesAudio = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

        self.writer = writer
        self.videoInput = videoInput
        self.outputURL = tempURL
        self.sessionStarted = false
        self.stream = stream

        try await stream.startCapture()
        fputs("[meeting-video] screen capture started (\(width)x\(height) @ \(Self.framesPerSecond)fps)\n", stderr)
    }

    /// Stops capture and finalizes the temporary file. Returns nil when the
    /// recording never produced a frame or finalization failed.
    func stop() async -> URL? {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        let finishedURL: URL? = await withCheckedContinuation { continuation in
            sampleQueue.async { [self] in
                guard let writer, sessionStarted, writer.status == .writing else {
                    writer?.cancelWriting()
                    if let outputURL {
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                    continuation.resume(returning: nil)
                    return
                }
                videoInput?.markAsFinished()
                let url = outputURL
                writer.finishWriting {
                    continuation.resume(returning: writer.status == .completed ? url : nil)
                }
            }
        }

        writer = nil
        videoInput = nil
        if finishedURL != nil {
            fputs("[meeting-video] screen capture finished: \(finishedURL!.path)\n", stderr)
        } else {
            fputs("[meeting-video] screen capture produced no usable video\n", stderr)
        }
        return finishedURL
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let writer,
              let videoInput else { return }

        // Skip frames ScreenCaptureKit marks as incomplete/idle.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusValue),
              status == .complete else {
            return
        }

        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }
        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }
}

/// Muxes the temporary video-only recording with the saved meeting audio mix
/// into the final .mp4 next to the audio in `meeting-recordings/`.
enum MeetingVideoComposer {
    /// Returns the final video URL. The temporary video file is removed on
    /// success. When `audioPath` is nil the video is stored without sound.
    static func finalize(
        temporaryVideoURL: URL,
        audioPath: String?,
        supportDirectory: URL
    ) async throws -> URL {
        let recordingsDirectory = supportDirectory.appendingPathComponent("meeting-recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let baseName: String
        if let audioPath {
            baseName = URL(fileURLWithPath: audioPath).deletingPathExtension().lastPathComponent
        } else {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            baseName = "Meeting Video \(stamp)"
        }
        var outputURL = recordingsDirectory.appendingPathComponent("\(baseName).mp4")
        var suffix = 2
        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = recordingsDirectory.appendingPathComponent("\(baseName) \(suffix).mp4")
            suffix += 1
        }

        guard let audioPath, FileManager.default.fileExists(atPath: audioPath) else {
            // No saved audio — keep the video as-is.
            fputs("[meeting-video] no audio available (path: \(audioPath ?? "nil")) — saving silent video\n", stderr)
            try FileManager.default.moveItem(at: temporaryVideoURL, to: outputURL)
            return outputURL
        }

        // PCM (wav) tracks can't be passed through into an .mp4 container —
        // transcode to AAC first, otherwise the export fails or drops audio.
        var audioURL = URL(fileURLWithPath: audioPath)
        var temporaryAACURL: URL?
        if audioURL.pathExtension.lowercased() == "wav" {
            let aacURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("muesli-video-audio-\(UUID().uuidString).m4a")
            try await transcodeToM4A(sourceURL: audioURL, destinationURL: aacURL)
            audioURL = aacURL
            temporaryAACURL = aacURL
        }
        defer {
            if let temporaryAACURL {
                try? FileManager.default.removeItem(at: temporaryAACURL)
            }
        }

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: temporaryVideoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        guard let videoAssetTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "MeetingVideoComposer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Recorded video has no video track"
            ])
        }
        let videoDuration = try await videoAsset.load(.duration)
        try compositionVideo.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoAssetTrack,
            at: .zero
        )

        if let audioAssetTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioDuration = try await audioAsset.load(.duration)
            try compositionAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: audioDuration),
                of: audioAssetTrack,
                at: .zero
            )
        }

        if composition.tracks(withMediaType: .audio).isEmpty {
            fputs("[meeting-video] WARNING: no audio track loaded from \(audioURL.lastPathComponent) — video will be silent\n", stderr)
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "MeetingVideoComposer", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create export session"
            ])
        }
        export.outputURL = outputURL
        export.outputFileType = .mp4
        await export.export()
        if let error = export.error {
            throw error
        }

        try? FileManager.default.removeItem(at: temporaryVideoURL)
        fputs("[meeting-video] finalized with audio: \(outputURL.lastPathComponent)\n", stderr)
        return outputURL
    }

    private static func transcodeToM4A(sourceURL: URL, destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "MeetingVideoComposer", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create audio transcode session"
            ])
        }
        export.outputURL = destinationURL
        export.outputFileType = .m4a
        await export.export()
        if let error = export.error {
            throw error
        }
    }
}
