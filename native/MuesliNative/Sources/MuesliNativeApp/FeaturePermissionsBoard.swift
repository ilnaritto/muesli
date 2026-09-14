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

/// Round 5: the presentational "what does Muesli need access to, and why"
/// section, relocated from the Overview/dashboard page onto the Функции
/// page (per live feedback — this belongs next to the features it unlocks,
/// not on the usage-stats page) and expanded to cover every real macOS
/// permission the app uses, not just the two originally covered.
/// Always visible (never self-hides once everything's granted) — this is
/// meant to double as a presentational substitute for Settings → the
/// technical permissions list, not a one-time nag.
///
/// Round 8: folded into the same `FeatureBanner` as the main feature board
/// (per live feedback that this read as a bolted-on separate section) —
/// status is now owned by the shared `FeaturePermissionStatus` (see
/// `HomeView.swift`) instead of this view's own polling timer, since
/// `HomeView` already polls overlapping permissions for the two hero
/// cards' badges; one timer, one source of truth.
struct FeaturePermissionsBoard: View {
    let useCoreAudioTap: Bool
    let status: FeaturePermissionStatus
    /// Explicit board width, same value `mainFeaturesBoard(width:)` gets —
    /// used to size the mosaic's full-width/paired rows, not a uniform
    /// grid (per live feedback + the picked "Вариант B" mockup: the
    /// permission tiles should read as the same kind of mosaic as the
    /// cards above, not a separate grid section).
    let width: CGFloat

    @State private var eventStore = EKEventStore()

    // Keep in sync with `HomeView.mainFeaturesBoard`'s `boardSpacing` — the
    // two mosaics should read as one continuous rhythm.
    private static let spacing: CGFloat = 14

