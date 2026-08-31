import SwiftUI
import MuesliCore

/// Task 5: full-width onboarding-style banner for the Features tour — one
/// per flagship feature, illustration + description + one action, replacing
/// the grid-of-cards showcase for the first-run path. `assetName` looks up
/// `Contents/Resources/features-tour/<assetName>.png` in the bundle (copied
/// there by `scripts/build_native_app.sh`, matching the `about-hero.jpg`
/// pattern). Real screenshots/GIFs aren't wired up yet — until they are, a
/// gradient tile with the feature's own glyph fills the same slot, so the
/// banner still has visual weight instead of reading as a bare text bar.
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
        HStack(alignment: .center, spacing: MuesliTheme.spacing20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let action {
                    tourActionButton(action)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            illustration
        }
        .padding(.horizontal, MuesliTheme.spacing20)
        .padding(.vertical, MuesliTheme.spacing16)
        .frame(maxWidth: 1100, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
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
                .frame(width: 220, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
                .fixedSize()
        } else {
            // Placeholder until a real screenshot/GIF exists for this
            // feature — a gradient tile with the feature's own glyph, so
            // the banner keeps its visual weight either way.
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(0.35), accent.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(accent)
            }
            .frame(width: 220, height: 128)
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
            HStack(spacing: 6) {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(action.label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(Capsule().fill(MuesliTheme.accent))
        }
        .buttonStyle(.plain)
    }
}
