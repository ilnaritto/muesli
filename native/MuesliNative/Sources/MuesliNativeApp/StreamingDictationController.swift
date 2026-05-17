import Foundation
import CoreAudio
import os

/// Merges real-time mic recording with Nemotron chunk-by-chunk transcription.
/// Text appears at the cursor as the user speaks (~560ms per chunk).
///
/// Usage:
///   let controller = StreamingDictationController(transcriber: nemotron)
///   controller.onPartialText = { fullText in /* paste delta */ }
///   controller.start()
///   // ... user speaks ...
///   let finalText = controller.stop()
@available(macOS 15, *)
final class StreamingDictationController {
    /// Called with the full accumulated transcript so far (on a background thread).
    var onPartialText: ((String) -> Void)?

    private let transcriber: NemotronStreamingTranscriber
    private let recorder: StreamingDictationRecording
    private var streamState: NemotronStreamingTranscriber.StreamState?
    private var sampleBuffer: [Float] = []
    private let bufferLock = OSAllocatedUnfairLock()
    private var chunkQueue: [[Float]] = []
    private let queueLock = OSAllocatedUnfairLock()
    private var isDraining = false
    private let drainLock = OSAllocatedUnfairLock()
    private var fullTranscript = ""
    private var isActive = false
    private var activeSessionID: UUID?
    private let chunkSamples = 8960  // 560ms at 16kHz

    init(
        transcriber: NemotronStreamingTranscriber,
        preferredInputDeviceID: AudioObjectID? = nil,
        recorder: StreamingDictationRecording = StreamingMicRecorder()
    ) {
        self.transcriber = transcriber
        self.recorder = recorder
        recorder.preferredInputDeviceID = preferredInputDeviceID
    }

