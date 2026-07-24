import SwiftUI
import MuesliCore

/// Shared scaffold for the leftmost column of every tab: a fixed-width pane
/// with a traffic-light header zone on top and the bottom tab bar pinned below.
struct PrimaryColumn<Content: View, Leading: View, Trailing: View>: View {
    static var columnWidth: CGFloat { 320 }
    static var headerZoneHeight: CGFloat { 44 }
    static var cardCornerRadius: CGFloat { 23 }
    /// Horizontal room reserved on the left of the header for the macOS
    /// traffic-light window buttons, so leading accessories clear them.
    static var trafficLightInset: CGFloat { 76 }

    let appState: AppState
    let title: String
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(
        appState: AppState,
        title: String,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.appState = appState
        self.title = title
        self.leading = leading
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            headerZone

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            modelPreparationStatus

            BottomTabBar(appState: appState)
        }
        .frame(width: Self.columnWidth)
        .background(MuesliTheme.backgroundBase)
        .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        // The window-level container only insets horizontally now,
        // so the card keeps its own gap from the top and bottom edges.
        .padding(.vertical, 8)
    }

    private var headerZone: some View {
        ZStack {
            // Tab title, vertically aligned with the traffic lights on the left.
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(1)

            // Leading accessories sit just right of the traffic-light buttons.
            HStack(spacing: MuesliTheme.spacing4) {
                leading()
                Spacer()
            }
            .padding(.leading, Self.trafficLightInset)

            HStack(spacing: MuesliTheme.spacing4) {
                Spacer()
                trailing()
            }
            .padding(.trailing, 10)
        }
        .frame(height: Self.headerZoneHeight)
    }

    @ViewBuilder
    private var modelPreparationStatus: some View {
        if let title = appState.modelPreparationTitle {
            HStack(spacing: MuesliTheme.spacing8) {
                Group {
                    if appState.modelPreparationIsComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MuesliTheme.success)
                    } else if appState.isModelPreparingAfterDownload || appState.modelPreparationProgress == nil {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        ProgressView(value: appState.modelPreparationProgress ?? 0, total: 1)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    }
                }
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 6)
            .help([title, appState.modelPreparationDetail].compactMap { $0 }.joined(separator: " — "))
        }
    }
}

extension PrimaryColumn where Leading == EmptyView, Trailing == EmptyView {
    init(
        appState: AppState,
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(appState: appState, title: title, leading: { EmptyView() }, content: content, trailing: { EmptyView() })
    }
}

extension PrimaryColumn where Leading == EmptyView {
    init(
        appState: AppState,
        title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(appState: appState, title: title, leading: { EmptyView() }, content: content, trailing: trailing)
    }
}

/// Telegram-style icon-only tab strip pinned to the bottom of the primary column.
struct BottomTabBar: View {
    let appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(MuesliTheme.surfaceBorder.opacity(0.7))
                .frame(height: 1)

            HStack(spacing: 0) {
                tabButton(tab: .home, icon: "house.fill", label: tr("Home", "Главная"))
                tabButton(tab: .dictations, icon: "mic.fill", label: tr("Dictations", "Диктовки"))
                tabButton(tab: .meetings, icon: "person.2.fill", label: tr("Meetings", "Встречи"))
                tabButton(tab: .settings, icon: "gearshape.fill", label: tr("Settings", "Настройки"), showsUpdateBadge: hasPendingUpdate)
            }
            .frame(height: 50)
        }
    }

    private var hasPendingUpdate: Bool {
        switch appState.sparkleUpdateStatus {
        case .available, .downloaded:
            return true
        case .idle, .checking, .busy, .installing, .upToDate, .disabled, .failed:
            return false
        }
    }

    private func tabButton(tab: DashboardTab, icon: String, label: String, showsUpdateBadge: Bool = false) -> some View {
        let isSelected = appState.selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectedTab = tab
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    if showsUpdateBadge {
                        Circle()
                            .fill(MuesliTheme.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: -18, y: 8)
                            .accessibilityLabel(tr("Update available", "Доступно обновление"))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
