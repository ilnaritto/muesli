import AppKit
import SwiftUI
import MuesliCore

/// Invisible titlebar accessory that extends the titlebar container downward so
/// the dropped/enlarged traffic lights stay fully hover- and click-testable.
private final class OnboardingTrafficLightHitAreaExtender: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let controller: MuesliController
    private let resumeProgress: OnboardingProgress?
    private var window: NSWindow?

    // Traffic-light geometry (mirrors the main window's larger, inset buttons).
    private var defaultTrafficLightY: CGFloat?
    private var defaultTrafficLightSize: NSSize?
    private var didScaleTrafficLights = false
    private let trafficLightScale: CGFloat = 1.15
    private let trafficLightCenterDropDown: CGFloat = 17
    private let trafficLightGap: CGFloat = 7

    init(controller: MuesliController, resumeProgress: OnboardingProgress? = nil) {
        self.controller = controller
        self.resumeProgress = resumeProgress
        super.init()
    }

    func show() {
        if window == nil { buildWindow() }
        // Reopen from the menu bar after the user closed or minimized the window.
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.center()
        bringToFront()
        applyTrafficLightCentering()
    }

    func bringToFront() {
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func yieldFocusToSystemSettings() {
        guard let window else { return }
        window.level = .normal
        window.orderBack(nil)
    }

    func prepareForNativePermissionPrompt() {
        guard let window else { return }
        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Pryanik"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.backgroundColor = NSColor(red: 0.067, green: 0.071, blue: 0.078, alpha: 1)

        // Extend the titlebar container down past the dropped traffic lights so
        // their full enlarged area stays hover- and click-responsive.
        let hitAreaAccessory = NSTitlebarAccessoryViewController()
        hitAreaAccessory.view = OnboardingTrafficLightHitAreaExtender(
            frame: NSRect(x: 0, y: 0, width: 0, height: 40)
        )
        hitAreaAccessory.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(hitAreaAccessory)

        let rootView: OnboardingView
        if let progress = resumeProgress {
            let backend = BackendOption.all.first(where: {
                $0.backend == progress.selectedBackendKey && $0.model == progress.selectedModelKey
            }) ?? .parakeetMultilingual
            let cohereLanguage = CohereTranscribeLanguage.resolved(progress.selectedCohereLanguageCode)
            let hotkey = HotkeyConfig(keyCode: progress.hotkeyKeyCode, label: progress.hotkeyLabel)
            rootView = OnboardingView(
                controller: controller,
                appState: controller.appState,
                initialStep: progress.currentStep,
                initialUserName: progress.userName,
                initialBackend: backend,
                initialCohereLanguage: cohereLanguage,
                initialHotkey: hotkey,
                initialSystemAudioRequested: progress.systemAudioRequested,
                initialUseCase: OnboardingUseCase.resolved(progress.onboardingUseCaseRawValue),
                initialSummaryBackend: .chatGPT,
                initialModelDownloadProgress: progress.modelDownloadProgress,
                initialModelDownloadStatus: progress.modelDownloadStatus
            )
        } else {
            rootView = OnboardingView(
                controller: controller,
                appState: controller.appState,
                initialCohereLanguage: controller.config.resolvedCohereLanguage,
                initialUseCase: controller.config.resolvedOnboardingUseCase,
                initialSummaryBackend: .chatGPT
            )
        }
        window.contentView = NSHostingView(rootView: rootView)
        self.window = window
        applyTrafficLightCentering()
    }

    // MARK: - Traffic light centering (enlarged + inset, matching the main window)

    private func applyTrafficLightCentering() {
        repositionTrafficLights()
        DispatchQueue.main.async { [weak self] in
            self?.repositionTrafficLights()
        }
    }

    private func repositionTrafficLights() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = buttonTypes.compactMap { window.standardWindowButton($0) }
        guard buttons.count == buttonTypes.count else { return }

        if defaultTrafficLightSize == nil {
            defaultTrafficLightSize = buttons[0].frame.size
        }
        guard let defaultSize = defaultTrafficLightSize, defaultSize.width > 0 else { return }

        let currentY = buttons[0].frame.origin.y
        if defaultTrafficLightY == nil {
            defaultTrafficLightY = currentY
        } else if let known = defaultTrafficLightY, currentY > known {
            defaultTrafficLightY = max(known, currentY)
        }

        let scaledSize = NSSize(
            width: defaultSize.width * trafficLightScale,
            height: defaultSize.height * trafficLightScale
        )
        if !didScaleTrafficLights {
            for button in buttons {
                button.scaleUnitSquare(to: NSSize(width: trafficLightScale, height: trafficLightScale))
            }
            didScaleTrafficLights = true
        }

        let defaultCenterY = (defaultTrafficLightY ?? currentY) + defaultSize.height / 2
        let targetY = defaultCenterY - trafficLightCenterDropDown - scaledSize.height / 2
        let targetMinX: CGFloat = 20

        var didChangeLayout = false
        for (index, button) in buttons.enumerated() {
            let x = targetMinX + CGFloat(index) * (scaledSize.width + trafficLightGap)
            if abs(button.frame.width - scaledSize.width) > 0.5 {
                button.setFrameSize(scaledSize)
                didChangeLayout = true
            }
            if abs(button.frame.origin.x - x) > 0.5 || abs(button.frame.origin.y - targetY) > 0.5 {
                button.setFrameOrigin(NSPoint(x: x, y: targetY))
                didChangeLayout = true
            }
        }

        if didChangeLayout {
            for button in buttons {
                button.updateTrackingAreas()
            }
            buttons[0].superview?.updateTrackingAreas()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyTrafficLightCentering()
    }

    func windowDidResignKey(_ notification: Notification) {
        applyTrafficLightCentering()
    }

    func windowDidResize(_ notification: Notification) {
        applyTrafficLightCentering()
    }
}
