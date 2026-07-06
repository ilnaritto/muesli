import AppKit
import Foundation
import SwiftUI
import MuesliCore

@MainActor
final class RecentHistoryWindowController: NSObject, NSWindowDelegate {
    private let store: DictationStore
    private let controller: MuesliController
    private var window: NSWindow?
    private var keyMonitor: Any?

    var presentationWindow: NSWindow? {
        window
    }

    init(store: DictationStore, controller: MuesliController) {
        self.store = store
        self.controller = controller
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        guard let window else { return }
        controller.syncAppState()
        if !window.isVisible {
            controller.noteWindowOpened()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        applyTrafficLightCentering()
    }

    func reload() {
        controller.syncAppState()
    }

    func close() {
        window?.close()
    }

    func updateBackendLabel() {
        controller.syncAppState()
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        controller.noteWindowClosed()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 140, width: 1120, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppIdentity.displayName
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.067, green: 0.071, blue: 0.078, alpha: 1) // #111214

        let rootView = DashboardRootView(
            appState: controller.appState,
            controller: controller
        )
        let hostingView = NSHostingView(rootView: rootView)
        // Without this, NSHostingView constrains the window content to SwiftUI's
        // *ideal* width (rail + list + detail maxWidth caps ≈ 1600pt) and centers
        // the oversized content, clipping both edges. Empty sizing options make
        // the SwiftUI content always match the window size instead.
        hostingView.sizingOptions = []

        // Custom window corner radius: the window itself is transparent and the
        // content layer defines the rounded shape (larger than the system default).
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 26
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 980, height: 600)

        self.window = window

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "f" else {
                return event
            }
            self.controller.appState.focusSearchField = true
            return nil
        }

        applyTrafficLightCentering()
    }

    // MARK: - Traffic light centering

    /// Centers the close/minimize/zoom buttons horizontally within the icon rail.
    /// AppKit re-lays-out the buttons on its own schedule (resize, key-state change,
    /// appearance change), so this is re-applied from several NSWindowDelegate hooks,
    /// each time both synchronously and on the next runloop tick.
    private func applyTrafficLightCentering() {
        repositionTrafficLights()
        DispatchQueue.main.async { [weak self] in
            self?.repositionTrafficLights()
        }
    }

    /// Default (system) geometry of the close button, captured on first layout
    /// so repeated repositioning stays absolute rather than cumulative.
    private var defaultTrafficLightY: CGFloat?
    private var defaultTrafficLightSize: NSSize?
    private var didScaleTrafficLights = false

    /// Traffic lights are enlarged (matching modern card-style apps) and moved
    /// down so they sit vertically centered against the window corner curve.
    private let trafficLightScale: CGFloat = 1.15
    private let trafficLightCenterDropDown: CGFloat = 17
    private let trafficLightGap: CGFloat = 7

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
            // AppKit re-laid-out the buttons at a fresh (higher) default position.
            defaultTrafficLightY = max(known, currentY)
        }

        // Scale the button *drawing* once (scaleUnitSquare is cumulative), then
        // keep enforcing the enlarged frame on every pass.
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

        // AppKit coordinates are bottom-up: moving visually down = smaller y.
        // Keep the button *center* dropped by a fixed amount, accounting for the
        // extra height from scaling.
        let defaultCenterY = (defaultTrafficLightY ?? currentY) + defaultSize.height / 2
        let targetY = defaultCenterY - trafficLightCenterDropDown - scaledSize.height / 2

        // Left-aligned inside the rounded window corner.
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
            // The hover/rollover region for the button group is tracked by the
            // titlebar superview using the buttons' *original* frames — force it
            // to recompute so hover matches the moved/scaled buttons.
            for button in buttons {
                button.updateTrackingAreas()
            }
            buttons[0].superview?.updateTrackingAreas()
        }
    }

    func windowDidResize(_ notification: Notification) {
        applyTrafficLightCentering()
        window?.invalidateShadow()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        applyTrafficLightCentering()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyTrafficLightCentering()
    }

    func windowDidResignKey(_ notification: Notification) {
        applyTrafficLightCentering()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        applyTrafficLightCentering()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        applyTrafficLightCentering()
    }
}
