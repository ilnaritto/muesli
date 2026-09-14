import AppKit
import SwiftUI
import MuesliCore

/// Lightweight Identifiable wrapper so heterogeneous cards can be laid out in
/// a LazyVGrid via ForEach without a shared concrete type.
struct IdentifiedView: View, Identifiable {
    let id = UUID()
    private let content: AnyView
    init<V: View>(_ view: V) { content = AnyView(view) }
    var body: some View { content }
}

/// One action button on a feature card.
struct FeatureAction: Identifiable {
    let id = UUID()
    let label: String
    var systemImage: String? = nil
    var isPrimary: Bool = false
    let action: () -> Void
}

/// A functional on/off control on a feature card — per live feedback, this
/// must actually DO the thing (request the permission, open the connect
/// sheet) right here, not just report status and send the user to Settings.
struct FeatureToggle {
    let isOn: Bool
    let action: () -> Void
}

/// Small icon+title+subtitle utility tile with an optional functional
/// toggle in the corner for features with a real on/off state (permission
/// granted, config boolean). Used for the 2×2 grid of small feature tiles
/// in the mosaic board — the six flagship cards on the same page are their
/// own bespoke views (see `HomeView.swift`'s card primitives) since each
/// shows a different kind of live app data, not a generic subtitle.
struct FeatureCard: View {
    let accent: Color
    let icon: String
    let title: String
    let subtitle: String
    let actions: [FeatureAction]
    var compact: Bool = false
    var toggle: FeatureToggle? = nil

    private var singleAction: FeatureAction? {
        actions.count == 1 ? actions.first : nil
    }

    var body: some View {
        Group {
            if let singleAction {
                Button(action: singleAction.action) { cardBody }
                    .buttonStyle(.plain)
            } else {
                cardBody
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .top, spacing: 10) {
                FeatureIcon(
                    icon: icon,
                    accent: accent,
                    tileSize: compact ? 40 : 44,
                    iconSize: compact ? 18 : 20,
                    corner: compact ? 10 : 12
                )
                Spacer(minLength: 0)
                if let toggle {
                    // A real toggle — tapping it fires the request/connect
                    // action directly, right here, not a status readout.
                    Toggle("", isOn: Binding(get: { toggle.isOn }, set: { _ in toggle.action() }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(MuesliTheme.accent)
                        .labelsHidden()
                }
            }

            Text(title)
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: compact ? 12 : 13, weight: .regular))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineSpacing(2)
                .lineLimit(compact ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if actions.count > 1 {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        actionButton(action)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(MuesliTheme.spacing20)
        .frame(maxWidth: .infinity, minHeight: compact ? 130 : 230, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .fill(MuesliTheme.backgroundBase)
        )
        // Nothing else in this view clips — when a parent gives the card
        // less room than its content needs (e.g. a narrow windowed-mode
        // column), unclipped content doesn't shrink or truncate, it spills
        // past the rounded-rect border and overlaps the next card in the
        // row. This caps it: worst case content is cut off inside its own
        // card, it never bleeds into a neighbor.
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL))
        .overlay(
            // A soft accent outline when the toggle is on — a card being
            // active should read at a glance, not only from the small
            // switch in the corner.
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .strokeBorder(
                    toggle?.isOn == true ? MuesliTheme.accent.opacity(0.5) : MuesliTheme.surfaceBorder,
                    lineWidth: toggle?.isOn == true ? 1.5 : 1
                )
        )
    }

    @ViewBuilder
    private func actionButton(_ action: FeatureAction) -> some View {
        Button(action: action.action) {
            HStack(spacing: 5) {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(action.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(MuesliTheme.backgroundBase))
            .overlay(Capsule().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// SF Symbol on an accent tile — static illustration for feature cards.
private struct FeatureIcon: View {
    let icon: String
    let accent: Color
    let tileSize: CGFloat
    let iconSize: CGFloat
    let corner: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(accent)
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: tileSize, height: tileSize)
    }
}