    private enum ItemKind {
        /// A real macOS permission with a system prompt this page can request.
        case grantable(granted: Bool, action: () -> Void)
        /// No system prompt exists for this one — either not needed at all,
        /// or granted automatically by macOS the first time it's used.
        case informational(note: String)
    }

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let title: String
        let unlocks: String
        let kind: ItemKind
        let pane: String
    }

    private var items: [Item] {
        var result: [Item] = [
            Item(
                id: "mic", icon: "mic.fill",
                title: tr("Microphone", "Микрофон"),
                unlocks: tr("Needed for dictation and meeting recording.", "Нужен для диктовки и записи встреч."),
                kind: .grantable(granted: status.microphone) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                },
                pane: "Privacy_Microphone"
            ),
            Item(
                id: "accessibility", icon: "cursorarrow.rays",
                title: tr("Accessibility", "Универсальный доступ"),
                unlocks: tr("Needed to paste dictated text where you're typing.", "Нужен, чтобы вставлять продиктованный текст куда ты печатаешь."),
                kind: .grantable(granted: status.accessibility) {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(opts)
                },
                pane: "Privacy_Accessibility"
            ),
            Item(
                id: "inputMonitoring", icon: "keyboard.fill",
                title: tr("Input Monitoring", "Мониторинг ввода"),
                unlocks: tr("Needed for the hold-to-talk dictation hotkey.", "Нужен для горячей клавиши диктовки."),
                kind: .grantable(granted: status.inputMonitoring) {
                    if !CGRequestListenEventAccess() { openPrivacyPane("Privacy_ListenEvent") }
                },
                pane: "Privacy_ListenEvent"
            ),
            Item(
                id: "screenRecording", icon: "display",
                title: tr("Screen Recording", "Запись экрана"),
                unlocks: tr("Needed to capture what others say in a meeting.", "Нужен, чтобы записывать то, что говорят другие на встрече."),
                kind: .grantable(granted: status.screenRecording) {
                    CGRequestScreenCaptureAccess()
                },
                pane: "Privacy_ScreenCapture"
            ),
        ]

        if useCoreAudioTap {
            result.append(Item(
                id: "systemAudio", icon: "waveform",
                title: tr("System Audio", "Системный звук"),
                unlocks: tr("Needed to capture meeting audio via the CoreAudio tap.", "Нужен для захвата звука встречи через CoreAudio."),
                kind: .grantable(granted: status.systemAudio) {
                    Task { await CoreAudioSystemRecorder.requestSystemAudioAccess() }
                },
                pane: "Privacy_ScreenCapture"
            ))
        }

        result.append(contentsOf: [
            Item(
                id: "calendar", icon: "calendar",
                title: tr("Calendar", "Календарь"),
                unlocks: tr("Optional — shows upcoming meetings and their join links.", "Опционально — показывает ближайшие встречи и ссылки на подключение."),
                kind: .grantable(granted: status.calendar) {
                    eventStore.requestFullAccessToEvents { _, _ in }
                },
                pane: "Privacy_Calendars"
            ),
            Item(
                id: "camera", icon: "camera.fill",
                title: tr("Camera", "Камера"),
                unlocks: tr("Muesli only notices when your camera turns on, to detect meetings — it never reads video, so there's no permission prompt.", "Muesli только замечает, что камера включилась, чтобы понять, что началась встреча — видео не читается, поэтому системного запроса нет."),
                kind: .informational(note: tr("Not needed", "Не требуется")),
                pane: "Privacy_Camera"
            ),
            Item(
                id: "automation", icon: "gearshape.2.fill",
                title: tr("Automation", "Автоматизация"),
                unlocks: tr("For computer-use browser actions. macOS asks the first time it's actually used — not here.", "Для действий с браузером в режиме управления компьютером. macOS спросит сама при первом использовании — не здесь."),
                kind: .informational(note: tr("Granted on first use", "Выдаётся при первом использовании")),
                pane: "Privacy_Automation"
            ),
        ])

        return result
    }

    private var grantedCount: Int {
        items.filter {
            if case .grantable(let granted, _) = $0.kind { return granted }
            return false
        }.count
    }

    private var grantableCount: Int {
        items.filter {
            if case .grantable = $0.kind { return true }
            return false
        }.count
    }

    /// Chunks a flat item list into mosaic rows: the first two items pair
    /// up, the third stands alone full-width to break the rhythm, then the
    /// rest pair off two-at-a-time with a trailing odd item (if any) also
    /// full-width — the exact grouping picked from the "Вариант B" mockup,
    /// generalized so it still reads right whether or not the conditional
    /// System Audio item is present.
    private func rows(for items: [Item]) -> [[Item]] {
        guard items.count > 3 else { return items.map { [$0] } }
        var result: [[Item]] = [[items[0], items[1]], [items[2]]]
        var rest = Array(items[3...])
        while !rest.isEmpty {
            if rest.count == 1 {
                result.append([rest.removeFirst()])
            } else {
                result.append([rest.removeFirst(), rest.removeFirst()])
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("ACCESS & PERMISSIONS · \(grantedCount)/\(grantableCount)", "ДОСТУП И РАЗРЕШЕНИЯ · \(grantedCount)/\(grantableCount)"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuesliTheme.textTertiary)
                .textCase(.uppercase)

            let half = (width - Self.spacing) / 2
            VStack(spacing: Self.spacing) {
                ForEach(Array(rows(for: items).enumerated()), id: \.offset) { _, row in
                    if row.count == 2 {
                        HStack(alignment: .top, spacing: Self.spacing) {
                            permissionCard(row[0]).frame(width: half)
                            permissionCard(row[1]).frame(width: half)
                        }
                    } else {
                        permissionCard(row[0]).frame(width: width)
                    }
                }
            }
        }
    }

    /// Same card language as the main board above (`FeatureCellContainer`
    /// + `FeatureCellHeader` + `PermissionBadge`) — per live feedback that
    /// this section needs to visually match, not have its own bespoke
    /// icon/title/bottom-button layout. The whole card opens the matching
    /// System Settings pane (mirrors the main cards' whole-card-tappable
    /// pattern); the badge is its own nested tap target for the grant
    /// action specifically.
    /// No whole-card Button anymore — it used to wrap the badge and, on
    /// macOS, silently swallowed every tap meant for it (confirmed live:
    /// "нажимаю на — выдать доступ и ничего не происходит" — the tap was
    /// actually firing `openPrivacyPane` instead of the real request API,
    /// and for panes whose URL scheme doesn't resolve on this macOS
    /// version that's visibly nothing).
    ///
    /// One button, not two. Screen Recording (and a few others on modern
    /// macOS) often show NO in-app system dialog at all when requested —
    /// the OS increasingly requires System Settings directly, so a request
    /// call alone can look like it did nothing even the very first time.
    /// Rather than ask the user to notice a separate small arrow icon,
    /// "Выдать доступ" now fires the real request API AND opens the
    /// matching System Settings pane together — whichever one actually
    /// does something, the user ends up looking at the right place either
    /// way. Once granted, the same pill's tap just opens the pane (nothing
    /// left to request). Informational items (Camera/Automation) have no
    /// grant action at all, so their pill's only job is opening the pane —
    /// same one-tappable-thing rule, no separate arrow icon needed.
    private func permissionCard(_ item: Item) -> some View {
        FeatureCellContainer {
            FeatureCellHeader(icon: item.icon, title: item.title) {
                switch item.kind {
                case .grantable(let granted, let action):
                    PermissionBadge(
                        granted: granted,
                        action: granted
                            ? { openPrivacyPane(item.pane) }
                            : { action(); openPrivacyPane(item.pane) }
                    )
                case .informational(let note):
                    StatusPill(text: note) { openPrivacyPane(item.pane) }
                }
            }
            Text(item.unlocks)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }


    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
