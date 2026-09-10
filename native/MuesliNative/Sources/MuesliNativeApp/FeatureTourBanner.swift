import AppKit
import SwiftUI
import MuesliCore

/// Round 3 redesign: presentational image banner for a flagship feature —
/// per Ilnar's reference (a "recommended tools" board: image-first cards,
/// caption baked in or overlaid, no hover state, whole card is the tap
/// target). Replaces the earlier hover-to-preview GIF-demo card — the demo
/// interaction read as "boring"/needed rework once compared against a real
/// reference; a static, larger banner reads as more presentational.
/// `assetName` looks up `Contents/Resources/features-tour/<assetName>-cover.png`
/// in the bundle (copied there by `scripts/build_native_app.sh`). No cover
/// yet → a plain accent-gradient tile with the feature's own glyph fills the
/// same slot, so the card still has visual weight either way.
struct FeatureTourBanner: View {
    let assetName: String
    let icon: String
    let accent: Color
    let title: String
    let description: String
    let action: FeatureAction?

    private var coverAssetURL: URL? {
        Bundle.main.url(forResource: "\(assetName)-cover", withExtension: "png", subdirectory: "features-tour")
    }

    /// Covers are sized to fill the banner (`.fill`, then clipped) rather
    /// than letterboxed — unlike the old hover-demo card, this is now a
    /// pure image banner with no separate text block competing for height.
    private var coverAspectRatio: CGFloat {
        guard let url = coverAssetURL, let size = NSImage(contentsOf: url)?.size, size.height > 0 else {
            return 16.0 / 9.0
        }
        return size.width / size.height
    }

    var body: some View {
        Button {
            action?.action()
        } label: {
            ZStack(alignment: .bottomLeading) {
                illustration

                // Cover art already bakes the feature name into the image
                // (see the earlier title-card work) — only the description
                // needs an overlay caption, on a scrim so it stays legible
                // over any artwork. The placeholder (no cover yet) has no
                // baked-in text, so it needs the title here too.
                LinearGradient(
                    colors: [.black.opacity(0.62), .black.opacity(0)],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 2) {
                    if coverAssetURL == nil {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(description)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, minHeight: 175, maxHeight: .infinity)
            .background(MuesliTheme.backgroundBase)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    @ViewBuilder
    private var illustration: some View {
        if let coverURL = coverAssetURL, let cover = NSImage(contentsOf: coverURL) {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(coverAspectRatio, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            LinearGradient(
                colors: [accent.opacity(0.5), accent.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            )
        }
    }
}
