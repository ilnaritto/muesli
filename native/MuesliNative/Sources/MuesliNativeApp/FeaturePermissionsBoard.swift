import AppKit
import AVFoundation
import EventKit
import SwiftUI
import MuesliCore

/// Round 5: the presentational "what does Muesli need access to, and why"
/// section, relocated from the Overview/dashboard page onto the Функции
/// page (per live feedback — this belongs next to the features it unlocks,
/// not on the usage-stats page) and expanded to cover every real macOS
/// permission the app uses, not just the two originally covered.
/// Always visible (never self-hides once everything's granted) — this is
/// meant to double as a presentational substitute for Settings → the
/// technical permissions list, not a one-time nag.
struct FeaturePermissionsBoard: View {
    let useCoreAudioTap: Bool

    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var screenRecordingGranted = false
    @State private var systemAudioGranted = false
    @State private var calendarGranted = false
    @State private var isCheckingSystemAudio = false
    @State private var pollTimer: Timer?
    @State private var eventStore = EKEventStore()

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
                kind: .grantable(granted: microphoneGranted) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                },
                pane: "Privacy_Microphone"
            ),
            Item(
                id: "accessibility", icon: "cursorarrow.rays",
                title: tr("Accessibility", "Универсальный доступ"),
                unlocks: tr("Needed to paste dictated text where you're typing.", "Нужен, чтобы вставлять продиктованный текст куда ты печатаешь."),
                kind: .grantable(granted: accessibilityGranted) {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(opts)
                },
                pane: "Privacy_Accessibility"
            ),
            Item(
                id: "inputMonitoring", icon: "keyboard.fill",
                title: tr("Input Monitoring", "Мониторинг ввода"),
                unlocks: tr("Needed for the hold-to-talk dictation hotkey.", "Нужен для горячей клавиши диктовки."),
                kind: .grantable(granted: inputMonitoringGranted) {
                    if !CGRequestListenEventAccess() { openPrivacyPane("Privacy_ListenEvent") }
                },
                pane: "Privacy_ListenEvent"
            ),
            Item(
                id: "screenRecording", icon: "display",
                title: tr("Screen Recording", "Запись экрана"),
                unlocks: tr("Needed to capture what others say in a meeting.", "Нужен, чтобы записывать то, что говорят другие на встрече."),
                kind: .grantable(granted: screenRecordingGranted) {
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
                kind: .grantable(granted: systemAudioGranted) {
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
                kind: .grantable(granted: calendarGranted) {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Access & Permissions", "Доступ и разрешения"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(grantedCount == grantableCount
                    ? tr("Everything's granted — \(grantedCount)/\(grantableCount).", "Всё выдано — \(grantedCount)/\(grantableCount).")
                    : tr("The same as Settings → Permissions, just explained.", "То же самое, что в Настройках → Разрешения, только с объяснением."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 11)], spacing: 11) {
                ForEach(items) { item in
                    permissionCard(item)
                }
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    private func permissionCard(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor(for: item.kind))
                Spacer()
                Button {
                    openPrivacyPane(item.pane)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .help(tr("Open in System Settings", "Открыть в Системных настройках"))
            }
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
            Text(item.unlocks)
                .font(.system(size: 11))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            switch item.kind {
            case .grantable(let granted, let action):
                if granted {
                    Text(tr("Granted", "Разрешено"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.success)
                } else {
                    Button(tr("Grant access", "Предоставить доступ"), action: action)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(MuesliTheme.accent.opacity(0.9)))
                }
            case .informational(let note):
                Text(note)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        }
        .padding(MuesliTheme.spacing12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }

    private func statusColor(for kind: ItemKind) -> Color {
        switch kind {
        case .grantable(let granted, _): return granted ? MuesliTheme.success : MuesliTheme.accent
        case .informational: return MuesliTheme.textTertiary
        }
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling() {
        refreshStatuses()
        pollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshStatuses()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshStatuses() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: calendarGranted = true
        default: calendarGranted = false
        }
        refreshSystemAudioIfNeeded()
    }

    private func refreshSystemAudioIfNeeded() {
        guard useCoreAudioTap, !isCheckingSystemAudio else { return }
        isCheckingSystemAudio = true
        Task {
            let granted = await Task.detached(priority: .utility) {
                CoreAudioSystemRecorder.checkSystemAudioPermission()
            }.value
            await MainActor.run {
                systemAudioGranted = granted
                isCheckingSystemAudio = false
            }
        }
    }
}
