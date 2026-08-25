import AppKit
import SwiftUI
import MuesliCore

struct AboutView: View {
    let appState: AppState
    let onOpenManualDiagnosticReport: () -> Void

    private let originalAuthorURL = "https://github.com/Muesli-HQ/muesli"
    private let redesignAuthorURL = "https://github.com/ilnaritto/muesli"

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        return "v\(v)"
    }

    private var appDataPath: String {
        AppIdentity.supportDirectoryURL.path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing32) {
                heroCard

                if let banner = updateBanner {
                    updateBannerView(banner)
                }

                // MARK: - App Info
                sectionHeader(tr("App Info", "Сведения о приложении"))
                aboutCard {
                    iconRow(icon: "number", title: tr("Version", "Версия")) {
                        Text(version)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    iconRow(icon: "arrow.triangle.2.circlepath", title: tr("Updates", "Обновления")) {
                        Text(updateRowGuidance)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // MARK: - Support
                sectionHeader(tr("Support", "Поддержка"))
                aboutCard {
                    iconRow(icon: "chevron.left.slash.chevron.right", title: tr("Source Code", "Исходный код")) {
                        openButton(tr("Open", "Открыть"), icon: "arrow.up.right.square") {
                            if let url = URL(string: originalAuthorURL) { NSWorkspace.shared.open(url) }
                        }
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    iconRow(icon: "exclamationmark.bubble", title: tr("Report a Problem", "Сообщить о проблеме")) {
                        openButton(tr("Open", "Открыть"), icon: "exclamationmark.bubble") {
                            onOpenManualDiagnosticReport()
                        }
                    }
                }

                // MARK: - Credits
                sectionHeader(tr("Credits", "Авторство"))
                aboutCard {
                    iconRow(
                        icon: "cpu",
                        title: tr("Original author (engine)", "Оригинальный автор (движок)"),
                        subtitle: tr("Engine, models, privacy, transcription", "Движок, модели, приватность, транскрипция")
                    ) {
                        openButton(tr("Open", "Открыть"), icon: "arrow.up.right.square") {
                            if let url = URL(string: originalAuthorURL) { NSWorkspace.shared.open(url) }
                        }
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    iconRow(
                        icon: "paintbrush.pointed",
                        title: tr("ilnaritto (UX/UI design)", "ilnaritto (UX/UI-дизайн)"),
                        subtitle: tr("Interface, navigation, this fork's visual language", "Интерфейс, навигация, визуальный язык этого форка")
                    ) {
                        openButton(tr("Open", "Открыть"), icon: "arrow.up.right.square") {
                            if let url = URL(string: redesignAuthorURL) { NSWorkspace.shared.open(url) }
                        }
                    }
                }

                // MARK: - Data
                sectionHeader(tr("Data", "Данные"))
                aboutCard {
                    iconRow(icon: "folder", title: tr("App Data Directory", "Папка данных приложения"), subtitle: appDataPath, subtitleMonospaced: true) {
                        openButton(tr("Open", "Открыть"), icon: "folder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDataPath)
                        }
                    }
                }

                // MARK: - Acknowledgements
                sectionHeader(tr("Acknowledgements", "Благодарности"))
                aboutCard {
                    iconRow(
                        icon: "waveform",
                        title: "FluidAudio",
                        subtitle: tr("CoreML speech stack: Parakeet, Qwen3 ASR, VAD, diarization.", "Речевой стек CoreML: Parakeet, Qwen3 ASR, VAD, диаризация.")
                    ) { EmptyView() }

                    Divider().background(MuesliTheme.surfaceBorder)

                    iconRow(
                        icon: "waveform.badge.minus",
                        title: "LocalVQE",
                        subtitle: tr("On-device echo cancellation for cleaner transcription.", "Эхоподавление на устройстве для более чистой транскрипции.")
                    ) { EmptyView() }

                    Divider().background(MuesliTheme.surfaceBorder)

                    iconRow(
                        icon: "text.bubble",
                        title: "WhisperKit",
                        subtitle: tr("Swift Whisper inference on CoreML/ANE.", "Инференс Whisper на Swift через CoreML/ANE.")
                    ) { EmptyView() }
                }

                Spacer(minLength: MuesliTheme.spacing32)
            }
            .padding(MuesliTheme.spacing32)
        }
    }

    // MARK: - Hero

    private var appIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "muesli_app_icon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    @ViewBuilder
    private var heroCard: some View {
        HStack(alignment: .center, spacing: MuesliTheme.spacing24) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                HStack(spacing: MuesliTheme.spacing12) {
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                            )
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Muesli")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(MuesliTheme.textPrimary)
                        HStack(spacing: 5) {
                            Text(tr("UX/UI Update", "Редизайн UX/UI"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MuesliTheme.accent)
                            Text("·")
                                .foregroundStyle(MuesliTheme.textTertiary)
                            Text(version)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                    }
                }

                Text(tr(
                    "This is a design fork of Muesli: the same on-device speech engine, a fully reworked interface. The technical foundation — models, privacy, the transcription engine — was built by the original author.",
                    "Это дизайн-форк Muesli: тот же локальный движок распознавания речи, полностью переработанный интерфейс. Технический фундамент — модели, приватность, движок транскрипции — сделан автором оригинала."
                ))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            heroMockup
                .fixedSize()
        }
        .padding(MuesliTheme.spacing24)
        .background(
            LinearGradient(
                colors: [MuesliTheme.accentSubtle, MuesliTheme.backgroundBase],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    /// Illustrated stand-in for a marketing screenshot: a miniature "meeting
    /// notes" window mockup plus a floating dictation pill, built from the
    /// app's own theme tokens rather than a captured screenshot or photo.
    @ViewBuilder
    private var heroMockup: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 6) {
                Circle()
                    .fill(MuesliTheme.recording)
                    .frame(width: 7, height: 7)
                Text(tr("Listening…", "Слушаю…"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(MuesliTheme.backgroundRaised))
            .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
            .rotationEffect(.degrees(-5))
            .offset(x: 6, y: -6)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: 0xFF5F57)).frame(width: 7, height: 7)
                    Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 7, height: 7)
                    Circle().fill(Color(hex: 0x28C840)).frame(width: 7, height: 7)
                }

                Text(tr("Weekly Sync", "Еженедельная встреча"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)

                HStack(spacing: 6) {
                    mockTag(tr("Roadmap", "План"))
                    mockTag(tr("Launch", "Запуск"))
                    mockTag(tr("Budget", "Бюджет"))
                }

                VStack(alignment: .leading, spacing: 6) {
                    mockLine(width: 152)
                    mockLine(width: 188)
                    mockLine(width: 116)
                }
                .padding(.top, 2)
            }
            .padding(14)
            .frame(width: 216, alignment: .leading)
            .background(MuesliTheme.backgroundBase)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.30), radius: 24, y: 16)
            .offset(x: 14, y: 24)
        }
        .frame(width: 230, height: 150, alignment: .topLeading)
    }

    private func mockTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(MuesliTheme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(MuesliTheme.accentSubtle))
    }

    private func mockLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(MuesliTheme.textTertiary.opacity(0.5))
            .frame(width: width, height: 6)
    }

    // MARK: - Components

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MuesliTheme.textTertiary)
            .textCase(.uppercase)
            .padding(.leading, 2)
    }

    @ViewBuilder
    private func aboutCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(MuesliTheme.spacing20)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private struct UpdateBanner {
        let icon: String
        let title: String
        let message: String
        let tint: Color
    }

    private var updateRowGuidance: String {
        switch appState.sparkleUpdateStatus {
        case .available:
            return tr("Use the menu bar icon > Check for Updates...", "Значок в строке меню > Проверить обновления...")
        case .downloaded:
            return tr("Use the menu bar updater to finish installation.", "Завершите установку через обновление в строке меню.")
        case .checking, .busy, .installing:
            return tr("Checking...", "Проверка...")
        case .failed:
            return tr("Use the menu bar icon > Check for Updates...", "Значок в строке меню > Проверить обновления...")
        case .idle, .upToDate, .disabled:
            return tr("Use the menu bar icon > Check for Updates...", "Значок в строке меню > Проверить обновления...")
        }
    }

    private var updateBanner: UpdateBanner? {
        switch appState.sparkleUpdateStatus {
        case .idle:
            return nil
        case .checking:
            return UpdateBanner(
                icon: "arrow.triangle.2.circlepath",
                title: tr("Checking for updates", "Проверка обновлений"),
                message: tr("Muesli is checking the appcast for the latest version.", "Muesli проверяет наличие последней версии в appcast."),
                tint: MuesliTheme.transcribing
            )
        case .busy(let message):
            return UpdateBanner(
                icon: "clock.arrow.circlepath",
                title: tr("Updater is busy", "Обновление занято"),
                message: message,
                tint: MuesliTheme.transcribing
            )
        case .available(let version):
            return UpdateBanner(
                icon: "exclamationmark.triangle.fill",
                title: tr("Muesli \(version) is available", "Доступна Muesli \(version)"),
                message: tr("An update is available. Use the menu bar icon > Check for Updates... to open the updater.", "Доступно обновление. Откройте значок в строке меню > Проверить обновления..., чтобы запустить обновление."),
                tint: MuesliTheme.transcribing
            )
        case .downloaded(let version):
            return UpdateBanner(
                icon: "exclamationmark.triangle.fill",
                title: tr("Muesli \(version) is ready to install", "Muesli \(version) готова к установке"),
                message: tr("The update is downloaded. Use the menu bar updater to finish installation.", "Обновление загружено. Завершите установку через обновление в строке меню."),
                tint: MuesliTheme.transcribing
            )
        case .installing(let version):
            return UpdateBanner(
                icon: "arrow.down.circle.fill",
                title: tr("Installing Muesli \(version)", "Установка Muesli \(version)"),
                message: tr("Sparkle is preparing the update. Muesli may relaunch when installation finishes.", "Sparkle готовит обновление. Muesli может перезапуститься после завершения установки."),
                tint: MuesliTheme.transcribing
            )
        case .upToDate:
            return UpdateBanner(
                icon: "checkmark.circle.fill",
                title: tr("Muesli is up to date", "Установлена последняя версия Muesli"),
                message: tr("No newer version was found in the appcast.", "Более новая версия в appcast не найдена."),
                tint: MuesliTheme.success
            )
        case .disabled(let message):
            return UpdateBanner(
                icon: "minus.circle.fill",
                title: tr("Updates are disabled", "Обновления отключены"),
                message: message,
                tint: MuesliTheme.textTertiary
            )
        case .failed(let message):
            return UpdateBanner(
                icon: "xmark.octagon.fill",
                title: tr("Update check failed", "Не удалось проверить обновления"),
                message: tr("\(message) Use the menu bar icon > Check for Updates... to try again.", "\(message) Откройте значок в строке меню > Проверить обновления..., чтобы повторить попытку."),
                tint: MuesliTheme.recording
            )
        }
    }

    @ViewBuilder
    private func updateBannerView(_ banner: UpdateBanner) -> some View {
        HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
            Image(systemName: banner.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(banner.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(banner.title)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(banner.message)
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: MuesliTheme.spacing16)
        }
        .padding(MuesliTheme.spacing16)
        .background(banner.tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(banner.tint.opacity(0.45), lineWidth: 1)
        )
    }

    /// Icon-tile row: replaces the old fixed-136pt-control `aboutRow` with a
    /// layout that scales to whatever control it's given (button, text, or
    /// nothing for a pure acknowledgement entry).
    @ViewBuilder
    private func iconRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        subtitleMonospaced: Bool = false,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(alignment: subtitle != nil ? .top : .center, spacing: MuesliTheme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(MuesliTheme.accentSubtle))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MuesliTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, design: subtitleMonospaced ? .monospaced : .default))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(subtitleMonospaced ? 2 : nil)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: MuesliTheme.spacing8)

            control()
        }
        .padding(.vertical, MuesliTheme.spacing8)
    }

    private func openButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(Capsule().fill(MuesliTheme.surfacePrimary))
            .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
