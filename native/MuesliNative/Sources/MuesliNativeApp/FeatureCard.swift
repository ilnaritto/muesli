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

/// Round 5: settings-panel-style card — small looping demo clip up top
/// (per repeated feedback that the page needs to actually show the
/// animations, not just an icon), icon + title + subtitle below, and an
/// optional functional toggle in the corner for features with a real
/// on/off state (permission granted, model connected). Cards without a
/// natural on/off state (Templates, Meeting chat, Insights) have no
/// toggle — they're still single-tap-target navigation cards.
struct FeatureCard: View {
    let accent: Color
    let icon: String
    let title: String
    let subtitle: String
    let actions: [FeatureAction]
    var compact: Bool = false
    /// Looks up `Contents/Resources/features-tour/<name>.gif` — plays on a
    /// continuous loop, no hover gating.
    var previewAssetName: String? = nil
    /// Overrides the default preview strip height — used to give the hero
    /// card (full row width, most important feature) a noticeably bigger
    /// demo than the rest instead of matching the standard card's height.
    var previewHeight: CGFloat? = nil
    /// The single full-width card in a row of important-by-priority cards
    /// gets larger type on top of the taller preview — a bit more visual
    /// weight than just "not compact".
    var isHero: Bool = false
    var toggle: FeatureToggle? = nil

    private var singleAction: FeatureAction? {
        actions.count == 1 ? actions.first : nil
    }

    private var previewURL: URL? {
        guard let previewAssetName else { return nil }
        return Bundle.main.url(forResource: previewAssetName, withExtension: "gif", subdirectory: "features-tour")
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
            if let previewURL {
                LoopingGIFView(url: previewURL)
                    .frame(height: previewHeight ?? (compact ? 72 : 110))
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            } else if !compact {
                // Main-board cards without a demo clip (e.g. "Connect an AI
                // model") used to just skip this slot, leaving them visibly
                // barer than their gif-preview neighbors in the same row —
                // per feedback the board read as "some cards have video,
                // some don't" instead of one cohesive set. This gives every
                // non-compact card the same visual weight up top.
                decorativePreview
            }

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
                .font(.system(size: isHero ? 20 : (compact ? 14 : 16), weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: isHero ? 14 : (compact ? 12 : 13), weight: .regular))
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
        .padding(isHero ? MuesliTheme.spacing24 : MuesliTheme.spacing20)
        .frame(maxWidth: .infinity, minHeight: compact ? 130 : 230, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .fill(MuesliTheme.backgroundBase)
        )
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

    /// Gradient-and-glyph stand-in for the gif slot on non-compact cards
    /// that have no demo clip — same footprint (height, corner radius,
    /// border) as `LoopingGIFView`'s block, so the card reads the same
    /// silhouette as its gif-preview neighbors instead of skipping the slot.
    private var decorativePreview: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.28), accent.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(accent.opacity(0.35))
        }
        .frame(height: previewHeight ?? 110)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
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

/// Continuously-looping GIF, no play/pause state, no hover gating — used
/// for the small demo-clip strip at the top of a feature card. SwiftUI's
/// `Image` never animates GIF frames, only `NSImageView.animates` does.
private struct LoopingGIFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = FixedSizeGIFImageView()
        view.image = NSImage(contentsOf: url)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.animates = true
    }
}

/// `NSImageView`'s default `intrinsicContentSize` matches the loaded
/// image's pixel size, which fights the SwiftUI `.frame` around it inside
/// a `LazyVGrid` cell. Reporting no intrinsic size lets the SwiftUI-provided
/// frame win.
private final class FixedSizeGIFImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
