import AppKit
import AVFoundation
import EventKit
import Observation
import SwiftUI
import MuesliCore

/// The single source of truth for every permission status shown on the
/// Функции page — both the two hero cards' badges (Dictation, Meetings)
/// and `FeaturePermissionsBoard`'s tiles read from one shared instance
/// instead of each running its own 1s polling timer over overlapping
/// system checks.
@Observable
final class FeaturePermissionStatus {
    var microphone = false
    var accessibility = false
    var inputMonitoring = false
    var screenRecording = false
    var systemAudio = false
    var calendar = false
    var isCheckingSystemAudio = false

    private var timer: Timer?
    /// Set by the owning view before `startPolling()` — a `HomeView`
    /// property, not known at `@State` property-initializer time (can't
    /// reference `self.appState` there), so this stays a plain settable
    /// var instead of an init parameter.
    var useCoreAudioTap = false

    var dictationGranted: Bool { microphone && accessibility && inputMonitoring }
    var meetingsGranted: Bool { microphone && screenRecording }

    func startPolling() {
        refresh()
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibility = AXIsProcessTrusted()
        inputMonitoring = CGPreflightListenEventAccess()
        screenRecording = CGPreflightScreenCaptureAccess()
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: calendar = true
        default: calendar = false
        }
        refreshSystemAudioIfNeeded()
    }

    private func refreshSystemAudioIfNeeded() {
        guard useCoreAudioTap, !isCheckingSystemAudio else { return }
        isCheckingSystemAudio = true
        Task { [weak self] in
            let granted = await Task.detached(priority: .utility) {
                CoreAudioSystemRecorder.checkSystemAudioPermission()
            }.value
            await MainActor.run {
                self?.systemAudio = granted
                self?.isCheckingSystemAudio = false
            }
        }
    }
}

// The standalone `FeaturePermissionsBoard` section that used to live here
// (a separate bottom-of-page permissions grid) is gone — per direct
// feedback ("все разрешения и настройки теперь крутятся вокруг базовых
// функций, а не просто размазаны в конце"), each permission tile now
// lives inside whichever function group it belongs to (see
// `HomeView.swift`'s `microphoneSubItem`/`accessibilitySubItem`/etc. and
// `dictationGroup`/`meetingsGroup`/`computerGroup`). `FeaturePermissionStatus`
// above is still the shared polling source those tiles read from.
