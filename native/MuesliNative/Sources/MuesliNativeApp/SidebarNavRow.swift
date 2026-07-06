import SwiftUI
import MuesliCore

/// Telegram-style sidebar row: a colored rounded icon tile, a title, and a
/// full-width rounded highlight on selection (the meeting-tab selection color).
/// When selected the tile inverts — white background, glyph in the pane color —
/// so the icon reads as cut out. Shared by the Settings and Home left menus.
struct SidebarNavRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.white : iconColor)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? iconColor : .white)
                }
                .frame(width: 23, height: 23)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? .white : MuesliTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium, style: .continuous)
                    .fill(isSelected ? MuesliTheme.accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
