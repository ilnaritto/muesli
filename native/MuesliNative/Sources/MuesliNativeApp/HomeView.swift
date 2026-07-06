import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import TelemetryDeck
import MuesliCore

/// Home tab: overview dashboard and app features. Hosts the usage stats moved
/// from the Dictations page; richer analytics blocks land here later.
struct HomeView: View {
    private enum HomeSection: String, CaseIterable, Identifiable {
        case overview
        case functions

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return tr("Overview", "Обзор")
            case .functions: return tr("Features", "Функции")
            }
        }

        var icon: String {
            switch self {
            case .overview: return "chart.bar.xaxis"
            case .functions: return "puzzlepiece.extension"
            }
        }
    }

    let appState: AppState
    let controller: MuesliController
    @State private var selectedSection: HomeSection = .overview
    @State private var bridgePromptSeen = false
    @State private var isBridgeQRCodePresented = false

    var body: some View {
        HStack(spacing: 5) {
            PrimaryColumn(appState: appState, title: tr("Home", "Главная")) {
                sectionList
            }

            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $isBridgeQRCodePresented) {
            IPhoneBridgeQRCodeSheet(
                deepLinkURL: IPhoneBridgeLinks.iOSSyncDeepLinkURL,
                installURL: IPhoneBridgeLinks.installURL
            )
        }
    }

    @ViewBuilder
    private var sectionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(HomeSection.allCases) { section in
                    sectionRow(section)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, MuesliTheme.spacing12)
        }
    }

    private func sectionRow(_ section: HomeSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: MuesliTheme.spacing12) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textSecondary)
                    .frame(width: 20)
                Text(section.title)
                    .font(MuesliTheme.callout())
                    .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            overviewContent
        case .functions:
            functionsContent
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                Text(tr("Overview", "Обзор"))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                StatsHeaderView(
                    dictationStats: appState.dictationStats,
                    meetingStats: appState.meetingStats
                )

                Text(tr("Detailed analytics will appear here.", "Здесь появится подробная аналитика."))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .padding(MuesliTheme.spacing32)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var functionsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                Text(tr("Features", "Функции"))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                iPhoneBridgeCard
                    .frame(maxWidth: 520, alignment: .leading)
            }
            .padding(MuesliTheme.spacing32)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - iPhone bridge (moved from the Dictations page)

    private var bridgeState: ICloudBridgeState {
        appState.iCloudBridgeState
    }

    private var iPhoneBridgeCard: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing8) {
                BridgeSyncIcon(
                    systemName: bridgeIcon,
                    isAnimating: bridgeSyncIconIsAnimating,
                    font: .system(size: 15, weight: .semibold)
                )
                    .foregroundStyle(bridgeIconColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bridgeTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(bridgeSubtitle)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: MuesliTheme.spacing8) {
                Button {
                    bridgePrimaryAction()
                } label: {
                    HStack(spacing: 6) {
                        Text(bridgeButtonTitle)
                            .lineLimit(1)
                        BridgeSyncIcon(
                            systemName: bridgeButtonIcon,
                            isAnimating: bridgeButtonIconIsAnimating,
                            font: .system(size: 11, weight: .semibold)
                        )
                    }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(MuesliTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)
                .disabled(bridgeActionDisabled)
                .help(bridgeButtonHelp)

                if shouldShowBridgeHandoffButton {
                    Button {
                        isBridgeQRCodePresented = true
                        TelemetryDeck.signal("bridge_qr_shown", parameters: ["platform": "macos"])
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .frame(width: 26, height: 26)
                            .background(MuesliTheme.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    .buttonStyle(.plain)
                    .help(tr("Show iPhone setup QR", "Показать QR для настройки iPhone"))
                }

                Spacer(minLength: 0)
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .onAppear {
            guard !bridgePromptSeen else { return }
            bridgePromptSeen = true
            TelemetryDeck.signal("bridge_prompt_seen", parameters: ["platform": "macos"])
        }
    }

    private var shouldShowBridgeHandoffButton: Bool {
        guard appState.config.iCloudSyncEnabled else { return false }
        switch bridgeState {
        case .needsICloud, .error:
            return false
        case .active:
            return appState.iCloudBridgeCompanionDeviceName == nil
        case .notConfigured, .checkingICloud, .syncing:
            return false
        }
    }

    private var bridgeSyncIconIsAnimating: Bool {
        isBridgeSyncWorking && bridgeIcon == "arrow.triangle.2.circlepath"
    }

    private var bridgeButtonIconIsAnimating: Bool {
        isBridgeSyncWorking && bridgeButtonIcon == "arrow.triangle.2.circlepath"
    }

    private var isBridgeSyncWorking: Bool {
        bridgeState == .checkingICloud || bridgeState == .syncing
    }

    private var bridgeIcon: String {
        switch bridgeState {
        case .active:
            return "checkmark.icloud"
        case .checkingICloud, .syncing:
            return "arrow.triangle.2.circlepath"
        case .needsICloud, .error:
            return "exclamationmark.icloud"
        case .notConfigured:
            return "iphone.gen3"
        }
    }

    private var bridgeIconColor: Color {
        switch bridgeState {
        case .active:
            return MuesliTheme.success
        case .needsICloud, .error:
            return MuesliTheme.transcribing
        default:
            return MuesliTheme.accent
        }
    }

    private var bridgeTitle: String {
        switch bridgeState {
        case .active:
            guard let deviceName = appState.iCloudBridgeCompanionDeviceName else {
                if let lastSyncedAt = appState.iCloudLastSyncedAt {
                    return tr("iCloud sync active · \(relativeSyncTime(lastSyncedAt))", "Синхронизация iCloud активна · \(relativeSyncTime(lastSyncedAt))")
                }
                return tr("iCloud sync active", "Синхронизация iCloud активна")
            }
            if let lastSyncedAt = appState.iCloudLastSyncedAt {
                return tr("Synced with \(deviceName) · \(relativeSyncTime(lastSyncedAt))", "Синхронизировано с \(deviceName) · \(relativeSyncTime(lastSyncedAt))")
            }
            return tr("Synced with \(deviceName)", "Синхронизировано с \(deviceName)")
        case .checkingICloud, .syncing:
            return tr("Setting up private iCloud sync", "Настройка приватной синхронизации iCloud")
        case .needsICloud:
            return tr("Sign in to iCloud to sync", "Войдите в iCloud для синхронизации")
        case .error:
            return tr("iPhone sync needs attention", "Синхронизация с iPhone требует внимания")
        case .notConfigured:
            return tr("Use Muesli on iPhone", "Используйте Muesli на iPhone")
        }
    }

    private var bridgeSubtitle: String {
        switch bridgeState {
        case .active:
            if let deviceName = appState.iCloudBridgeCompanionDeviceName {
                return tr("Private iCloud text sync is on with \(deviceName). Audio stays local.", "Приватная синхронизация текста через iCloud включена с \(deviceName). Аудио остаётся на устройстве.")
            }
            return tr("Scan the QR code to connect your iPhone. Audio stays local.", "Отсканируйте QR-код, чтобы подключить iPhone. Аудио остаётся на устройстве.")
        case .checkingICloud:
            return tr("Checking this Mac's iCloud account...", "Проверка учётной записи iCloud на этом Mac...")
        case .syncing:
            return tr("Creating the sync channel and pulling your latest text records.", "Создание канала синхронизации и загрузка последних текстовых записей.")
        case .needsICloud, .error:
            return appState.iCloudBridgeMessage ?? tr("Open iCloud settings, then try again.", "Откройте настройки iCloud и повторите попытку.")
        case .notConfigured:
            return tr("Your Muesli history follows you through private iCloud. Audio stays local.", "История Muesli следует за вами через приватный iCloud. Аудио остаётся на устройстве.")
        }
    }

    private var bridgeButtonTitle: String {
        switch bridgeState {
        case .active:
            return tr("Sync", "Синхронизировать")
        case .checkingICloud, .syncing:
            return tr("Syncing", "Синхронизация")
        case .needsICloud, .error:
            return tr("Try again", "Повторить")
        case .notConfigured:
            return tr("Set up private iCloud sync", "Настроить синхронизацию iCloud")
        }
    }

    private var bridgeButtonIcon: String {
        switch bridgeState {
        case .notConfigured:
            return "icloud"
        default:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var bridgeActionDisabled: Bool {
        bridgeState == .checkingICloud || bridgeState == .syncing
    }

    private var bridgeButtonHelp: String {
        switch bridgeState {
        case .active:
            return tr("Sync text with iCloud", "Синхронизировать текст через iCloud")
        case .checkingICloud, .syncing:
            return tr("Sync setup is in progress", "Идёт настройка синхронизации")
        default:
            return tr("Set up private iCloud text sync", "Настроить приватную синхронизацию текста через iCloud")
        }
    }

    private func bridgePrimaryAction() {
        switch bridgeState {
        case .active:
            controller.performICloudSync()
        case .checkingICloud, .syncing:
            break
        default:
            controller.enableIPhoneBridgeSync()
        }
    }

    private func relativeSyncTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct BridgeSyncIcon: View {
    let systemName: String
    let isAnimating: Bool
    let font: Font
    @State private var rotationDegrees = 0.0

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .symbolRenderingMode(.hierarchical)
            .rotationEffect(.degrees(rotationDegrees))
            .onAppear {
                updateRotation(animated: false)
            }
            .onChange(of: isAnimating) { _, _ in
                updateRotation(animated: true)
            }
    }

    private func updateRotation(animated: Bool) {
        guard isAnimating else {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    rotationDegrees = 0
                }
            } else {
                rotationDegrees = 0
            }
            return
        }

        rotationDegrees = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rotationDegrees = 360
        }
    }
}

private struct IPhoneBridgeQRCodeSheet: View {
    let deepLinkURL: URL
    let installURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var didCopySetupLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    Text(tr("Open Muesli on iPhone", "Откройте Muesli на iPhone"))
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(tr("Scan this after installing the iPhone app. The QR only opens setup; private iCloud does the actual sync.", "Отсканируйте после установки приложения на iPhone. QR-код только открывает настройку; синхронизацию выполняет приватный iCloud."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: MuesliTheme.spacing16) {
                QRCodeImage(payload: deepLinkURL.absoluteString)
                    .frame(width: 148, height: 148)
                    .padding(MuesliTheme.spacing8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    Label(tr("Same iCloud account", "Одна учётная запись iCloud"), systemImage: "icloud")
                    Label(tr("Text sync only", "Синхронизация только текста"), systemImage: "text.badge.checkmark")
                    Label(tr("Audio stays local", "Аудио остаётся на устройстве"), systemImage: "lock")
                }
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
            }

            HStack(spacing: MuesliTheme.spacing8) {
                Button(tr("Open iPhone app page", "Открыть страницу приложения для iPhone")) {
                    NSWorkspace.shared.open(installURL)
                }
                .buttonStyle(.bordered)

                Button(didCopySetupLink ? tr("Copied!", "Скопировано!") : tr("Copy setup link", "Копировать ссылку настройки")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(deepLinkURL.absoluteString, forType: .string)
                    didCopySetupLink = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1500))
                        didCopySetupLink = false
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(MuesliTheme.spacing20)
        .frame(width: 430)
        .background(MuesliTheme.backgroundBase)
    }
}

private struct QRCodeImage: View {
    let payload: String
    @State private var cachedImage: NSImage?

    var body: some View {
        Group {
            if let image = cachedImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        }
        .accessibilityLabel(tr("iPhone sync setup QR code", "QR-код настройки синхронизации iPhone"))
        .onAppear {
            if cachedImage == nil {
                cachedImage = makeQRCodeImage(payload: payload)
            }
        }
    }

    private func makeQRCodeImage(payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else {
            return nil
        }

        let representation = NSCIImageRep(ciImage: outputImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
