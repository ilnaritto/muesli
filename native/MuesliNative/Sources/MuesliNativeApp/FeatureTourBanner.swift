import AppKit
import SwiftUI
import MuesliCore

/// One macOS permission (or none) a flagship feature depends on, and
/// whether it's currently granted — drives the always-visible status
/// badge on `FeatureTourBanner`. Computed once per render by `HomeView`'s
/// single shared permission poller, not by the banner itself.
struct PermissionRequirement {
    let summary: String
    let isSatisfied: Bool
}

/// Presentational image banner for a flagship feature. Stateless by design
/// — no `@State`, no `.onHover` — so its layout can never depend on
/// interaction state; height comes in as one explicit number from the row
/// that places it (`HomeView.mainFeaturesBoard`), never inferred from
/// content. This is what makes the caption unable to spill past the card:
/// every text element has `.lineLimit` + `.truncationMode(.tail)` and none
/// use `.fixedSize(vertical: true)` (the modifier that let a card's own
/// content grow past its bounds in earlier attempts).
///
/// `assetName` looks up `Contents/Resources/features-tour/<assetName>-art.png`
/// — deliberately a different suffix than the old `-cover.png` placeholder
/// title cards (which baked in Russian-only text and a per-feature color,
/// directly at odds with the single theme-accent requirement and prone to
/// cropping once cards vary in aspect ratio). No `-art.png` exists yet for
/// any feature, so every card currently renders the theme-accent gradient
/// + glyph fallback below — real photography/art can be dropped in later
/// under that name, as long as it carries no baked-in text or color.
struct FeatureTourBanner: View {
    let assetName: String
    let icon: String
    let title: String
    let description: String
    let action: FeatureAction?
    var permission: PermissionRequirement? = nil
    var height: CGFloat = 220

    private var artURL: URL? {
        Bundle.main.url(forResource: "\(assetName)-art", withExtension: "png", subdirectory: "features-tour")
    }

    private var isCompact: Bool { height < 170 }

    var body: some View {
        Button {
            action?.action()
        } label: {
            ZStack(alignment: .topTrailing) {
                artwork
                scrim
                caption
                statusBadge
                    .padding(10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(MuesliTheme.backgroundBase)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .help(action?.label ?? title)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artwork: some View {
        if let artURL, let image = NSImage(contentsOf: artURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [MuesliTheme.accent.opacity(0.85), MuesliTheme.accent.opacity(0.32)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: icon)
                    .font(.system(size: isCompact ? 40 : 68, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.16))
                    .padding(isCompact ? 14 : 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var scrim: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: captionZoneHeight + 16)
        }
    }

    // MARK: - Caption (bounded — cannot spill past the card)

    private var captionZoneHeight: CGFloat {
        min(height * 0.55, isCompact ? 66 : 92)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
            Text(title)
                .font(.system(size: isCompact ? 13 : 17, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
            Text(description)
                .font(.system(size: isCompact ? 10 : 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(isCompact ? 1 : 2)
                .truncationMode(.tail)
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.bottom, isCompact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: captionZoneHeight, alignment: .bottomLeading)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .clipped()
    }

    // MARK: - Status badge (always visible — not hover-gated)

    /// Permission-gated cards show a persistent granted/needs-access
    /// readout — that's a fact about the system, always worth seeing at a
    /// glance, per live feedback that hover-hiding it made the page read
    /// as less informative. Non-gated cards show their action label
    /// instead, in the same slot, also always visible. The whole card is
    /// still the single tap target — this is a label, not a nested button.
    @ViewBuilder
    private var statusBadge: some View {
        if let permission {
            HStack(spacing: 4) {
                Image(systemName: permission.isSatisfied ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(permission.isSatisfied ? tr("Access granted", "Доступ разрешён") : tr("Needs access", "Нужен доступ"))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill((permission.isSatisfied ? MuesliTheme.success : MuesliTheme.recording).opacity(0.9)))
            .help(permission.summary)
        } else if let action, !isCompact {
            HStack(spacing: 5) {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(action.label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(MuesliTheme.accent.opacity(0.9)))
        }
    }
}
