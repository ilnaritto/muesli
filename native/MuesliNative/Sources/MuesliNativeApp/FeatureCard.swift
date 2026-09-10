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

/// Round 3 redesign: the secondary/minor features are small icon tiles —
/// icon, title, one-line subtitle, no image, no hover effects — per Ilnar's
/// reference board (large presentational banners for the flagship features
/// above, small plain tiles for everything else). `compact` is the only
/// variant actually used today (the Home → Features "minor items" grid);
/// kept as a flag rather than deleted in case a larger single-action card
/// is needed elsewhere later.
///
/// When there's exactly one action, the whole card is the tap target (no
/// separate button chip, matching the reference's plain clickable tiles).
/// A card with zero or several actions keeps its own per-action buttons.
struct FeatureCard: View {
    let accent: Color
    let icon: String
    let title: String
    let subtitle: String
    let actions: [FeatureAction]
    var compact: Bool = false

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
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            FeatureIcon(
                icon: icon,
                accent: accent,
                tileSize: compact ? 40 : 48,
                iconSize: compact ? 18 : 22,
                corner: compact ? 10 : 12
            )

            Text(title)
                .font(.system(size: compact ? 14 : 17, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: compact ? 12 : 13, weight: .regular))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineSpacing(2)
                .lineLimit(compact ? 2 : 4)
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
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity, minHeight: compact ? 130 : 230, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .fill(MuesliTheme.backgroundBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
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
