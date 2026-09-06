import AppKit
import SwiftUI
import MuesliCore

/// Task 5: onboarding-style card for the Features tour — one per flagship
/// feature, illustration on top + title + description + one action, laid
/// out 3-per-row (per live feedback — a single full-width banner per row
/// needed too much scrolling). `assetName` looks up
/// `Contents/Resources/features-tour/<assetName>.gif` (preferred) or
/// `.png` in the bundle (copied there by `scripts/build_native_app.sh`,
/// matching the `about-hero.jpg` pattern). Real screenshots/GIFs aren't
/// wired up yet — until they are, a gradient tile with the feature's own
/// glyph fills the same slot, so the card still has visual weight instead
/// of reading as a bare text block.
///
/// The whole card is the tap target (not just a small button inside it),
/// and hovering highlights it — a GIF asset plays only while hovered and
/// sits on its first frame otherwise, per live feedback.
struct FeatureTourBanner: View {
    let assetName: String
    let icon: String
    let accent: Color
    let title: String
    let description: String
    let action: FeatureAction?

    @State private var isHovered = false

    private var tourAssetURL: URL? {
        Bundle.main.url(forResource: assetName, withExtension: "gif", subdirectory: "features-tour")
            ?? Bundle.main.url(forResource: assetName, withExtension: "png", subdirectory: "features-tour")
    }

    /// Resting-state cover, `<assetName>-cover.png` — a crisp, non-animated
    /// title card shown whenever the card isn't hovered. Kept as a separate
    /// asset (not the GIF's first frame) for two reasons: a GIF re-encoded
    /// without a custom palette (this build's `paletteuse` filter crashes)
    /// carries visible dithering noise that makes text hard to read, and
    /// `NSImageView.animates = false` freezes on whatever frame was already
    /// playing rather than resetting to frame 0 — so the GIF alone can't
    /// reliably show a clean "front cover" on mouse-out. A real SwiftUI
    /// `Image` swap has neither problem.
    private var coverAssetURL: URL? {
        Bundle.main.url(forResource: "\(assetName)-cover", withExtension: "png", subdirectory: "features-tour")
    }

    /// The illustration box is sized to the asset's own aspect ratio (via
    /// `.aspectRatio(_:contentMode: .fit)` below) rather than a fixed height,
    /// so it hugs the image exactly instead of leaving letterbox bars when
    /// an asset's proportions don't match a guessed fixed height.
    private var assetAspectRatio: CGFloat {
        guard let url = tourAssetURL, let size = NSImage(contentsOf: url)?.size, size.height > 0 else {
            return 3.0
        }
        return size.width / size.height
    }

    var body: some View {
        Button {
            action?.action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                illustration

                // The cover image already carries the feature name — repeating
                // it as a second text line under the illustration read as
                // duplicated content, per live feedback. Cards without a
                // cover (no real asset recorded yet) still need the title
                // here, since their placeholder illustration has no text.
                if coverAssetURL == nil {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Compensates for the missing title line above so the
                    // card's own internal rhythm still feels balanced, not
                    // cramped right under the illustration.
                    .padding(.top, coverAssetURL != nil ? 6 : 0)

                Spacer(minLength: 0)

                if let action {
                    tourActionLabel(action)
                }
            }
            .padding(MuesliTheme.spacing12)
            .frame(maxWidth: .infinity, minHeight: 195, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                    .fill(isHovered ? MuesliTheme.backgroundHover : MuesliTheme.backgroundBase)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                    .strokeBorder(isHovered ? accent.opacity(0.55) : MuesliTheme.surfaceBorder, lineWidth: isHovered ? 1.5 : 1)
            )
            .scaleEffect(isHovered ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var illustration: some View {
        if !isHovered, let coverURL = coverAssetURL, let cover = NSImage(contentsOf: coverURL) {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(assetAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        } else if let url = tourAssetURL, url.pathExtension.lowercased() == "gif" {
            AnimatedImageView(url: url, animates: isHovered)
                .aspectRatio(assetAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        } else if let url = tourAssetURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(assetAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        } else {
            // Placeholder until a real screenshot/GIF exists for this
            // feature — a gradient tile with the feature's own glyph, so
            // the card keeps its visual weight either way. The glyph
            // nudges up slightly on hover, echoing the "press me" cue a
            // real GIF would give once one exists.
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(isHovered ? 0.45 : 0.35), accent.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accent)
                    .scaleEffect(isHovered ? 1.08 : 1)
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func tourActionLabel(_ action: FeatureAction) -> some View {
        HStack(spacing: 5) {
            if let systemImage = action.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(action.label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, MuesliTheme.spacing8)
        .background(Capsule().fill(accent.opacity(0.82)))
    }
}

/// GIF playback bridge: SwiftUI's `Image` never animates a GIF's frames —
/// only `NSImageView.animates` does. Hover controls play/pause; the view
/// sits on the first frame when not hovered instead of looping constantly.
/// Internal (not `private`) so `FeatureCard` can reuse it for the same
/// cover/GIF illustration pattern on the compact grid below.
struct AnimatedImageView: NSViewRepresentable {
    let url: URL
    let animates: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = FixedSizeImageView()
        view.image = NSImage(contentsOf: url)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = animates
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.animates = animates
    }
}

/// `NSImageView`'s default `intrinsicContentSize` matches the loaded image's
/// pixel size, which fights the SwiftUI `.frame` around it inside a
/// `LazyVGrid` cell and blows the card out over its neighbors. Reporting no
/// intrinsic size lets the SwiftUI-provided frame win.
final class FixedSizeImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
