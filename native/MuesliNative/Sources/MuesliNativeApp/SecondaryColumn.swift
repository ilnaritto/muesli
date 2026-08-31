import SwiftUI
import MuesliCore

/// Shared scaffold for a second, narrower navigation column placed next to
/// `PrimaryColumn` — used for role/category pickers embedded inside a
/// section (meeting templates, model roles). Matches `PrimaryColumn`'s
/// visual rhythm — height, corner radius, vertical window margins, centered
/// header zone — but has no bottom tab bar of its own.
struct SecondaryColumn<Content: View>: View {
    static var cardCornerRadius: CGFloat { 23 }
    static var headerZoneHeight: CGFloat { 44 }

    let title: String
    var width: CGFloat = 260
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            headerZone

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(MuesliTheme.backgroundBase)
        .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .padding(.vertical, 8)
    }

    private var headerZone: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MuesliTheme.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: Self.headerZoneHeight)
    }
}

/// Row for `SecondaryColumn`: a square rounded icon tile in one fixed tint
/// (the glyph carries the distinction, not the tile color — unlike
/// `SidebarNavRow`'s per-section colors), a title, and an optional trailing
/// accessory (e.g. an enable toggle).
struct SecondaryColumnRow<Trailing: View>: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var tileColor: Color = MuesliTheme.accent
    var showsEditedMark: Bool = false
    var isDimmed: Bool = false
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    var body: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Button(action: action) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.white : tileColor)
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? tileColor : .white)
                    }
                    .frame(width: 23, height: 23)

                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(isSelected ? .white : MuesliTheme.textPrimary)
                        .lineLimit(1)

                    if showsEditedMark {
                        Circle()
                            .fill(isSelected ? Color.white : MuesliTheme.accent)
                            .frame(width: 5, height: 5)
                            .help(tr("Edited", "Изменён"))
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium, style: .continuous)
                .fill(isSelected ? MuesliTheme.accent : Color.clear)
        )
        .opacity(isDimmed ? 0.55 : 1)
    }
}

extension SecondaryColumnRow where Trailing == EmptyView {
    init(
        icon: String,
        title: String,
        isSelected: Bool,
        tileColor: Color = MuesliTheme.accent,
        showsEditedMark: Bool = false,
        isDimmed: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.isSelected = isSelected
        self.tileColor = tileColor
        self.showsEditedMark = showsEditedMark
        self.isDimmed = isDimmed
        self.trailing = { EmptyView() }
        self.action = action
    }
}
