import SwiftUI
import MuesliCore

/// One tab inside a `CapsuleTabBarContainer`: text with an accent underline
/// when selected. Shared by the meeting-page template tabs and the Models
/// role tabs so both read as the same visual language.
struct CapsuleTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Text is vertically centered in the row; the underline hugs the
            // bottom edge regardless of the row height.
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 2,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 2
                    )
                    .fill(isSelected ? MuesliTheme.accent : Color.clear)
                    .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The capsule chrome around a row of `CapsuleTab`s: horizontal scroll,
/// `backgroundBase` fill and hairline border, with an optional gearshape
/// pinned to the trailing edge (behind a fade gradient so scrolled-under
/// tabs dim out instead of clipping abruptly).
struct CapsuleTabBarContainer<Tabs: View, TrailingAccessory: View>: View {
    var gearAction: (() -> Void)? = nil
    var gearHelp: String = ""
    @ViewBuilder var tabs: () -> Tabs
    @ViewBuilder var trailingAccessory: () -> TrailingAccessory

    init(
        gearAction: (() -> Void)? = nil,
        gearHelp: String = "",
        @ViewBuilder tabs: @escaping () -> Tabs,
        @ViewBuilder trailingAccessory: @escaping () -> TrailingAccessory = { EmptyView() }
    ) {
        self.gearAction = gearAction
        self.gearHelp = gearHelp
        self.tabs = tabs
        self.trailingAccessory = trailingAccessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: MuesliTheme.spacing16) {
                    tabs()
                }
                .padding(.leading, 20)
                .padding(.trailing, gearAction != nil ? 70 : 20)
                .frame(height: 40)
            }

            trailingAccessory()
        }
        .frame(height: 40)
        .background(Capsule().fill(MuesliTheme.backgroundBase))
        .overlay(alignment: .trailing) {
            if let gearAction {
                CapsuleGearOverlay(action: gearAction, help: gearHelp)
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
    }
}

/// Fixed gear pinned inside the right edge of a tabs capsule.
private struct CapsuleGearOverlay: View {
    let action: () -> Void
    let help: String

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: MuesliTheme.backgroundBase.opacity(0), location: 0),
                    .init(color: MuesliTheme.backgroundBase, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 24)
            .allowsHitTesting(false)

            Button(action: action) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    // 40pt zone flush with the capsule edge: the glyph center
                    // lands 20pt from the right, on the same vertical axis as
                    // the "⋯" chip above.
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(MuesliTheme.backgroundBase)
            .help(help)
        }
        .frame(height: 40)
    }
}
