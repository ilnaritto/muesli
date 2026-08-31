import SwiftUI
import MuesliCore

/// Task 5: full-width onboarding-style banner for the Features tour — one
/// per flagship feature, image + description + one action, replacing the
/// grid-of-cards showcase for the first-run path. `assetName` looks up
/// `Contents/Resources/features-tour/<assetName>.png` in the bundle (copied
/// there by `scripts/build_native_app.sh`/`dev-test.sh`, matching the
/// `about-hero.jpg` pattern) — when the file isn't there, the banner
/// renders without the image instead of leaving a gap or crashing.
struct FeatureTourBanner: View {
    let assetName: String
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
        HStack(alignment: .center, spacing: MuesliTheme.spacing24) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let action {
                    tourActionButton(action)
                        .padding(.top, MuesliTheme.spacing4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let tourImage {
                Image(nsImage: tourImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 300, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                    .fixedSize()
            }
        }
        .padding(MuesliTheme.spacing24)
        .frame(maxWidth: 1100, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL).fill(MuesliTheme.backgroundBase))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
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
