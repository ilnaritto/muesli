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

/// A showcase tile on the Home → Features page: a gently animated illustration,
/// a title + subtitle, and one or two action buttons that deep-link into the
/// relevant setting. Styled like the meeting-page cards (backgroundBase,
/// rounded, hairline border). `compact` renders the smaller 3-per-row variant.
///
/// When there's exactly one action, the whole card is the tap target and
/// highlights on hover — same treatment as the tour banners above it, per
/// live feedback. A card with zero or several actions (no single obvious
/// destination) keeps its own per-action buttons instead.
struct FeatureCard: View {
    let accent: Color
    let icon: String
    let title: String
    let subtitle: String
    let actions: [FeatureAction]
    var compact: Bool = false

    @State private var isHovered = false

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
        .onHover { hovering in
            guard singleAction != nil else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            illustration

            Text(title)
                .font(.system(size: compact ? 14 : 17, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: compact ? 12 : 13, weight: .regular))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineSpacing(2)
                .lineLimit(compact ? 3 : 4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if let singleAction {
                actionLabel(singleAction)
            } else if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        actionButton(action)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity, minHeight: compact ? 150 : 230, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .fill(isHovered ? MuesliTheme.backgroundHover : MuesliTheme.backgroundBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .strokeBorder(isHovered ? accent.opacity(0.55) : MuesliTheme.surfaceBorder, lineWidth: isHovered ? 1.5 : 1)
        )
        .scaleEffect(isHovered ? 1.012 : 1)
    }

    private var illustration: some View {
        FeatureIcon(
            icon: icon,
            accent: accent,
            tileSize: compact ? 40 : 48,
            iconSize: compact ? 18 : 22,
            corner: compact ? 10 : 12
        )
    }

    /// Visual-only chip (not a nested Button) for the single-action case,
    /// since the whole card is already the button.
    @ViewBuilder
    private func actionLabel(_ action: FeatureAction) -> some View {
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
            // Uniform neutral chip: soft, low-key buttons across the whole
            // Features page (no loud accent fills).
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
    /// nil → no tile, just the glyph (used inside the large gradient panel).
    let tileSize: CGFloat?
    let iconSize: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let tileSize {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(accent)
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: tileSize, height: tileSize)
            } else {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
    }
}
