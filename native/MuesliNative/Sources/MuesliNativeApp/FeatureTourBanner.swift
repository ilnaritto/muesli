import SwiftUI
import MuesliCore

/// Task 5: onboarding-style card for the Features tour — one per flagship
/// feature, illustration on top + title + description + one action button,
/// laid out 3-per-row (per live feedback — a single full-width banner per
/// row needed too much scrolling). `assetName` looks up
/// `Contents/Resources/features-tour/<assetName>.png` in the bundle (copied
/// there by `scripts/build_native_app.sh`, matching the `about-hero.jpg`
/// pattern). Real screenshots/GIFs aren't wired up yet — until they are, a
/// gradient tile with the feature's own glyph fills the same slot, so the
/// card still has visual weight instead of reading as a bare text block.
struct FeatureTourBanner: View {
    let assetName: String
    let icon: String
    let accent: Color
    let title: String
    let description: String
    let action: FeatureAction?

    private var tourImage: NSImage? {
        guard let url = Bundle.main.url(
            forResource: assetName,
            withExtension: "png",
            subdirectory: "features-tour"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            illustration

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineSpacing(2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if let action {
                tourActionButton(action)
            }
        }
        .padding(MuesliTheme.spacing12)
        .frame(maxWidth: .infinity, minHeight: 230, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge).fill(MuesliTheme.backgroundBase))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var illustration: some View {
        if let tourImage {
            Image(nsImage: tourImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        } else {
            // Placeholder until a real screenshot/GIF exists for this
            // feature — a gradient tile with the feature's own glyph, so
            // the card keeps its visual weight either way.
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(0.35), accent.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accent)
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
    private func tourActionButton(_ action: FeatureAction) -> some View {
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(Capsule().fill(MuesliTheme.accent))
        }
        .buttonStyle(.plain)
    }
}
