import SwiftUI
import MuesliCore

struct AboutView: View {
    let appState: AppState

    private let githubURL = "https://github.com/Muesli-HQ/muesli"
    private let donateURL = "https://buymeacoffee.com/phequals7"

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
                Text(tr("About", "О приложении"))
                    .font(MuesliTheme.pageTitle())
                    .foregroundStyle(MuesliTheme.textPrimary)

                if let banner = updateBanner {
                    updateBannerView(banner)
                }

                // MARK: - App Info
                sectionHeader(tr("App Info", "Сведения о приложении"))
                aboutCard {
                    aboutRow(tr("Version", "Версия")) {
                        Text(version)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    aboutRow(tr("Updates", "Обновления")) {
                        Text(updateRowGuidance)
                            .font(MuesliTheme.callout())
                            .foregroundStyle(MuesliTheme.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // MARK: - Support
                sectionHeader(tr("Support", "Поддержка"))
                aboutCard {
                    aboutRow(tr("Support Development", "Поддержать разработку")) {
                        Button {
                            if let url = URL(string: donateURL) { NSWorkspace.shared.open(url) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 12))
                                Text(tr("Donate", "Пожертвовать"))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, MuesliTheme.spacing20)
                            .padding(.vertical, MuesliTheme.spacing8)
                            .background(MuesliTheme.success)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    aboutRow(tr("Source Code", "Исходный код")) {
                        actionButton(tr("View on GitHub", "Открыть на GitHub"), icon: "arrow.up.right.square") {
                            if let url = URL(string: githubURL) { NSWorkspace.shared.open(url) }
                        }
                    }
                }

                // MARK: - Data
                sectionHeader(tr("Data", "Данные"))
                aboutCard {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        Text(tr("App Data Directory", "Папка данных приложения"))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        HStack {
                            Text(appDataPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            actionButton(tr("Open", "Открыть"), icon: "folder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDataPath)
                            }
                        }
                    }
                }

                // MARK: - Acknowledgements
                sectionHeader(tr("Acknowledgements", "Благодарности"))
                aboutCard {
                    acknowledgement(
                        name: "FluidAudio by FluidInference",
                        description: tr("CoreML speech stack powering Parakeet, Qwen3 ASR, Silero VAD, and speaker diarization on Apple Silicon.", "Речевой стек CoreML, обеспечивающий работу Parakeet, Qwen3 ASR, Silero VAD и диаризации говорящих на Apple Silicon.")
                    )
                    Divider().background(MuesliTheme.surfaceBorder)
                    acknowledgement(
                        name: "LocalVQE by localai-org",
                        description: tr("On-device acoustic echo cancellation powering cleaner meeting transcription.", "Акустическое эхоподавление на устройстве для более чистой транскрипции встреч.")
                    )
                    Divider().background(MuesliTheme.surfaceBorder)
                    acknowledgement(
                        name: "WhisperKit by Argmax",
                        description: tr("Swift Whisper inference on CoreML/ANE powering the app's Whisper Small, Medium, and Large Turbo backends.", "Инференс Whisper на Swift через CoreML/ANE, обеспечивающий работу бэкендов Whisper Small, Medium и Large Turbo.")
                    )
                }

                Spacer(minLength: MuesliTheme.spacing32)
            }
            .padding(MuesliTheme.spacing32)
        }
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

    @ViewBuilder
    private func aboutRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
            Spacer()
            control()
        }
        .padding(.vertical, MuesliTheme.spacing8)
    }

    @ViewBuilder
    private func acknowledgement(name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
            Text(description)
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MuesliTheme.spacing8)
    }

    @ViewBuilder
    private func actionButton(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