    /// Pre-warm the ANE so first real chunk is fast. Call this early (e.g., on backend select).
    func warmup() {
        Task {
            do {
                var state = try await transcriber.makeStreamState()
                fputs("[streaming-dictation] warming up ANE...\n", stderr)
                let silence = [Float](repeating: 0, count: chunkSamples)
                _ = try? await transcriber.transcribeChunk(samples: silence, state: &state)
                fputs("[streaming-dictation] warmup done\n", stderr)
            } catch {
                fputs("[streaming-dictation] warmup failed: \(error)\n", stderr)
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        guard !isActive else { return true }
        let sessionID = UUID()
        isActive = true
        activeSessionID = sessionID
        fullTranscript = ""
        sampleBuffer.removeAll()
        chunkQueue.removeAll()
        streamState = nil
        drainLock.withLock {
            isDraining = false
        }

        // Start mic IMMEDIATELY — don't block on state init or warmup
        recorder.onAudioBuffer = { [weak self] samples in
            self?.handleAudioBuffer(samples)
        }
        do {
            try recorder.prepare()
            try recorder.start()
            fputs("[streaming-dictation] mic started\n", stderr)
        } catch {
            fputs("[streaming-dictation] mic start failed: \(error)\n", stderr)
            isActive = false
            activeSessionID = nil
            recorder.cancel()
            bufferLock.withLock {
                sampleBuffer.removeAll()
            }
            queueLock.withLock {
                chunkQueue.removeAll()
            }
            drainLock.withLock {
                isDraining = false
            }
            streamState = nil
            return false
        }

        // Init stream state in background — audio buffers queue while this runs
        Task {
            do {
                let state = try await transcriber.makeStreamState()
                guard self.isCurrentSession(sessionID) else { return }
                streamState = state
                fputs("[streaming-dictation] stream state ready, draining queued chunks\n", stderr)
                startDrainIfNeeded(sessionID: sessionID)
            } catch {
                guard self.isCurrentSession(sessionID) else { return }
                fputs("[streaming-dictation] failed to create stream state: \(error)\n", stderr)
            }
        }
        return true
    }

    /// Stop recording and return text already emitted by real-time chunk drains.
    /// This intentionally avoids blocking the main thread on trailing chunks.
    func stop() -> String {
        guard isActive else { return fullTranscript }
        isActive = false
        activeSessionID = nil

        let _ = recorder.stop()

        // Collect remaining buffered samples
        let remaining: [Float] = bufferLock.withLock {
            let samples = sampleBuffer
            sampleBuffer.removeAll()
            return samples
        }

        queueLock.withLock {
            chunkQueue.removeAll()
        }
        drainLock.withLock {
            isDraining = false
        }
        if !remaining.isEmpty {
            fputs("[streaming-dictation] discarded trailing samples on stop: \(remaining.count)\n", stderr)
        }

        fputs("[streaming-dictation] stopped, transcript (\(fullTranscript.count) chars): \(fullTranscript.prefix(100))...\n", stderr)
        return fullTranscript
    }

    // MARK: - Audio Buffer Handling

    /// Called on AVAudioEngine's audio processing thread (4096 samples per call).
    private func handleAudioBuffer(_ samples: [Float]) {
        guard isActive else { return }

        let newChunks = bufferLock.withLock { () -> [[Float]] in
            var chunks: [[Float]] = []
            sampleBuffer.append(contentsOf: samples)
            while sampleBuffer.count >= chunkSamples {
                chunks.append(Array(sampleBuffer.prefix(chunkSamples)))
                sampleBuffer.removeFirst(chunkSamples)
            }
            return chunks
        }

        if !newChunks.isEmpty {
            queueLock.withLock {
                chunkQueue.append(contentsOf: newChunks)
            }
            // Kick off serial processing if not already running
            guard let sessionID = activeSessionID else { return }
            startDrainIfNeeded(sessionID: sessionID)
        }
    }

    private func startDrainIfNeeded(sessionID: UUID) {
        guard isCurrentSession(sessionID) else { return }
        let shouldStart = drainLock.withLock {
            if isDraining { return false }
            isDraining = true
            return true
        }
        guard shouldStart else { return }
        Task { [weak self] in
            await self?.drainQueue(sessionID: sessionID)
            self?.markDrainFinished(sessionID: sessionID)
        }
    }

    private func markDrainFinished(sessionID: UUID) {
        let hasQueuedChunks = queueLock.withLock { !chunkQueue.isEmpty }
        drainLock.withLock {
            isDraining = false
        }
        if hasQueuedChunks {
            startDrainIfNeeded(sessionID: sessionID)
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        isActive && activeSessionID == sessionID
    }

    /// Process all queued chunks serially, one at a time.
    private func drainQueue(sessionID: UUID) async {
        while true {
            guard isCurrentSession(sessionID) else { return }
            let chunk: [Float]? = queueLock.withLock {
                chunkQueue.isEmpty ? nil : chunkQueue.removeFirst()
            }
            guard let chunk else { return }

            guard var state = streamState else {
                fputs("[streaming-dictation] no stream state, skipping chunk\n", stderr)
                queueLock.withLock {
                    chunkQueue.insert(chunk, at: 0)
                }
                return
            }

            let start = CFAbsoluteTimeGetCurrent()
            do {
                let newText = try await transcriber.transcribeChunk(samples: chunk, state: &state)
                guard isCurrentSession(sessionID) else { return }
                streamState = state
                let elapsed = CFAbsoluteTimeGetCurrent() - start

                if !newText.isEmpty {
                    fullTranscript += newText
                    fputs("[streaming-dictation] chunk → \"\(newText)\" (\(String(format: "%.0f", elapsed * 1000))ms)\n", stderr)
                    onPartialText?(fullTranscript)
                } else {
                    fputs("[streaming-dictation] chunk → (silence) (\(String(format: "%.0f", elapsed * 1000))ms)\n", stderr)
                }
            } catch {
                fputs("[streaming-dictation] chunk error: \(error)\n", stderr)
            }
        }
    }
}
