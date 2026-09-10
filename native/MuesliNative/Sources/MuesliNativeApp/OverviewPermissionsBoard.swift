import AppKit
import AVFoundation
import SwiftUI
import MuesliCore

/// Round 3 feedback: the Overview dashboard should "immerse the user in the
/// features and push them to grant permissions, not just redirect to
/// Settings" — it should read like settings but in presentational format,
/// so a new user understands WHAT each permission unlocks instead of being
/// dropped on a bare system-style toggle list. Shows only while at least
/// one relevant permission is missing; once everything's granted the board
/// disappears entirely rather than sitting there as permanent clutter.
///
/// Deliberately duplicates the same status checks/requests already used in
/// `SettingsView`/`OnboardingView` (same APIs, same 1s poll-while-visible
/// pattern) rather than sharing state with them — those two already
/// independently duplicate this same permission logic today, so a third
/// self-contained copy here is consistent with how the rest of the app
/// already handles it, and keeps this board's lifecycle (poll only while
/// Overview is on screen) simple and self-owned.
struct OverviewPermissionsBoard: View {
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var screenRecordingGranted = false
    @State private var pollTimer: Timer?

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let title: String
        let unlocks: String
        let granted: Bool
        let action: () -> Void
    }

    private var items: [Item] {
        [
            Item(
                id: "mic",
                icon: "mic.fill",
                title: tr("Microphone", "Микрофон"),
                unlocks: tr("Needed for dictation and meeting recording.", "Нужен для диктовки и записи встреч."),
                granted: micGranted,
                action: { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
            ),
            Item(
                id: "accessibility",
                icon: "cursorarrow.rays",
                title: tr("Accessibility", "Универсальный доступ"),
                unlocks: tr("Needed to paste dictated text where you're typing.", "Нужен, чтобы вставлять продиктованный текст куда ты печатаешь."),
                granted: accessibilityGranted,
                action: {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(opts)
                }
            ),
            Item(
                id: "inputMonitoring",
                icon: "keyboard.fill",
                title: tr("Input Monitoring", "Мониторинг ввода"),
                unlocks: tr("Needed for the hold-to-talk dictation hotkey.", "Нужен для горячей клавиши диктовки."),
                granted: inputMonitoringGranted,
                action: {
                    if !CGRequestListenEventAccess() {
                        openPrivacyPane("Privacy_ListenEvent")
                    }
                }
            ),
            Item(
                id: "screenRecording",
                icon: "display",
                title: tr("Screen Recording", "Запись экрана"),
                unlocks: tr("Needed to capture what others say in a meeting.", "Нужен, чтобы записывать то, что говорят другие на встрече."),
                granted: screenRecordingGranted,
                action: { CGRequestScreenCaptureAccess() }
            ),
        ]
    }

    private var missingItems: [Item] {
        items.filter { !$0.granted }
    }

    var body: some View {
        if !missingItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Finish setting up Muesli", "Заверши настройку Muesli"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("A few permissions unlock the rest of what Muesli can do.", "Несколько разрешений откроют остальные возможности Muesli."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 4), spacing: 11) {
                    ForEach(items) { item in
                        permissionCard(item)
                    }
                }
            }
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
        }
    }

    private func permissionCard(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.granted ? MuesliTheme.success : MuesliTheme.accent)
                Spacer()
                if item.granted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(MuesliTheme.success)
                }
            }
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
            Text(item.unlocks)
                .font(.system(size: 11))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !item.granted {
                Button(tr("Grant access", "Предоставить доступ")) {
                    item.action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(MuesliTheme.accent.opacity(0.82)))
            }
        }
        .padding(MuesliTheme.spacing12)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
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
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }
}
