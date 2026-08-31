import SwiftUI
import AppKit
import MuesliCore

struct ShortcutsView: View {
    let appState: AppState
    let controller: MuesliController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                Text(tr("Shortcuts", "Горячие клавиши"))
                    .font(MuesliTheme.pageTitle())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(tr("Choose your preferred shortcuts for dictation and computer use commands.", "Выберите удобные горячие клавиши для диктовки и команд управления компьютером."))
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)

                dictationShortcutSection

                computerUseShortcutSection

                meetingRecordingShortcutSection

                doubleTapSection

                resetButton
            }
            .padding(MuesliTheme.spacing32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dictationShortcutSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(tr("Push to Talk", "Нажми и говори"))
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(tr("Hold to record, release to transcribe", "Удерживайте для записи, отпустите для транскрипции"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            Divider()
                .background(MuesliTheme.surfaceBorder)

            HotkeyRecorderControl(appState: appState, controller: controller, target: .dictation)
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var computerUseShortcutSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    Text(tr("Computer Use Command", "Команда управления компьютером"))
                        .font(MuesliTheme.headline())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("Hold to record a command, release to plan and run it", "Удерживайте, чтобы записать команду, отпустите, чтобы спланировать и выполнить её"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.config.enableComputerUseHotkey },
                    set: { newValue in
                        _ = controller.updateComputerUseHotkeyEnabled(newValue)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(MuesliTheme.accent)
                .labelsHidden()
            }

            Divider()
                .background(MuesliTheme.surfaceBorder)

            HotkeyRecorderControl(
                appState: appState,
                controller: controller,
                target: .computerUse,
                isEnabled: appState.config.enableComputerUseHotkey
            )
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var meetingRecordingShortcutSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    Text(tr("Meeting Recording", "Запись встречи"))
                        .font(MuesliTheme.headline())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("Toggle meeting recording on/off", "Включение и выключение записи встречи"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.config.enableMeetingRecordingHotkey },
                    set: { newValue in
                        _ = controller.updateMeetingRecordingHotkeyEnabled(newValue)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(MuesliTheme.accent)
                .labelsHidden()
            }

            Divider()
                .background(MuesliTheme.surfaceBorder)

            HotkeyRecorderControl(
                appState: appState,
                controller: controller,
                target: .meetingRecording,
                isEnabled: appState.config.enableMeetingRecordingHotkey
            )
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var doubleTapSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    Text(tr("Hands-Free Mode", "Режим без рук"))
                        .font(MuesliTheme.headline())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("Double-tap dictation or CUA to start, tap again to stop", "Двойное нажатие клавиши диктовки или CUA — старт, ещё одно нажатие — стоп"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.config.enableDoubleTapDictation },
                    set: { newValue in
                        controller.updateConfig { $0.enableDoubleTapDictation = newValue }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(MuesliTheme.accent)
                .labelsHidden()
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var resetButton: some View {
        Button {
            controller.resetShortcutDefaults()
        } label: {
            Text(tr("Reset to Defaults", "Сбросить настройки"))
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(
            appState.config.dictationHotkey == .default
                && appState.config.computerUseHotkey == .computerUseDefault
                && !appState.config.enableComputerUseHotkey
                && appState.config.meetingRecordingHotkey == .meetingRecordingDefault
                && !appState.config.enableMeetingRecordingHotkey
                && appState.config.hotkeyTriggerThresholdMS == HotkeyTriggerTiming.defaultThresholdMilliseconds
                && appState.config.computerUseHotkeyTriggerThresholdMS == HotkeyTriggerTiming.defaultThresholdMilliseconds
                && appState.config.meetingRecordingHotkeyTriggerThresholdMS == HotkeyTriggerTiming.defaultMeetingThresholdMilliseconds
        )
    }
}
