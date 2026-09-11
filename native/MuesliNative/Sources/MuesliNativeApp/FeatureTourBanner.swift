import AppKit
import SwiftUI
import MuesliCore

/// Presentational image banner for a flagship feature (round 3), refined
/// per Ilnar's follow-up voice note (round 4):
/// - the action button is hidden until hover, then fades/slides in, instead
///   of always showing a static pill;
/// - when the feature is gated by a real macOS permission, a persistent
///   "granted" badge replaces the hover button once access is actually
///   granted — that status should always be visible, not hidden behind
///   hover, so the user can tell at a glance what's still needed.
/// The whole card stays the single tap target (clicking always navigates to
/// the feature's setup, whether or not permission is granted yet — the
/// destination screen is where the actual grant happens); the badge/button
/// here is a status readout, not a second interactive control.
struct FeatureTourBanner: View {
    let assetName: String
    let icon: String
    let accent: Color
    let title: String
    let description: String
    let action: FeatureAction?
    /// Non-nil marks this card as permission-gated: polled while the card
    /// is visible, same pattern as `OverviewPermissionsBoard`.
    var permissionGranted: (() -> Bool)? = nil

    @State private var isHovered = false
    @State private var granted = false
    @State private var pollTimer: Timer?

    private var coverAssetURL: URL? {
        Bundle.main.url(forResource: "\(assetName)-cover", withExtension: "png", subdirectory: "features-tour")
    }

    /// Covers are sized to fill the banner (`.fill`, then clipped) rather
    /// than letterboxed — a pure image banner with no separate text block
    /// competing for height.
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
                // over any artwork without covering most of it. The
                // placeholder (no cover yet) has no baked-in text, so it
                // needs the title here too.
                LinearGradient(
                    colors: [.black.opacity(0.62), .black.opacity(0)],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .frame(height: 70, alignment: .bottom)

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

                statusBadge
                    .padding(10)
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
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            guard permissionGranted != nil else { return }
            refreshPermission()
            pollTimer?.invalidate()
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                refreshPermission()
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func refreshPermission() {
        granted = permissionGranted?() ?? false
    }

    /// Top-trailing status readout: a persistent checkmark once a gated
    /// permission is granted (always visible — that's a fact about the
    /// system, not a hover affordance); otherwise the action chip, shown
    /// only on hover per the latest feedback.
    @ViewBuilder
    private var statusBadge: some View {
        if permissionGranted != nil, granted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(tr("Access granted", "Доступ разрешён"))
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(MuesliTheme.success.opacity(0.85)))
            .frame(maxWidth: .infinity, alignment: .topTrailing)
        } else if let action {
            HStack(spacing: 5) {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(action.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(accent.opacity(0.88)))
            .frame(maxWidth: .infinity, alignment: .topTrailing)
            .opacity(isHovered ? 1 : 0)
            .offset(y: isHovered ? 0 : -4)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
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
