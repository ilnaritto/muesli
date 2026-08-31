import SwiftUI
import AppKit
import MuesliCore

/// Which action a hotkey is being assigned to. Shared between the
/// consolidated Shortcuts page and each feature's own settings section
/// (task 14.2) — both use the same `HotkeyRecorderControl`.
enum ShortcutTarget {
    case dictation
    case computerUse
    case meetingRecording
}

/// Self-contained hotkey-assignment widget: badge + change/record button +
/// hold-threshold field, plus any conflict/warning message. Used both on
/// the Shortcuts page and inline in the Dictation/Computer Use/Meetings
/// settings sections — one component, not copy-pasted, so recording rules
/// and conflict messages can't drift between the two places.
struct HotkeyRecorderControl: View {
    let appState: AppState
    let controller: MuesliController
    let target: ShortcutTarget
    var isEnabled: Bool = true

    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var pendingModifierKeyCode: UInt16?
    @State private var commitMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing12) {
                hotkeyBadge
                changeButton
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.55)
                Spacer(minLength: MuesliTheme.spacing16)
                if isEnabled {
                    thresholdInput
                }
            }
            if let effectiveMessage {
                Text(effectiveMessage)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.transcribing)
            }
        }
        .onDisappear { stopRecording() }
    }

    // MARK: - Config plumbing (per-target)

    private var hotkey: HotkeyConfig {
        switch target {
        case .dictation: return appState.config.dictationHotkey
        case .computerUse: return appState.config.computerUseHotkey
        case .meetingRecording: return appState.config.meetingRecordingHotkey
        }
    }

    private var threshold: Int {
        switch target {
        case .dictation: return appState.config.hotkeyTriggerThresholdMS
        case .computerUse: return appState.config.computerUseHotkeyTriggerThresholdMS
        case .meetingRecording: return appState.config.meetingRecordingHotkeyTriggerThresholdMS
        }
    }

    private func setThreshold(_ value: Int) {
        let clamped = HotkeyTriggerTiming.clampedMilliseconds(value)
        switch target {
        case .dictation: controller.updateConfig { $0.hotkeyTriggerThresholdMS = clamped }
        case .computerUse: controller.updateConfig { $0.computerUseHotkeyTriggerThresholdMS = clamped }
        case .meetingRecording: controller.updateConfig { $0.meetingRecordingHotkeyTriggerThresholdMS = clamped }
        }
    }

    private var effectiveMessage: String? {
        if let commitMessage { return commitMessage }
        guard isEnabled else { return nil }
        switch target {
        case .computerUse:
            if ShortcutHotkeyPolicy.hotkeysConflict(appState.config.computerUseHotkey, appState.config.dictationHotkey) {
                return ShortcutHotkeyPolicy.conflictMessage
            }
        case .meetingRecording:
            return ShortcutHotkeyPolicy.commonGlobalShortcutWarning(for: appState.config.meetingRecordingHotkey)
        case .dictation:
            break
        }
        return nil
    }

    // MARK: - Sub-controls

    private var hotkeyBadge: some View {
        Text(hotkey.displayLabel)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, MuesliTheme.spacing4)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .help(hotkey.label)
    }

    private var changeButton: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            Text(isRecording ? recordingPrompt : tr("Change Shortcut", "Изменить сочетание"))
                .font(MuesliTheme.body())
                .foregroundStyle(isRecording ? MuesliTheme.accent : MuesliTheme.textPrimary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, MuesliTheme.spacing8)
        .background(isRecording ? MuesliTheme.accentSubtle : MuesliTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(isRecording ? MuesliTheme.accent.opacity(0.3) : MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var recordingPrompt: String {
        switch target {
        case .meetingRecording:
            return tr("Press a key or modifier...", "Нажмите клавишу или модификатор...")
        case .dictation, .computerUse:
            return tr("Press a modifier key...", "Нажмите клавишу-модификатор...")
        }
    }

    private var thresholdInput: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Text(tr("Hold", "Удержание"))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)

            TextField(
                "",
                value: Binding(
                    get: { HotkeyTriggerTiming.clampedMilliseconds(threshold) },
                    set: { setThreshold($0) }
                ),
                format: .number
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(MuesliTheme.textPrimary)
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, MuesliTheme.spacing4)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )

            Text(tr("ms", "мс"))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .help(tr("Hold threshold: \(HotkeyTriggerTiming.minThresholdMilliseconds)-\(HotkeyTriggerTiming.maxThresholdMilliseconds) ms", "Порог удержания: \(HotkeyTriggerTiming.minThresholdMilliseconds)-\(HotkeyTriggerTiming.maxThresholdMilliseconds) мс"))
    }

    // MARK: - Recording

    private func startRecording() {
        stopRecording()
        commitMessage = nil
        pendingModifierKeyCode = nil
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }
                let mods = HotkeyConfig.supportedCombinationModifiers(from: event.modifierFlags)
                let hasModifiers = mods.contains(.command) || mods.contains(.control)
                    || mods.contains(.option)
                guard target == .meetingRecording,
                      hasModifiers,
                      HotkeyConfig.letterLabel(for: event.keyCode) != nil else {
                    return event
                }
                pendingModifierKeyCode = nil
                let newConfig = HotkeyConfig.combination(modifiers: mods, keyCode: event.keyCode)
                commitShortcut(newConfig)
                return nil
            }

            let keyCode = event.keyCode
            guard HotkeyConfig.label(for: keyCode) != nil else { return event }
            let flags = event.modifierFlags
            let isDown: Bool
            switch keyCode {
            case 55, 54: isDown = flags.contains(.command)
            case 56, 60: isDown = flags.contains(.shift)
            case 58, 61: isDown = flags.contains(.option)
            case 59, 62: isDown = flags.contains(.control)
            default: isDown = false
            }
            if isDown {
                pendingModifierKeyCode = keyCode
            } else if keyCode == pendingModifierKeyCode {
                let newConfig = HotkeyConfig(keyCode: keyCode, label: HotkeyConfig.label(for: keyCode)!)
                pendingModifierKeyCode = nil
                commitShortcut(newConfig)
            }
            return event
        }
    }

    private func commitShortcut(_ config: HotkeyConfig) {
        let result: ShortcutHotkeyUpdateResult
        switch target {
        case .dictation:
            result = controller.updateDictationHotkey(config)
        case .computerUse:
            result = controller.updateComputerUseHotkey(config)
        case .meetingRecording:
            result = controller.updateMeetingRecordingHotkey(config)
        }
        commitMessage = result.message
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
