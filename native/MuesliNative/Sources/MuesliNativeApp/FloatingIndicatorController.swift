import AppKit
import QuartzCore
import Foundation
import SwiftUI
import MuesliCore

@MainActor
private final class HoverIndicatorView: NSView {
    weak var owner: FloatingIndicatorController?
    private var trackingAreaRef: NSTrackingArea?
    private var dragOrigin: NSPoint?
    private var didDrag = false
    private var dragEnabled = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        owner?.setHovered(true)
    }

    override func mouseMoved(with event: NSEvent) {
        owner?.handleHoverMouseMoved()
    }

    override func mouseExited(with event: NSEvent) {
        owner?.scheduleHoverExit()
    }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        // Dragging is only allowed when the position setting is "custom";
        // preset anchors (top-center etc.) keep the pill locked in place so
        // it can't be nudged accidentally.
        dragEnabled = owner?.allowsDragging ?? false
        guard dragEnabled else { return }
        owner?.collapseForDrag()
        // Recalculate drag origin after collapse (frame changed)
        dragOrigin = NSPoint(x: (window?.frame.width ?? 0) / 2, y: (window?.frame.height ?? 0) / 2)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragEnabled, let window else { return }
        didDrag = true
        let current = event.locationInWindow
        let frame = window.frame
        let newOrigin = NSPoint(
            x: frame.origin.x + (current.x - (dragOrigin?.x ?? current.x)),
            y: frame.origin.y + (current.y - (dragOrigin?.y ?? current.y))
        )
        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        // Always clear the drag flag — a plain click sets it in mouseDown too,
        // and a stuck flag permanently blocks hover expansion.
        owner?.isDragging = false
        if didDrag {
            owner?.savePosition()
        } else if event.modifierFlags.contains(.option) {
            owner?.handleOptionClick()
        } else {
            let clickX = convert(event.locationInWindow, from: nil).x
            owner?.handleClick(atX: clickX)
            owner?.restoreHoverAfterClick()
        }
        dragOrigin = nil
        didDrag = false
    }

    override func rightMouseUp(with event: NSEvent) {
        owner?.handleOptionClick()
    }
}

@MainActor
final class FloatingIndicatorController: NSObject {
    private var panel: NSPanel?
    private var contentView: HoverIndicatorView?
    private var iconLabel: NSTextField?
    private var textLabel: NSTextField?
    private var state: DictationState = .idle
    private var isHovered = false
    private var hoverExitWorkItem: DispatchWorkItem?
    private let configStore: ConfigStore
    private var isMeetingRecording = false
    private var isMeetingRecordingPaused = false
    private var glassView: NSVisualEffectView?
    private var tintLayer: CALayer?
    private var micIconView: NSImageView?
    private var wandIconView: NSImageView?
    private var barLayers: [CALayer] = []
    private var amplitudeTimer: Timer?
    private var smoothedDictationAmplitude: CGFloat = 0
    private var smoothedMeetingAmplitude: CGFloat = 0
    private var waveGroupSignature = ""
    private var waveformAnimationMode: WaveformAnimationMode = .level
    private var recordingWaveformMode: WaveformAnimationMode = .level
    private var waveformAnimationStartedAt = Date()
    fileprivate var isDragging = false
    /// Independent audio-level sources: dictation and meeting capture can run
    /// simultaneously, each animating its own dot group.
    var dictationPowerProvider: (() -> Float)?
    var meetingPowerProvider: (() -> Float)?
    /// True while a dictation capture is live (independent of meetings).
    private(set) var isDictationCapturing = false
    var onStopMeeting: (() -> Void)?
    var onDiscardMeeting: (() -> Void)?
    var onToggleMeetingPause: (() -> Void)?
    var onCancelToggleDictation: (() -> Void)?
    var onPositionSaved: ((CGPoint) -> Void)?
    var isToggleDictation = false
    /// Top edge of the collapsed strip while hovering — the launcher expands
    /// strictly downward from it and the strip returns to the same spot.
    private var hoverAnchorTop: CGFloat?
    /// Monotonic token for in-flight expand/collapse morphs: completions
    /// compare it so a superseded morph can't apply its finishing step.
    private var morphGeneration = 0
    /// Hover value the LAST render actually drew. setHovered mutates
    /// isHovered before calling setState, so previousHover can't detect a
    /// hover flip — this can.
    private var lastRenderedHovered = false
    /// While a collapse morph shrinks the pill back to the strip, the tiny
    /// status text stays hidden and reappears in the morph completion.
    private var statusHiddenForMorph = false
    /// True while a hover expand/collapse morph is animating — cosmetic
    /// re-renders must not repaint collapsed geometry mid-morph.
    private var hoverMorphInFlight = false
    var onStartDictation: (() -> Void)?
    var onStartMeeting: (() -> Void)?
    var onStartMeetingWithVideo: (() -> Void)?
    private var isMeetingVideoRecording = false
    private var launcherView: NSView?
    /// Bumped on each fresh launcher reveal to reset stuck hover captions.
    private var launcherRevealToken = 0

    /// True while the hover launcher is open — the meeting-start loading
    /// pill must not replace the pill then (it reads as a duplicate strip).
    var isLauncherExpanded: Bool {
        isHovered && launcherView?.isHidden == false
    }
    private var stopLayer: CALayer?
    /// Dedicated layer-hosting view for the wave dots. Bar CALayers must NOT
    /// live directly in contentView.layer — AppKit manages that sublayer tree
    /// for its own layer-backed subviews and reorders it on subview churn
    /// (the hover launcher add/remove), which shoved the dots under the glass.
    private var dotsHostView: NSView?
    // Processing status (transcribe/summarize/…) lives INSIDE the pill:
    // a mini color loader in the strip, a spinning stage ring around the
    // mode's launcher icon, and the hover caption carries the stage text.
    enum ProcessingKind {
        case meetingAudio
        case meetingVideo
        case dictation
    }
    private(set) var processingStatus: String?
    private var processingKind: ProcessingKind = .meetingAudio
    private var stripSpinnerLayer: CAShapeLayer?
    private var transcribingTitle = "Transcribing"
    private var computerUseTranscriptText: String?
    private var loadingSpinner: NSProgressIndicator?
    private var isShowingLoading = false
    private var isComputerUseCursorMode = false
    private var computerUseCursorReturnFrame: NSRect?

    private enum WaveformAnimationMode {
        case level
        case waiting
    }

    init(configStore: ConfigStore) {
        self.configStore = configStore
        super.init()
    }

    var onStopToggleDictation: (() -> Void)?

    var currentFrame: NSRect? {
        panel?.frame
    }

    /// The pill may only be dragged when its position setting is "custom".
    fileprivate var allowsDragging: Bool {
        configStore.load().indicatorAnchor == .custom
    }

    func handleClick(atX x: CGFloat? = nil) {
        // Every recording control lives in the SwiftUI hover launcher now —
        // clicks on the strip/pill background do nothing.
        _ = x
    }

    func handleOptionClick() {
        if isMeetingRecording, state == .recording {
            onDiscardMeeting?()
        } else if state == .recording {
            onCancelToggleDictation?()
        }
    }

    func collapseForDrag() {
        isDragging = true
        hoverExitWorkItem?.cancel()
        defer { hoverAnchorTop = nil }
        guard state == .idle,
              !isShowingLoading,
              let panel,
              let contentView,
              let iconLabel,
              let textLabel else { return }
        isHovered = false
        lastRenderedHovered = false

        let config = configStore.load()
        let style = styleForState(.idle, config: config)
        let targetFrame = frameForState(.idle, config: config)

        // Instant resize — no animation
        panel.setFrame(targetFrame, display: true)
        contentView.frame = NSRect(origin: .zero, size: targetFrame.size)
        contentView.layer?.cornerRadius = targetFrame.height / 2
        contentView.layer?.backgroundColor = style.background.cgColor
        contentView.layer?.borderWidth = 0
        glassView?.frame = NSRect(origin: .zero, size: targetFrame.size)
        panel.alphaValue = style.alpha

        iconLabel.stringValue = style.icon
        iconLabel.textColor = style.iconColor
        textLabel.isHidden = true
        textLabel.alphaValue = 0
        launcherView?.isHidden = true
        layoutLabels(iconLabel: iconLabel, textLabel: textLabel, in: targetFrame.size, hasTitle: false, animated: false)
        applyGlassState(.idle, frameSize: targetFrame.size)
    }

    /// Strip ⇄ launcher hover switch, shared by idle AND capture states. The
    /// window SNAPS to the target frame (top edge pinned via hoverAnchorTop)
    /// and only the tint layer morphs — animating the NSPanel frame itself
    /// sags and reads as the pill sliding.
    private func animateHoverMorph(
        style: (background: NSColor, border: NSColor, icon: String, title: String, iconColor: NSColor, textColor: NSColor, alpha: CGFloat),
        targetFrame: NSRect,
        collapsedTintAlpha: CGFloat
    ) {
        guard let panel, let contentView, let tint = tintLayer else { return }
        morphGeneration += 1
        let generation = morphGeneration
        let stateAtMorph = state
        hoverMorphInFlight = true
        if isHovered {
            // The dots/mini-loader must vanish BEFORE the expand snaps the
            // window (display: true renders immediately) — otherwise that
            // frame shows them parked at the new bottom-left.
            setWaveBarsHidden(true)
        }
        let collapsedColor = NSColor.colorWith(hexString: "1e1e1e", alpha: collapsedTintAlpha).cgColor
        let hoveredColor = NSColor.colorWith(hexString: "1e1e1e", alpha: 0.45).cgColor

        // A repaint while ALREADY expanded (e.g. idle→idle right after a
        // dictation stops under the cursor) must not replay the morph under
        // the visible launcher — just refresh the final geometry in place.
        if isHovered, let launcher = launcherView, !launcher.isHidden {
            hoverMorphInFlight = false
            let pillHeight: CGFloat = 44
            let pillFrame = CGRect(
                x: 0,
                y: targetFrame.height - pillHeight,
                width: targetFrame.width,
                height: pillHeight
            )
            panel.setFrame(targetFrame, display: true)
            contentView.frame = NSRect(origin: .zero, size: targetFrame.size)
            contentView.layer?.cornerRadius = 0
            panel.alphaValue = style.alpha
            glassView?.frame = pillFrame
            glassView?.layer?.cornerRadius = pillHeight / 2
            glassView?.isHidden = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tint.isHidden = false
            tint.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            tint.position = CGPoint(x: targetFrame.width / 2, y: targetFrame.height)
            tint.bounds = CGRect(x: 0, y: 0, width: targetFrame.width, height: pillHeight)
            tint.cornerRadius = pillHeight / 2
            tint.backgroundColor = hoveredColor
            CATransaction.commit()
            updateLauncher(visible: true, frameSize: targetFrame.size)
            panel.orderFrontRegardless()
            return
        }

        micIconView?.isHidden = true
        wandIconView?.isHidden = true
        iconLabel?.isHidden = true
        textLabel?.isHidden = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.borderWidth = 0
        tint.isHidden = false
        tint.borderWidth = 1
        tint.borderColor = style.border.cgColor
        glassView?.layer?.borderWidth = 1
        glassView?.layer?.borderColor = style.border.cgColor

        panel.alphaValue = style.alpha
        if isHovered {
            // Expanding: the window snaps out immediately. When collapsing it
            // stays large until the shrink morph completes (see below).
            panel.setFrame(targetFrame, display: true)
            contentView.frame = NSRect(origin: .zero, size: targetFrame.size)
        }

        let timing = CAMediaTimingFunction(name: .easeOut)
        let collapsedSize = NSSize(width: 43, height: 7)

        if isHovered {
            // Window snaps to the expanded frame; the tint morphs easeOut from
            // the strip (pinned top-center) into the 44pt capsule. The strip
            // below the capsule stays transparent for the caption.
            let pillHeight: CGFloat = 44
            let pillFrame = CGRect(
                x: 0,
                y: targetFrame.height - pillHeight,
                width: targetFrame.width,
                height: pillHeight
            )
            contentView.layer?.cornerRadius = 0

            let start = CGRect(
                x: (targetFrame.width - collapsedSize.width) / 2,
                y: targetFrame.height - collapsedSize.height,
                width: collapsedSize.width,
                height: collapsedSize.height
            )
            // Explicit split animations: width starts 10ms before height.
            // Anchor at the top-center so growth is sideways + downward only.
            let easeOut = CAMediaTimingFunction(name: .easeOut)
            let morphDuration: CFTimeInterval = 0.27
            let heightLag: CFTimeInterval = 0.010

            // The blur never blinks off: it starts as the strip and morphs
            // into the capsule alongside the tint, so the finished
            // fill/gradient look exists from the very first frames.
            if let glass = glassView {
                glass.frame = start
                glass.layer?.masksToBounds = true
                glass.layer?.cornerRadius = collapsedSize.height / 2
                glass.isHidden = false
                let glassRadius = CABasicAnimation(keyPath: "cornerRadius")
                glassRadius.fromValue = collapsedSize.height / 2
                glassRadius.toValue = pillHeight / 2
                glassRadius.duration = morphDuration
                glassRadius.timingFunction = easeOut
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                glass.layer?.cornerRadius = pillHeight / 2
                glass.layer?.add(glassRadius, forKey: "glass.radius")
                CATransaction.commit()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = morphDuration
                    context.timingFunction = easeOut
                    context.allowsImplicitAnimation = true
                    glass.animator().frame = pillFrame
                }
            }

            // Start from the layer's PRESENTATION geometry: a rapid hover
            // in/out re-enters mid-morph, and restarting from the bare strip
            // flashes a phantom second pill under the half-open capsule.
            let fromBounds = tint.presentation()?.bounds
                ?? CGRect(origin: .zero, size: collapsedSize)
            let fromRadius = tint.presentation()?.cornerRadius ?? collapsedSize.height / 2
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tint.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            tint.position = CGPoint(x: targetFrame.width / 2, y: targetFrame.height)
            tint.bounds = fromBounds
            tint.cornerRadius = fromRadius
            // Final hover opacity from the very first frame — the expand
            // carries no translucency ramp (matches the capture look).
            tint.backgroundColor = hoveredColor
            CATransaction.commit()

            let now = CACurrentMediaTime()
            let widthAnim = CABasicAnimation(keyPath: "bounds.size.width")
            widthAnim.fromValue = fromBounds.width
            widthAnim.toValue = targetFrame.width
            widthAnim.beginTime = now
            widthAnim.duration = morphDuration
            widthAnim.timingFunction = easeOut

            let heightAnim = CABasicAnimation(keyPath: "bounds.size.height")
            heightAnim.fromValue = fromBounds.height
            heightAnim.toValue = pillHeight
            heightAnim.beginTime = now + heightLag
            heightAnim.duration = morphDuration
            heightAnim.fillMode = .backwards
            heightAnim.timingFunction = easeOut

            let radiusAnim = CABasicAnimation(keyPath: "cornerRadius")
            radiusAnim.fromValue = fromRadius
            radiusAnim.toValue = pillHeight / 2
            radiusAnim.beginTime = now + heightLag
            radiusAnim.duration = morphDuration
            radiusAnim.fillMode = .backwards
            radiusAnim.timingFunction = easeOut

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.morphGeneration == generation else { return }
                self.hoverMorphInFlight = false
                guard self.state == stateAtMorph, self.isHovered else { return }
                self.glassView?.frame = pillFrame
                self.glassView?.layer?.cornerRadius = pillHeight / 2
                self.glassView?.isHidden = false
                // Icons appear only after the capsule morph has settled.
                self.updateLauncher(visible: true, frameSize: targetFrame.size, fadeIn: true)
            }
            tint.bounds = CGRect(x: 0, y: 0, width: targetFrame.width, height: pillHeight)
            tint.cornerRadius = pillHeight / 2
            tint.backgroundColor = hoveredColor
            tint.add(widthAnim, forKey: "morph.width")
            tint.add(heightAnim, forKey: "morph.height")
            tint.add(radiusAnim, forKey: "morph.radius")
            CATransaction.commit()
        } else {
            updateLauncher(visible: false, frameSize: targetFrame.size)
            statusHiddenForMorph = true

            // Morph back to the strip inside the still-large window, then
            // snap the window down to the strip frame.
            let currentSize = panel.frame.size
            let strip = CGRect(
                x: (currentSize.width - collapsedSize.width) / 2,
                y: currentSize.height - collapsedSize.height,
                width: collapsedSize.width,
                height: collapsedSize.height
            )
            let easeOut = CAMediaTimingFunction(name: .easeOut)
            let morphDuration: CFTimeInterval = 0.24
            let widthLag: CFTimeInterval = 0.010
            // Presentation values: collapsing may interrupt a running expand.
            let currentBounds = tint.presentation()?.bounds ?? tint.bounds

            // The blur shrinks alongside the tint — it never blinks off.
            if let glass = glassView {
                if glass.isHidden {
                    glass.frame = CGRect(x: 0, y: currentSize.height - 44, width: currentSize.width, height: 44)
                    glass.layer?.cornerRadius = 22
                    glass.isHidden = false
                }
                glass.layer?.masksToBounds = true
                let glassRadius = CABasicAnimation(keyPath: "cornerRadius")
                glassRadius.fromValue = glass.layer?.presentation()?.cornerRadius
                    ?? glass.layer?.cornerRadius ?? 22
                glassRadius.toValue = collapsedSize.height / 2
                glassRadius.duration = morphDuration
                glassRadius.timingFunction = easeOut
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                glass.layer?.cornerRadius = collapsedSize.height / 2
                glass.layer?.add(glassRadius, forKey: "glass.radius")
                CATransaction.commit()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = morphDuration
                    context.timingFunction = easeOut
                    context.allowsImplicitAnimation = true
                    glass.animator().frame = strip
                }
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tint.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            tint.position = CGPoint(x: currentSize.width / 2, y: currentSize.height)
            tint.bounds = currentBounds
            CATransaction.commit()

            let now = CACurrentMediaTime()
            let heightAnim = CABasicAnimation(keyPath: "bounds.size.height")
            heightAnim.fromValue = currentBounds.height
            heightAnim.toValue = collapsedSize.height
            heightAnim.beginTime = now
            heightAnim.duration = morphDuration
            heightAnim.timingFunction = easeOut

            let widthAnim = CABasicAnimation(keyPath: "bounds.size.width")
            widthAnim.fromValue = currentBounds.width
            widthAnim.toValue = collapsedSize.width
            widthAnim.beginTime = now + widthLag
            widthAnim.duration = morphDuration
            widthAnim.fillMode = .backwards
            widthAnim.timingFunction = easeOut

            let radiusAnim = CABasicAnimation(keyPath: "cornerRadius")
            radiusAnim.fromValue = tint.presentation()?.cornerRadius ?? tint.cornerRadius
            radiusAnim.toValue = collapsedSize.height / 2
            radiusAnim.beginTime = now
            radiusAnim.duration = morphDuration
            radiusAnim.timingFunction = easeOut

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.morphGeneration == generation else { return }
                self.hoverMorphInFlight = false
                self.statusHiddenForMorph = false
                guard self.state == stateAtMorph, !self.isHovered,
                      let panel = self.panel, let contentView = self.contentView, let tint = self.tintLayer else { return }
                panel.setFrame(targetFrame, display: true)
                contentView.frame = NSRect(origin: .zero, size: targetFrame.size)
                contentView.layer?.cornerRadius = targetFrame.height / 2
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                tint.frame = CGRect(origin: .zero, size: targetFrame.size)
                tint.cornerRadius = targetFrame.height / 2
                tint.backgroundColor = collapsedColor
                CATransaction.commit()
                self.glassView?.frame = NSRect(origin: .zero, size: targetFrame.size)
                self.glassView?.layer?.cornerRadius = targetFrame.height / 2
                self.glassView?.isHidden = false
                // Capture dots return only after the shrink — rebuilt first,
                // since renders suppressed during the morph may have changed
                // the active group set.
                if stateAtMorph == .recording || stateAtMorph == .preparing {
                    self.ensureWaveformAnimation(
                        in: NSSize(width: 43, height: 7),
                        mode: stateAtMorph == .preparing ? .waiting : self.recordingWaveformMode
                    )
                }
                if stateAtMorph != .idle || self.processingStatus != nil {
                    self.setWaveBarsHidden(false, fade: 0.06)
                }
                self.refreshCollapsedStrip()
            }
            // The fill keeps FULL hover density almost all the way down — it
            // eases to the strip translucency only in the final stretch.
            let colorAnim = CABasicAnimation(keyPath: "backgroundColor")
            colorAnim.fromValue = tint.presentation()?.backgroundColor ?? tint.backgroundColor
            colorAnim.toValue = collapsedColor
            colorAnim.beginTime = now + morphDuration * 0.7
            colorAnim.duration = morphDuration * 0.3
            colorAnim.fillMode = .backwards
            colorAnim.timingFunction = easeOut
            tint.bounds = CGRect(origin: .zero, size: collapsedSize)
            tint.cornerRadius = collapsedSize.height / 2
            tint.backgroundColor = collapsedColor
            tint.add(heightAnim, forKey: "morph.height")
            tint.add(widthAnim, forKey: "morph.width")
            tint.add(radiusAnim, forKey: "morph.radius")
            tint.add(colorAnim, forKey: "morph.color")
            CATransaction.commit()
        }

        panel.orderFrontRegardless()
    }

    func savePosition() {
        guard let frame = panel?.frame else { return }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        onPositionSaved?(center)
    }

    func setToggleDictation(_ active: Bool, config: AppConfig) {
        isToggleDictation = active
        if active {
            isDictationCapturing = true
            setState(.recording, config: config)
        } else {
            removeStopLayer()
            isDictationCapturing = false
            dictationPowerProvider = nil
            setState(isMeetingRecording ? .recording : .idle, config: config)
        }
    }

    /// Marks the dictation capture as live/finished independently of the
    /// meeting flags, so both dot groups can coexist in the strip.
    func setDictationCapturing(_ active: Bool, config: AppConfig) {
        guard isDictationCapturing != active else { return }
        isDictationCapturing = active
        if !active {
            dictationPowerProvider = nil
        }
        if active || isMeetingRecording {
            setState(.recording, config: config)
        }
    }

    func setMeetingRecording(_ recording: Bool, withVideo: Bool = false, config: AppConfig) {
        isMeetingRecording = recording
        isMeetingVideoRecording = recording && withVideo
        recordingWaveformMode = .level
        if !recording {
            isMeetingRecordingPaused = false
            meetingPowerProvider = nil
        }
        if recording || isDictationCapturing {
            setState(.recording, config: config)
        } else {
            setState(.idle, config: config)
        }
    }

    func setRecordingWaveformWaiting(config: AppConfig) {
        recordingWaveformMode = .waiting
        guard state == .recording else { return }
        let targetSize = frameForState(.recording, config: config).size
        ensureWaveformAnimation(in: targetSize, mode: .waiting)
    }

    func setRecordingWaveformLevel(config: AppConfig) {
        recordingWaveformMode = .level
        guard state == .recording else {
            setState(.recording, config: config)
            return
        }
        let targetSize = frameForState(.recording, config: config).size
        ensureWaveformAnimation(in: targetSize, mode: .level)
    }

    func setPreparingWaveformWaiting(config: AppConfig) {
        recordingWaveformMode = .waiting
        guard state == .preparing else {
            setState(.preparing, config: config)
            return
        }
        if let panel {
            ensureWaveformAnimation(in: panel.frame.size, mode: .waiting)
        }
    }

    func setMeetingRecordingPaused(_ paused: Bool, config: AppConfig) {
        guard isMeetingRecordingPaused != paused else { return }
        isMeetingRecordingPaused = paused
        guard isMeetingRecording, state == .recording else { return }
        setState(.recording, config: config)
    }

    func setTranscribingTitle(_ title: String, config: AppConfig) {
        computerUseTranscriptText = nil
        transcribingTitle = title
        guard state == .transcribing else { return }
        setState(.transcribing, config: config)
    }

    func showComputerUseTranscript(_ transcript: String, config: AppConfig) {
        let normalized = Self.normalizedComputerUseTranscript(transcript)
        computerUseTranscriptText = normalized.isEmpty ? nil : normalized
        transcribingTitle = normalized.isEmpty ? "Starting CUA" : normalized
        setState(.transcribing, config: config)
    }

    func setState(_ state: DictationState, config: AppConfig) {
        var state = state
        // Composite-mode rules: the primary dictation flow ends with
        // .transcribing/.idle — that closes the dictation capture; but while a
        // meeting still records, the pill stays in the recording composite.
        if state == .idle || state == .transcribing {
            isDictationCapturing = false
            dictationPowerProvider = nil
            if isMeetingRecording {
                state = .recording
                // A dictation that never reached stream-active leaves the
                // waiting shimmer behind — the surviving meeting group must
                // return to live levels.
                recordingWaveformMode = .level
            }
        }
        if state == .preparing, isMeetingRecording || isDictationCapturing {
            state = .recording
        }
        // A stuck loading spinner must never outlive a state repaint — it
        // covers the strip and freezes hover (see meeting-start wedge bug).
        if isShowingLoading {
            isShowingLoading = false
            loadingSpinner?.stopAnimation(nil)
            loadingSpinner?.isHidden = true
        }
        let previousState = self.state
        let previousHover = isHovered
        if isComputerUseCursorMode {
            exitComputerUseCursorMode(restoreFrame: false)
        }
        self.state = state
        if state != .transcribing {
            transcribingTitle = "Transcribing"
            computerUseTranscriptText = nil
        }
        if state != .recording {
            recordingWaveformMode = .level
        }
        // Hover survives during preparing/recording — it expands the pill.
        if state == .transcribing {
            isHovered = false
            hoverAnchorTop = nil
        }
        if !config.showFloatingIndicator && state == .idle {
            close()
            return
        }
        if panel == nil {
            createPanel(config: config)
        }
        guard let panel, let contentView, let iconLabel, let textLabel else { return }

        // Entering recording/preparing with the cursor already over the pill
        // (start from the hover launcher) opens the pill expanded right away.
        let isCaptureState = state == .recording || state == .preparing
        let wasCaptureState = previousState == .recording || previousState == .preparing
        if isCaptureState, !wasCaptureState, pointerIsInsidePanel() {
            isHovered = true
            if hoverAnchorTop == nil { hoverAnchorTop = panel.frame.maxY }
        }

        // A cosmetic re-render (same state, same hover) must NOT interrupt an
        // in-flight hover morph: re-applying collapsed geometry mid-shrink
        // paints a phantom strip (glass+tint+dots) at the still-large
        // window's bottom-left. The morph completion rebuilds the strip.
        if hoverMorphInFlight,
           previousState == state,
           lastRenderedHovered == isHovered {
            return
        }

        let wasRenderedHovered = lastRenderedHovered
        lastRenderedHovered = isHovered

        let preservesWaveformAcrossTransition = previousState == .preparing && state == .recording
        if (previousState == .recording || previousState == .preparing)
            && state != previousState
            && !preservesWaveformAcrossTransition {
            stopWaveformAnimation()
        }

        // Immediately snap glass elements off when leaving idle so the SF Symbol
        // mic doesn't linger/fade during the recording/transcribing transition.
        if state != .idle {
            micIconView?.isHidden = true
            glassView?.isHidden = true
            tintLayer?.isHidden = true
            launcherView?.isHidden = true
        }

        let style = styleForState(state, config: config)
        let targetFrame = frameForState(state, config: config)
        defer { refreshCollapsedStrip() }

        // Any idle→idle redraw (hover on/off, refresh) must not animate the
        // window — a moving NSPanel visibly sags mid-animation. NOTE: setHovered
        // flips isHovered BEFORE calling setState, so previousHover == isHovered
        // here and cannot be used to detect the transition.
        if previousState == .idle, state == .idle {
            animateHoverMorph(style: style, targetFrame: targetFrame, collapsedTintAlpha: 0.22)
            return
        }
        // A hover flip while capturing runs the same snap-window layer morph
        // as idle — animating the NSPanel frame reads as the pill sliding.
        if previousState == state, state == .recording || state == .preparing,
           wasRenderedHovered != isHovered {
            animateHoverMorph(style: style, targetFrame: targetFrame, collapsedTintAlpha: 0.45)
            return
        }

        let duration = transitionDuration(
            from: previousState,
            to: state,
            wasHovered: previousHover,
            isHovered: isHovered
        )

        morphGeneration += 1
        let generation = morphGeneration
        if wasRenderedHovered, !isHovered, duration > 0.01 {
            // Collapsing from the launcher: the strip content reappears only
            // in the completion, after the pill has shrunk back.
            statusHiddenForMorph = true
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = style.alpha

            contentView.animator().frame = NSRect(origin: .zero, size: targetFrame.size)
            // In the hovered launcher the content view is just a transparent
            // container — its 37pt corner mask would clip the icon circles at
            // the top corners (the glass capsule carries the rounding).
            let launcherHover = isHovered && state != .transcribing
            contentView.layer?.cornerRadius = launcherHover ? 0 : targetFrame.height / 2
            contentView.layer?.backgroundColor = style.background.cgColor
            contentView.layer?.borderWidth = 0

            if state == .recording || state == .preparing {
                // Collapsed: only the per-mode dot groups. Expanded: the
                // SwiftUI launcher (toggles + cancel) covers the pill.
                iconLabel.isHidden = true
                iconLabel.animator().alphaValue = 0
                textLabel.animator().alphaValue = 0
                textLabel.isHidden = true
            } else {
                iconLabel.isHidden = false
                iconLabel.animator().alphaValue = 1
                iconLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
                iconLabel.stringValue = style.icon
                iconLabel.textColor = style.iconColor
                configureTextLabelForTranscript(state == .transcribing && computerUseTranscriptText != nil)
                textLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
                textLabel.stringValue = style.title
                textLabel.textColor = style.textColor
                textLabel.animator().alphaValue = style.title.isEmpty ? 0 : 1
                textLabel.isHidden = style.title.isEmpty
                if state == .transcribing, computerUseTranscriptText != nil {
                    layoutComputerUseTranscript(in: targetFrame.size, animated: true)
                } else {
                    layoutLabels(
                        iconLabel: iconLabel,
                        textLabel: textLabel,
                        in: targetFrame.size,
                        hasTitle: !style.title.isEmpty,
                        animated: true
                    )
                }
            }

            // Apply glass state last so it can override iconLabel visibility set above.
            applyGlassState(
                state,
                frameSize: targetFrame.size,
                tintAnimationDuration: duration,
                wasRenderedHovered: wasRenderedHovered
            )
        }, completionHandler: { [weak self] in
            guard let self, self.morphGeneration == generation else { return }
            self.finishHoverMorph()
        })

        // Manage SF Symbol effects — stop everything first, then start for the new state.
        micIconView?.removeAllSymbolEffects(animated: false)
        wandIconView?.removeAllSymbolEffects(animated: false)

        switch state {
        case .recording:
            ensureWaveformAnimation(in: targetFrame.size, mode: recordingWaveformMode)
            removeStopLayer()
            applyCollapsedDotsVisibility(wasRenderedHovered: wasRenderedHovered)
        case .transcribing:
            if #available(macOS 15, *) {
                wandIconView?.addSymbolEffect(
                    .wiggle.backward.byLayer,
                    options: .repeating, animated: true
                )
            }
        case .preparing:
            ensureWaveformAnimation(in: targetFrame.size, mode: .waiting)
            applyCollapsedDotsVisibility(wasRenderedHovered: wasRenderedHovered)
        case .idle:
            // No capture, but post-processing is pending: the strip carries
            // the tiny spinning stage loader in the mode's color.
            if processingStatus != nil {
                ensureStripSpinner()
                applyCollapsedDotsVisibility(wasRenderedHovered: wasRenderedHovered)
            } else {
                stopWaveformAnimation()
            }
        }

        panel.orderFrontRegardless()
        if state == .preparing {
            contentView.displayIfNeeded()
            panel.displayIfNeeded()
        }
    }

    func showComputerUseCursor(at quartzPoint: CGPoint, label rawLabel: String?) {
        let config = configStore.load()
        if panel == nil {
            createPanel(config: config)
        }
        guard let panel, let contentView, let iconLabel, let textLabel else { return }

        if !isComputerUseCursorMode {
            computerUseCursorReturnFrame = panel.frame
        }
        isComputerUseCursorMode = true
        hoverExitWorkItem?.cancel()
        isHovered = false
        isShowingLoading = false
        loadingSpinner?.stopAnimation(nil)
        loadingSpinner?.isHidden = true
        stopWaveformAnimation()

        let label = Self.cursorLabel(rawLabel)
        let targetSize = Self.computerUseCursorSize(label: label)
        let targetFrame = Self.computerUseCursorFrame(
            forQuartzPoint: quartzPoint,
            size: targetSize,
            offsetFromTarget: !label.isEmpty
        )

        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        glassView?.isHidden = true
        tintLayer?.isHidden = true
        micIconView?.isHidden = true
        wandIconView?.isHidden = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1.0
            contentView.animator().frame = NSRect(origin: .zero, size: targetSize)
            contentView.layer?.cornerRadius = targetSize.height / 2
            contentView.layer?.backgroundColor = NSColor.colorWith(hex: 0x1455D9, alpha: 0.88).cgColor
            contentView.layer?.borderWidth = 1.0
            contentView.layer?.borderColor = NSColor.colorWith(hex: 0xFFFFFF, alpha: 0.34).cgColor

            iconLabel.isHidden = false
            iconLabel.animator().alphaValue = 1
            iconLabel.stringValue = "•"
            iconLabel.font = NSFont.systemFont(ofSize: 18, weight: .heavy)
            iconLabel.textColor = .white

            textLabel.stringValue = label
            textLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            textLabel.textColor = .white.withAlphaComponent(0.92)
            textLabel.isHidden = label.isEmpty
            textLabel.animator().alphaValue = label.isEmpty ? 0 : 1
            layoutLabels(
                iconLabel: iconLabel,
                textLabel: textLabel,
                in: targetSize,
                hasTitle: !label.isEmpty,
                animated: true
            )
        }
        panel.orderFrontRegardless()
    }

    func hideComputerUseCursor() {
        exitComputerUseCursorMode(restoreFrame: true)
    }

    func ensureVisible(config: AppConfig) {
        setState(state, config: config)
    }

    /// Refresh the idle icon to match the user's selected menu bar icon.
    func refreshIcon() {
        let config = configStore.load()
        let fallback = NSImage(systemSymbolName: "waveform.badge.microphone", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) ?? NSImage()
        let newImage = MenuBarIconRenderer.make(choice: config.menuBarIcon) ?? fallback
        newImage.isTemplate = false
        micIconView?.image = newImage
    }

    /// Flash a brief warning message on the indicator pill, then snap back to idle.
    func showWarning(_ message: String, icon: String = "⚡", duration: TimeInterval = 2.5) {
        guard state == .idle else { return }
        let config = configStore.load()
        if panel == nil { createPanel(config: config) }
        guard let panel, let contentView, let iconLabel, let textLabel else { return }
        guard let screen = NSScreen.main?.visibleFrame else { return }

        let warningFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let warningSize = warningPillSize(
            message: message,
            icon: icon,
            font: warningFont,
            screen: screen
        )
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let x = min(max(center.x - warningSize.width / 2, screen.minX), screen.maxX - warningSize.width)
        let y = min(max(center.y - warningSize.height / 2, screen.minY), screen.maxY - warningSize.height)
        let targetFrame = NSRect(x: x, y: y, width: warningSize.width, height: warningSize.height)

        // Warning uses its own solid amber background — hide glass layers.
        glassView?.isHidden = true
        tintLayer?.isHidden = true
        micIconView?.isHidden = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1.0
            contentView.animator().frame = NSRect(origin: .zero, size: warningSize)
            contentView.layer?.cornerRadius = warningSize.height / 2
            contentView.layer?.backgroundColor = NSColor.colorWith(hex: 0xD99A11, alpha: 0.92).cgColor
            contentView.layer?.borderWidth = 1.0
            contentView.layer?.borderColor = NSColor.colorWith(hex: 0xFFFFFF, alpha: 0.24).cgColor

            let hasIcon = !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            iconLabel.isHidden = !hasIcon
            iconLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
            iconLabel.stringValue = icon
            iconLabel.textColor = NSColor.colorWith(hex: 0x1A140D, alpha: 0.95)
            iconLabel.animator().alphaValue = hasIcon ? 1 : 0

            textLabel.stringValue = message
            textLabel.font = warningFont
            textLabel.textColor = NSColor.colorWith(hex: 0x1A140D, alpha: 0.95)
            textLabel.isHidden = false
            textLabel.animator().alphaValue = 1
            layoutLabels(iconLabel: iconLabel, textLabel: textLabel, in: warningSize, hasTitle: true, animated: true)
        }
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.state == .idle else { return }
            self.setState(.idle, config: self.configStore.load())
        }
    }

    private func warningPillSize(message: String, icon: String, font: NSFont, screen: NSRect) -> NSSize {
        let horizontalPadding: CGFloat = 18
        let hasIcon = !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let iconWidth = hasIcon
            ? max(24, ceil((icon as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold)]).width) + 2)
            : 0
        let iconGap: CGFloat = hasIcon ? 4 : 0
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width) + 2
        let preferredWidth = horizontalPadding + iconWidth + iconGap + textWidth + horizontalPadding
        let minWidth: CGFloat = hasIcon ? 180 : 88
        let maxWidth = max(minWidth, min(640, screen.width - 32))
        return NSSize(width: min(max(preferredWidth, minWidth), maxWidth), height: 36)
    }

    func showLoading(_ message: String) {
        let config = configStore.load()
        if panel == nil { createPanel(config: config) }
        guard let panel, let contentView, let textLabel else { return }
        guard let screen = NSScreen.main?.visibleFrame else { return }

        isShowingLoading = true
        let loadingSize = loadingPillSize(message: message, screen: screen)
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let x = min(max(center.x - loadingSize.width / 2, screen.minX), screen.maxX - loadingSize.width)
        let y = min(max(center.y - loadingSize.height / 2, screen.minY), screen.maxY - loadingSize.height)
        let targetFrame = NSRect(x: x, y: y, width: loadingSize.width, height: loadingSize.height)

        // Create spinner if needed
        if loadingSpinner == nil {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isIndeterminate = true
            spinner.appearance = NSAppearance(named: .darkAqua)
            contentView.addSubview(spinner)
            loadingSpinner = spinner
        }

        let spinnerSize: CGFloat = 16
        let gap: CGFloat = 8
        let horizontalPadding: CGFloat = 16
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]
        let measuredTextW = ceil((message as NSString).size(withAttributes: attrs).width) + 2
        let availableTextW = max(40, loadingSize.width - (horizontalPadding * 2) - spinnerSize - gap)
        let textW = min(measuredTextW, availableTextW)
        let totalW = spinnerSize + gap + textW
        let startX = max(horizontalPadding, (loadingSize.width - totalW) / 2)

        micIconView?.isHidden = true
        wandIconView?.isHidden = true
        iconLabel?.isHidden = true
        setWaveBarsHidden(true)
        glassView?.isHidden = false
        tintLayer?.isHidden = false
        tintLayer?.backgroundColor = NSColor.colorWith(hexString: "1e1e1e", alpha: 0.72).cgColor
        applyTintLayerGeometry(size: loadingSize, radius: loadingSize.height / 2)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1.0
            contentView.animator().frame = NSRect(origin: .zero, size: loadingSize)
            contentView.layer?.cornerRadius = loadingSize.height / 2
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
            contentView.layer?.borderWidth = 1.0
            contentView.layer?.borderColor = NSColor.colorWith(hex: 0xFFFFFF, alpha: 0.16).cgColor

            loadingSpinner?.frame = NSRect(
                x: startX, y: (loadingSize.height - spinnerSize) / 2,
                width: spinnerSize, height: spinnerSize
            )
            loadingSpinner?.isHidden = false
            loadingSpinner?.startAnimation(nil)

            textLabel.stringValue = message
            textLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.maximumNumberOfLines = 1
            textLabel.usesSingleLineMode = true
            textLabel.cell?.wraps = false
            textLabel.cell?.isScrollable = false
            textLabel.textColor = NSColor.colorWith(hex: 0xFFFFFF, alpha: 0.82)
            textLabel.frame = NSRect(
                x: startX + spinnerSize + gap,
                y: (loadingSize.height - 14) / 2,
                width: textW, height: 14
            )
            textLabel.isHidden = false
            textLabel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
    }

    private func loadingPillSize(message: String, screen: NSRect) -> NSSize {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let spinnerSize: CGFloat = 16
        let gap: CGFloat = 8
        let horizontalPadding: CGFloat = 16
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width) + 2
        let preferredWidth = horizontalPadding + spinnerSize + gap + textWidth + horizontalPadding
        let minWidth = min(CGFloat(180), max(120, screen.width - 32))
        let maxWidth = max(minWidth, min(360, screen.width - 32))
        return NSSize(width: min(max(preferredWidth, minWidth), maxWidth), height: 36)
    }

    func hideLoading() {
        guard isShowingLoading else { return }
        isShowingLoading = false
        loadingSpinner?.stopAnimation(nil)
        loadingSpinner?.isHidden = true
        // Only reset to idle if no dictation started during the warmup window
        if state == .idle || state == .preparing {
            setState(.idle, config: configStore.load())
        }
    }

    func setHovered(_ hovered: Bool) {
        // Hover expands the idle launcher AND the recording control pill.
        guard state != .transcribing, !isShowingLoading, !isDragging, isHovered != hovered else { return }
        hoverExitWorkItem?.cancel()
        if hovered, hoverAnchorTop == nil {
            hoverAnchorTop = panel?.frame.maxY
        }
        isHovered = hovered
        let config = configStore.load()
        // Leaving the launcher: fade the circles out FIRST, then run the
        // shrink morph — hiding them at morph start reads as a hard cut.
        if !hovered, let launcher = launcherView, !launcher.isHidden, launcher.alphaValue > 0.01 {
            morphGeneration += 1
            let generation = morphGeneration
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                launcher.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.morphGeneration == generation, !self.isHovered else { return }
                self.setState(self.state, config: config)
                self.hoverAnchorTop = nil
            })
            return
        }
        setState(state, config: config)
        if !hovered {
            hoverAnchorTop = nil
        }
    }

    /// A plain click on the idle strip collapses it via collapseForDrag;
    /// reopen the launcher if the cursor is still over the pill.
    func restoreHoverAfterClick() {
        guard state == .idle, !isShowingLoading, pointerIsInsidePanel() else { return }
        setHovered(true)
    }

    func scheduleHoverExit() {
        guard state != .transcribing, !isShowingLoading, isHovered else { return }
        hoverExitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.pointerIsInsideActiveHoverRegion() else { return }
            self.setHovered(false)
        }
        hoverExitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    func closeIfIdle() {
        if state == .idle, !isShowingLoading { close() }
    }

    func close() {
        stopWaveformAnimation()
        hoverExitWorkItem?.cancel()
        hoverExitWorkItem = nil
        stripSpinnerLayer = nil
        dotsHostView?.removeFromSuperview()
        dotsHostView = nil
        panel?.close()
        panel = nil
        contentView = nil
        iconLabel = nil
        textLabel = nil
        glassView = nil
        tintLayer = nil
        micIconView = nil
        wandIconView = nil
        launcherView?.removeFromSuperview()
        launcherView = nil
    }

    private func removeStopLayer() {
        stopLayer?.removeFromSuperlayer()
        stopLayer = nil
    }

    private func stopWaveformAnimation() {
        amplitudeTimer?.invalidate()
        amplitudeTimer = nil
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll()
        removeStripSpinner()
        dotsHostView?.isHidden = true
        waveGroupSignature = ""
        smoothedDictationAmplitude = 0
        smoothedMeetingAmplitude = 0
        waveformAnimationMode = .level
        contentView?.layer?.transform = CATransform3DIdentity
        removeStopLayer()
    }

    // MARK: - Wave dot groups (one group of 3 per active capture mode)

    private struct WaveGroupSpec: Equatable {
        let colorHexKey: String
        let usesMeetingLevel: Bool
    }

    /// One 3-dot group per active mode: white = dictation, orange = meeting
    /// audio, red = meeting with video. Preparing/legacy flows fall back to a
    /// single white group.
    private func activeWaveGroupSpecs() -> [WaveGroupSpec] {
        var specs: [WaveGroupSpec] = []
        if isDictationCapturing {
            specs.append(WaveGroupSpec(colorHexKey: "dictation", usesMeetingLevel: false))
        }
        if isMeetingRecording {
            specs.append(WaveGroupSpec(
                colorHexKey: isMeetingVideoRecording ? "video" : "audio",
                usesMeetingLevel: true
            ))
        }
        if specs.isEmpty {
            specs.append(WaveGroupSpec(colorHexKey: "dictation", usesMeetingLevel: false))
        }
        return specs
    }

    /// Capture palette: saturated (not pastel) orange/red pinned near the
    /// accent's brightness — vivid enough to read as "live"; the glyph on
    /// these fills stays white.
    static let captureOrange = NSColor(calibratedRed: 0.961, green: 0.573, blue: 0.118, alpha: 1)
    static let captureRed = NSColor(calibratedRed: 0.937, green: 0.294, blue: 0.294, alpha: 1)

    private func waveColor(forKey key: String) -> NSColor {
        switch key {
        case "video": return Self.captureRed
        case "audio": return Self.captureOrange
        default: return .white.withAlphaComponent(0.85)
        }
    }

    private let waveBarsPerGroup = 3
    private let waveBarWidth: CGFloat = 2
    private let waveBarSpacing: CGFloat = 2
    private let waveGroupGap: CGFloat = 3

    /// The dots' own view, re-asserted ABOVE the glass on every rebuild so
    /// AppKit's subview ordering guarantees keep them visible.
    private func ensureDotsHost() -> NSView? {
        guard let contentView else { return nil }
        let host: NSView
        if let existing = dotsHostView {
            host = existing
        } else {
            host = NSView(frame: NSRect(x: 0, y: 0, width: 43, height: 7))
            host.wantsLayer = true
            host.layer?.masksToBounds = false
            dotsHostView = host
        }
        if let glassView {
            contentView.addSubview(host, positioned: .above, relativeTo: glassView)
        } else {
            contentView.addSubview(host)
        }
        host.frame = NSRect(x: 0, y: 0, width: 43, height: 7)
        return host
    }

    private func setupWaveformBars(in frameSize: NSSize) {
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll()
        removeStripSpinner()
        guard let layer = ensureDotsHost()?.layer else { return }
        // Visibility is decided in the SAME place as the rebuild, from state —
        // never left to whatever ran last.
        dotsHostView?.isHidden = isHovered

        // Dots live only in the collapsed 43×7 strip (the expanded pill shows
        // the launcher instead) — lay them out for the strip regardless of the
        // frame the rebuild happened in.
        let stripSize = NSSize(width: 43, height: 7)
        _ = frameSize
        let specs = activeWaveGroupSpecs()
        waveGroupSignature = specs.map(\.colorHexKey).joined(separator: "|")
        let groupWidth = CGFloat(waveBarsPerGroup) * waveBarWidth + CGFloat(waveBarsPerGroup - 1) * waveBarSpacing
        let totalWidth = CGFloat(specs.count) * groupWidth + CGFloat(max(0, specs.count - 1)) * waveGroupGap
        var x = (stripSize.width - totalWidth) / 2
        for spec in specs {
            let color = waveColor(forKey: spec.colorHexKey)
            for _ in 0..<waveBarsPerGroup {
                let bar = CALayer()
                bar.backgroundColor = color.cgColor
                bar.cornerRadius = waveBarWidth / 2
                bar.frame = CGRect(x: x, y: (stripSize.height - 2) / 2, width: waveBarWidth, height: 2)
                layer.addSublayer(bar)
                barLayers.append(bar)
                x += waveBarWidth + waveBarSpacing
            }
            x += waveGroupGap - waveBarSpacing
        }
    }

    private func setWaveBarsHidden(_ hidden: Bool, fade: TimeInterval? = nil) {
        guard let host = dotsHostView else { return }
        guard let fade else {
            host.isHidden = hidden
            host.alphaValue = 1
            return
        }
        if hidden {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fade
                host.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let host = self?.dotsHostView else { return }
                host.isHidden = true
                host.alphaValue = 1
            })
        } else {
            host.alphaValue = 0
            host.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fade
                host.animator().alphaValue = 1
            }
        }
    }

    /// Expand hides the dots instantly; a collapse keeps
    /// them hidden until finishHoverMorph re-shows them after the shrink —
    /// dots overlapping a running morph read as smearing.
    private func applyCollapsedDotsVisibility(wasRenderedHovered: Bool) {
        if isHovered {
            // Instant hide: any fade reads as dots flying to the grown
            // frame's bottom while the panel resizes.
            setWaveBarsHidden(true)
        } else if wasRenderedHovered {
            setWaveBarsHidden(true)
        } else {
            setWaveBarsHidden(false)
        }
    }

    /// Runs after an animated state/hover morph settles: only now do the
    /// launcher icons appear (expand) or the wave dots return (collapse).
    private func finishHoverMorph() {
        statusHiddenForMorph = false
        let isCaptureState = state == .recording || state == .preparing
        if isHovered, isCaptureState || state == .idle {
            updateLauncher(
                visible: true,
                frameSize: contentView?.bounds.size ?? .zero,
                fadeIn: true
            )
        } else if !isHovered, isCaptureState || (state == .idle && processingStatus != nil) {
            setWaveBarsHidden(false, fade: 0.06)
        }
        refreshCollapsedStrip()
    }

    private func ensureWaveformAnimation(in frameSize: NSSize, mode: WaveformAnimationMode) {
        // Rebuild whenever the set of active modes (groups) changes.
        let signature = activeWaveGroupSpecs().map(\.colorHexKey).joined(separator: "|")
        if barLayers.isEmpty || signature != waveGroupSignature {
            setupWaveformBars(in: frameSize)
        }
        setWaveformAnimationMode(mode)
        if amplitudeTimer == nil {
            startWaveformAnimation(mode: mode)
        }
    }

    private func setWaveformAnimationMode(_ mode: WaveformAnimationMode) {
        guard waveformAnimationMode != mode else { return }
        waveformAnimationMode = mode
        waveformAnimationStartedAt = Date()
    }

    private func startWaveformAnimation(mode: WaveformAnimationMode) {
        amplitudeTimer?.invalidate()
        waveformAnimationMode = mode
        waveformAnimationStartedAt = Date()
        let timer = Timer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(waveformTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        amplitudeTimer = timer
    }

    @objc private func waveformTimerFired(_ timer: Timer) {
        guard !barLayers.isEmpty else { return }
        // Dots render only inside the collapsed 43×7 strip.
        let stripHeight: CGFloat = 7
        let minHeight: CGFloat = 1
        let maxHeight: CGFloat = 5
        let groupMultipliers: [CGFloat] = [0.7, 1.0, 0.7]
        let elapsed = CGFloat(Date().timeIntervalSince(waveformAnimationStartedAt))

        // Each active mode drives its own group from its own level source.
        func smoothedLevel(meeting: Bool) -> CGFloat {
            let dB = CGFloat((meeting ? meetingPowerProvider : dictationPowerProvider)?() ?? -160)
            let raw = max(0, min(1, (dB + 68) / 38))
            if meeting {
                smoothedMeetingAmplitude = 0.48 * raw + 0.52 * smoothedMeetingAmplitude
                return smoothedMeetingAmplitude
            }
            smoothedDictationAmplitude = 0.48 * raw + 0.52 * smoothedDictationAmplitude
            return smoothedDictationAmplitude
        }

        let specs = activeWaveGroupSpecs()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in barLayers.enumerated() {
            let groupIndex = i / waveBarsPerGroup
            let barInGroup = i % waveBarsPerGroup
            let m = groupMultipliers[barInGroup]
            let usesMeetingLevel = groupIndex < specs.count && specs[groupIndex].usesMeetingLevel
            let amplitude: CGFloat
            switch waveformAnimationMode {
            case .level:
                amplitude = smoothedLevel(meeting: usesMeetingLevel) * m
                bar.opacity = 0.9
            case .waiting:
                let phase = elapsed * 5.8 + CGFloat(i) * 0.72
                amplitude = 0.28 + (sin(phase) + 1) * 0.22 * m
                bar.opacity = Float(0.38 + (sin(phase) + 1) * 0.18)
            }
            let h = minHeight + (maxHeight - minHeight) * amplitude
            bar.frame.size.height = h
            bar.frame.origin.y = (stripHeight - h) / 2
        }
        CATransaction.commit()
    }

    private func applyGlassState(
        _ state: DictationState,
        frameSize: NSSize,
        tintAnimationDuration: TimeInterval? = nil,
        wasRenderedHovered: Bool = false
    ) {
        let radius = frameSize.height / 2

        // Frosted glass in every state — the recording pill was the only one
        // without blur and looked flat against busy backgrounds.
        //
        // Unified hover geometry: while a capture state is hovered, the glass
        // is confined to a top-anchored 44pt capsule (same as the idle hover
        // morph) so the launcher captions below render OUTSIDE the glass.
        // Any hovered launcher state (idle included — e.g. right after a
        // capture stops under the cursor) keeps the top 44pt capsule.
        let capsuleHover = isHovered && state != .transcribing
        let glassRect: NSRect
        let glassRadius: CGFloat
        if capsuleHover {
            glassRect = NSRect(x: 0, y: frameSize.height - 44, width: frameSize.width, height: 44)
            glassRadius = 22
        } else {
            glassRect = NSRect(origin: .zero, size: frameSize)
            glassRadius = radius
        }
        glassView?.isHidden = false
        glassView?.frame = glassRect
        glassView?.layer?.cornerRadius = glassRadius
        glassView?.layer?.masksToBounds = true

        let tintAlpha: CGFloat
        let tintHex: String
        switch state {
        case .idle:
            tintAlpha = isHovered ? 0.45 : 0.22
            tintHex = "1e1e1e"
        case .preparing:
            tintAlpha = 0.45
            tintHex = "1e1e1e"
        case .recording:
            // Same style as the hover launcher; the stop square carries
            // the mode color instead.
            tintAlpha = 0.45
            tintHex = "1e1e1e"
        case .transcribing:
            tintAlpha = 0.45
            tintHex = "1e1e1e"
        }
        tintLayer?.isHidden = false
        tintLayer?.backgroundColor = NSColor.colorWith(hexString: tintHex, alpha: tintAlpha).cgColor
        // The single hairline border sits on the tint itself, so no dark rim
        // of the tint edge shows outside a separate content-view border.
        tintLayer?.borderWidth = 1
        tintLayer?.borderColor = NSColor.colorWith(hex: 0xFFFFFF, alpha: 0.12).cgColor
        glassView?.layer?.borderWidth = 1
        glassView?.layer?.borderColor = NSColor.colorWith(hex: 0xFFFFFF, alpha: 0.12).cgColor
        applyTintLayerGeometry(rect: glassRect, radius: glassRadius, animationDuration: tintAnimationDuration)

        let iconSize = NSSize(width: 18, height: 18)

        switch state {
        case .idle:
            // Collapsed idle is a bare thin strip; hover shows the launcher.
            wandIconView?.isHidden = true
            iconLabel?.isHidden = true
            micIconView?.isHidden = true
            refreshLauncherIfVisible(frameSize: frameSize, wasRenderedHovered: wasRenderedHovered)

        case .recording:
            // Collapsed: dot groups only. Expanded: the stateful launcher
            // (toggle circles + cancel) hosts every control.
            wandIconView?.isHidden = true
            iconLabel?.isHidden = true
            micIconView?.isHidden = true
            refreshLauncherIfVisible(frameSize: frameSize, wasRenderedHovered: wasRenderedHovered)

        case .transcribing:
            // Animated wand beside "Transcribing" label, the pair centred in the pill.
            micIconView?.isHidden = true
            iconLabel?.isHidden = true
            wandIconView?.isHidden = false
            if computerUseTranscriptText != nil {
                layoutComputerUseTranscript(in: frameSize, animated: false)
                return
            }
            if let wand = wandIconView {
                let gap: CGFloat = 6
                let horizontalPadding: CGFloat = 14
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .regular)
                ]
                let measuredTextW = max(
                    ceil((transcribingTitle as NSString).size(withAttributes: attrs).width),
                    ceil(textLabel?.intrinsicContentSize.width ?? 0)
                ) + 8
                let availableTextW = max(0, frameSize.width - iconSize.width - gap - (horizontalPadding * 2))
                let textW = min(measuredTextW, availableTextW)
                let totalW = iconSize.width + gap + textW
                let startX = (frameSize.width - totalW) / 2
                wand.frame = NSRect(x: startX, y: (frameSize.height - iconSize.height) / 2,
                                    width: iconSize.width, height: iconSize.height)
                // Reposition text label to sit right of the wand.
                let textH: CGFloat = 14
                textLabel?.frame = NSRect(x: startX + iconSize.width + gap,
                                          y: (frameSize.height - textH) / 2,
                                          width: textW, height: textH)
                textLabel?.isHidden = false
                textLabel?.alphaValue = 1
            }

        case .preparing:
            wandIconView?.isHidden = true
            iconLabel?.isHidden = true
            micIconView?.isHidden = true
            refreshLauncherIfVisible(frameSize: frameSize, wasRenderedHovered: wasRenderedHovered)
        }
    }

    private func configureTextLabelForTranscript(_ isTranscript: Bool) {
        guard let textLabel else { return }
        Self.configureTextLabel(textLabel, forTranscript: isTranscript)
    }

    private static func configureTextLabel(_ textLabel: NSTextField, forTranscript isTranscript: Bool) {
        textLabel.alignment = .left
        if isTranscript {
            textLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            textLabel.lineBreakMode = .byWordWrapping
            textLabel.maximumNumberOfLines = 0
            textLabel.usesSingleLineMode = false
            textLabel.cell?.wraps = true
            textLabel.cell?.isScrollable = false
        } else {
            textLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.maximumNumberOfLines = 1
            textLabel.usesSingleLineMode = true
            textLabel.cell?.wraps = false
            textLabel.cell?.isScrollable = false
        }
    }

    private func layoutComputerUseTranscript(in size: NSSize, animated: Bool) {
        guard let wand = wandIconView, let textLabel else { return }
        let iconSize = NSSize(width: 18, height: 18)
        let gap: CGFloat = 8
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 12
        let textX = horizontalPadding + iconSize.width + gap
        let textWidth = max(40, size.width - textX - horizontalPadding)
        let textHeight = max(16, size.height - (verticalPadding * 2))
        let textFrame = NSRect(
            x: textX,
            y: floor((size.height - textHeight) / 2),
            width: textWidth,
            height: textHeight
        )
        let iconFrame = NSRect(
            x: horizontalPadding,
            y: floor(size.height - verticalPadding - iconSize.height),
            width: iconSize.width,
            height: iconSize.height
        )

        wand.isHidden = false
        textLabel.isHidden = false
        if animated {
            wand.animator().alphaValue = 1
            wand.animator().frame = iconFrame
            textLabel.animator().alphaValue = 1
            textLabel.animator().frame = textFrame
        } else {
            wand.alphaValue = 1
            wand.frame = iconFrame
            textLabel.alphaValue = 1
            textLabel.frame = textFrame
        }
    }

    private func createPanel(config: AppConfig) {
        let panel = NSPanel(
            contentRect: frameForState(.idle, config: config),
            // .nonactivatingPanel is load-bearing: without it a click on the
            // pill activates the app, the user's target app loses focus, and
            // the dictation paste (Cmd+V) lands nowhere.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No compositor shadow: on a tiny translucent strip it reads as a
        // dark outline and its cached contour lags behind instant resizes.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let contentView = HoverIndicatorView(frame: NSRect(origin: .zero, size: panel.frame.size))
        contentView.owner = self
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = panel.frame.height / 2
        contentView.layer?.masksToBounds = false

        let iconLabel = NSTextField(labelWithString: "")
        iconLabel.alignment = .center
        iconLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        contentView.addSubview(iconLabel)

        let textLabel = NSTextField(labelWithString: "")
        textLabel.alignment = .left
        textLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        Self.configureTextLabel(textLabel, forTranscript: false)
        contentView.addSubview(textLabel)

        panel.contentView = contentView

        self.panel = panel
        self.contentView = contentView
        self.iconLabel = iconLabel
        self.textLabel = textLabel

        setupGlassLayer(in: contentView, iconLabel: iconLabel)
    }

    private func exitComputerUseCursorMode(restoreFrame: Bool) {
        guard isComputerUseCursorMode else { return }
        isComputerUseCursorMode = false
        panel?.ignoresMouseEvents = false
        panel?.level = .floating
        if restoreFrame, let frame = computerUseCursorReturnFrame {
            panel?.setFrame(frame, display: true)
            contentView?.frame = NSRect(origin: .zero, size: frame.size)
        }
        computerUseCursorReturnFrame = nil
    }

    private static func cursorLabel(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 24 { return trimmed }
        return String(trimmed.prefix(21)) + "..."
    }

    private static func computerUseCursorSize(label: String) -> NSSize {
        guard !label.isEmpty else {
            return NSSize(width: 36, height: 36)
        }
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        return NSSize(width: min(max(84, textWidth + 48), 190), height: 34)
    }

    private static func computerUseCursorFrame(
        forQuartzPoint point: CGPoint,
        size: NSSize,
        offsetFromTarget: Bool
    ) -> NSRect {
        let screen = NSScreen.screens.first { screen in
            let convertedY = screen.frame.maxY - point.y
            return point.x >= screen.frame.minX
                && point.x <= screen.frame.maxX
                && convertedY >= screen.frame.minY
                && convertedY <= screen.frame.maxY
        } ?? NSScreen.main

        guard let screen else {
            return NSRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        let appKitPoint = CGPoint(x: point.x, y: screen.frame.maxY - point.y)
        let xOffset: CGFloat = offsetFromTarget ? 14 : 0
        let yOffset: CGFloat = offsetFromTarget ? 14 : 0
        let proposed = NSRect(
            x: appKitPoint.x - size.width / 2 + xOffset,
            y: appKitPoint.y - size.height / 2 - yOffset,
            width: size.width,
            height: size.height
        )
        let bounds = screen.visibleFrame.insetBy(dx: 4, dy: 4)
        return NSRect(
            x: min(max(proposed.minX, bounds.minX), bounds.maxX - size.width),
            y: min(max(proposed.minY, bounds.minY), bounds.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private func setupGlassLayer(in contentView: HoverIndicatorView, iconLabel: NSTextField) {
        // masksToBounds clips both the glass blur and the tint layer to the pill shape.
        // The panel's compositor-level shadow is unaffected.
        contentView.layer?.masksToBounds = true

        // NSVisualEffectView — frosted blur behind the pill.
        let vev = NSVisualEffectView(frame: contentView.bounds)
        vev.autoresizingMask = [.width, .height]
        vev.material = .hudWindow
        vev.blendingMode = .behindWindow
        vev.state = .active
        // Force dark appearance so the glass always looks dark regardless of
        // what's behind the pill (light windows, bright desktops, etc.).
        vev.appearance = NSAppearance(named: .darkAqua)
        vev.isHidden = true
        contentView.addSubview(vev, positioned: .below, relativeTo: iconLabel)
        glassView = vev

        // Neutral dark graphite tint over the blur — gives the pill a defined
        // dark glass presence rather than showing everything underneath.
        // Deliberately zero blue dominance: during morphs the glass hides and
        // the bare tint shows, so any blue channel reads as a blue flash.
        let tint = CALayer()
        tint.backgroundColor = NSColor.colorWith(hex: 0x1e1e1e, alpha: 0.44).cgColor
        tint.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        tint.masksToBounds = false
        tint.cornerCurve = .continuous
        tint.isHidden = true
        contentView.layer?.insertSublayer(tint, at: 0)
        tintLayer = tint

        // Idle icon — uses the user's selected menu bar icon from config.
        // Falls back to waveform.badge.microphone if the configured icon can't be loaded.
        let config = configStore.load()
        let fallbackImage = NSImage(systemSymbolName: "waveform.badge.microphone", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) ?? NSImage()
        let idleImage = MenuBarIconRenderer.make(choice: config.menuBarIcon) ?? fallbackImage
        idleImage.isTemplate = false // we tint manually via contentTintColor
        let micView = NSImageView(image: idleImage)
        micView.contentTintColor = .white
        micView.imageScaling = .scaleProportionallyDown
        micView.isHidden = true
        contentView.addSubview(micView)
        micIconView = micView

        // wand.and.sparkles — transcribing (animated).
        let wandConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let wandImage = NSImage(systemSymbolName: "wand.and.sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(wandConfig)
        let wandView = NSImageView(image: wandImage ?? NSImage())
        wandView.contentTintColor = .white
        wandView.imageScaling = .scaleProportionallyDown
        wandView.isHidden = true
        contentView.addSubview(wandView)
        wandIconView = wandView

    }

    // MARK: - Processing status inside the strip

    /// Post-processing stage (transcribe/summarize/…) rendered as tiny text
    /// INSIDE the collapsed 43×7 strip, behind the wave dots. nil hides it.
    /// Never touches the pill's phase, so the launcher and captures stay
    /// fully usable during processing.
    func setProcessingStatus(_ status: String?, kind: ProcessingKind? = nil) {
        let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines)
        processingStatus = (trimmed?.isEmpty ?? true) ? nil : trimmed
        // nil kind = keep the current one (status restores after dictation).
        if processingStatus != nil, let kind {
            processingKind = kind
        }
        refreshCollapsedStrip()
        // The launcher ring/caption reflect the stage live while open.
        refreshLauncherIfVisible(
            frameSize: contentView?.bounds.size ?? .zero,
            wasRenderedHovered: isHovered
        )
    }

    /// Status changes arrive outside setState — swap the strip content
    /// between the mini loader and nothing without a full state repaint.
    private func refreshCollapsedStrip() {
        guard panel != nil else { return }
        let hasCapture = isDictationCapturing || isMeetingRecording
        if state == .idle, !hasCapture {
            if processingStatus != nil {
                ensureStripSpinner()
                if !isHovered, !statusHiddenForMorph {
                    setWaveBarsHidden(false)
                }
            } else {
                stopWaveformAnimation()
            }
        }
    }

    private var processingKindColor: NSColor {
        switch processingKind {
        case .meetingAudio: return Self.captureOrange
        case .meetingVideo: return Self.captureRed
        case .dictation: return NSColor.white.withAlphaComponent(0.9)
        }
    }

    /// The collapsed-strip analogue of the recording dots while a capture is
    /// post-processing: a tiny spinning color arc centered in the strip.
    private func ensureStripSpinner() {
        guard let host = ensureDotsHost() else { return }
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll()
        amplitudeTimer?.invalidate()
        amplitudeTimer = nil
        waveGroupSignature = ""
        if stripSpinnerLayer == nil {
            let size: CGFloat = 6
            let ring = CAShapeLayer()
            ring.frame = CGRect(x: (43 - size) / 2, y: (7 - size) / 2, width: size, height: size)
            let arc = CGMutablePath()
            arc.addArc(
                center: CGPoint(x: size / 2, y: size / 2),
                radius: 2.4,
                startAngle: 0,
                endAngle: .pi * 1.25,
                clockwise: false
            )
            ring.path = arc
            ring.fillColor = nil
            ring.lineWidth = 1.2
            ring.lineCap = .round
            host.layer?.addSublayer(ring)
            stripSpinnerLayer = ring
        }
        stripSpinnerLayer?.strokeColor = processingKindColor.cgColor
        if stripSpinnerLayer?.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 0.9
            spin.repeatCount = .infinity
            stripSpinnerLayer?.add(spin, forKey: "spin")
        }
    }

    private func removeStripSpinner() {
        stripSpinnerLayer?.removeFromSuperlayer()
        stripSpinnerLayer = nil
    }

    private func applyTintLayerGeometry(rect: NSRect, radius: CGFloat, animationDuration: TimeInterval? = nil) {
        guard let tint = tintLayer else { return }
        // Set position/bounds (frame is derived state) so the change can be
        // animated in sync with the NSView morph — a snapped tint exposes a
        // band of un-tinted blur while the glass is still animating.
        let anchor = tint.anchorPoint
        let targetPosition = CGPoint(
            x: rect.minX + anchor.x * rect.width,
            y: rect.minY + anchor.y * rect.height
        )
        let targetBounds = CGRect(origin: .zero, size: rect.size)
        let presentation = tint.presentation()
        let fromPosition = presentation?.position ?? tint.position
        let fromBounds = presentation?.bounds ?? tint.bounds
        let fromRadius = presentation?.cornerRadius ?? tint.cornerRadius

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tint.position = targetPosition
        tint.bounds = targetBounds
        tint.cornerRadius = radius
        tint.cornerCurve = .continuous
        if let animationDuration, animationDuration > 0.01, !tint.isHidden {
            let timing = CAMediaTimingFunction(name: .easeInEaseOut)
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(point: fromPosition)
            position.toValue = NSValue(point: targetPosition)
            let bounds = CABasicAnimation(keyPath: "bounds")
            bounds.fromValue = NSValue(rect: fromBounds)
            bounds.toValue = NSValue(rect: targetBounds)
            let corner = CABasicAnimation(keyPath: "cornerRadius")
            corner.fromValue = fromRadius
            corner.toValue = radius
            for (key, animation) in [("sync.position", position), ("sync.bounds", bounds), ("sync.cornerRadius", corner)] {
                animation.duration = animationDuration
                animation.timingFunction = timing
                tint.add(animation, forKey: key)
            }
        }
        CATransaction.commit()
    }

    private func applyTintLayerGeometry(size: NSSize, radius: CGFloat) {
        applyTintLayerGeometry(rect: CGRect(origin: .zero, size: size), radius: radius)
    }

    static func defaultIndicatorCenter(in visibleFrame: NSRect, idleSize: NSSize = NSSize(width: 44, height: 28)) -> CGPoint {
        anchorCenter(.midTrailing, in: visibleFrame, size: idleSize)
    }

    static func anchorCenter(_ anchor: IndicatorAnchor, in visibleFrame: NSRect, size: NSSize) -> CGPoint {
        let inset: CGFloat = 8
        let leadingX = visibleFrame.minX + size.width / 2 + inset
        let centerX = visibleFrame.midX
        let trailingX = visibleFrame.maxX - size.width / 2 - inset
        let topY = visibleFrame.maxY - size.height / 2 - inset
        let midY = visibleFrame.midY
        let bottomY = visibleFrame.minY + size.height / 2 + inset

        switch anchor {
        case .topLeading:
            return CGPoint(x: leadingX, y: topY)
        case .topCenter:
            return CGPoint(x: centerX, y: topY)
        case .topTrailing:
            return CGPoint(x: trailingX, y: topY)
        case .midLeading:
            return CGPoint(x: leadingX, y: midY)
        case .midTrailing:
            return CGPoint(x: trailingX, y: midY)
        case .bottomLeading:
            return CGPoint(x: leadingX, y: bottomY)
        case .bottomCenter:
            return CGPoint(x: centerX, y: bottomY)
        case .bottomTrailing:
            return CGPoint(x: trailingX, y: bottomY)
        case .custom:
            return defaultIndicatorCenter(in: visibleFrame, idleSize: size)
        }
    }

    static func isUsableIndicatorCenter(
        _ center: CGPoint,
        in visibleFrame: NSRect,
        size: NSSize
    ) -> Bool {
        let allowedRect = visibleFrame.insetBy(dx: size.width / 2, dy: size.height / 2)
        return allowedRect.contains(center)
    }

    private func frameForState(_ state: DictationState, config: AppConfig) -> NSRect {
        guard let screen = NSScreen.main?.visibleFrame else {
            return NSRect(x: 0, y: 0, width: 64, height: 28)
        }
        let size: NSSize
        switch state {
        case .idle:
            size = isHovered ? NSSize(width: 128, height: 74) : NSSize(width: 43, height: 7)
        // Collapsed recording is the exact idle-strip footprint with only the
        // per-mode dot groups inside; hovering expands to the stateful
        // launcher (wider when the cancel ✕ is shown).
        case .preparing, .recording:
            size = isHovered
                ? NSSize(width: 128, height: 74)
                : NSSize(width: 43, height: 7)
        case .transcribing:
            if let transcript = computerUseTranscriptText {
                size = Self.computerUseTranscriptPillSize(transcript: transcript, screen: screen)
            } else {
                size = Self.transcribingPillSize(title: transcribingTitle, screenWidth: screen.width)
            }
        }

        // Use the pill's current on-screen center if it exists, so state
        // transitions resize around the current position rather than jumping
        // for custom placement. Preset anchors always resolve from config so
        // changing the setting snaps immediately to the chosen anchor.
        let center: CGPoint
        if config.indicatorAnchor == .custom,
           let currentFrame = panel?.frame,
           currentFrame.width > 0 {
            center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        } else {
            switch config.indicatorAnchor {
            case .custom:
                if let saved = config.indicatorOrigin,
                   Self.isUsableIndicatorCenter(CGPoint(x: saved.x, y: saved.y), in: screen, size: size) {
                    center = CGPoint(x: saved.x, y: saved.y)
                } else {
                    center = Self.defaultIndicatorCenter(in: screen, idleSize: size)
                }
            default:
                center = Self.anchorCenter(config.indicatorAnchor, in: screen, size: size)
            }
        }

        let x = min(max(center.x - size.width / 2, screen.minX), screen.maxX - size.width)
        var y = min(max(center.y - size.height / 2, screen.minY), screen.maxY - size.height)
        if state == .idle || state == .recording, let top = hoverAnchorTop {
            // Expand/collapse strictly downward from the strip's top edge.
            y = min(max(top - size.height, screen.minY), screen.maxY - size.height)
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func styleForState(_ state: DictationState, config: AppConfig) -> (background: NSColor, border: NSColor, icon: String, title: String, iconColor: NSColor, textColor: NSColor, alpha: CGFloat) {
        switch state {
        case .idle:
            return (
                .clear,
                .colorWith(hex: 0xFFFFFF, alpha: 0.12),
                "",
                "",
                .colorWith(hex: 0xFFFFFF, alpha: 0.75),
                .colorWith(hex: 0xFFFFFF, alpha: 0.75),
                isHovered ? 1.0 : 0.85
            )
        case .preparing:
            return (.clear, .colorWith(hex: 0xFFFFFF, alpha: 0.12), "", "", .white, .white, 1.0)
        case .recording:
            return (
                .clear, .colorWith(hex: 0xFFFFFF, alpha: 0.12),
                isMeetingRecording ? "⏹" : "",
                isMeetingRecording ? "" : "",
                .white, .white, 1.0
            )
        case .transcribing:
            return (
                .clear, .colorWith(hex: 0xFFFFFF, alpha: 0.12),
                "", transcribingTitle,
                .white, .colorWith(hex: 0xFFFFFF, alpha: 0.82), 1.0
            )
        }
    }

    private func transitionDuration(from oldState: DictationState, to newState: DictationState, wasHovered: Bool, isHovered: Bool) -> TimeInterval {
        if newState == .preparing {
            // Launcher-started capture opens the expanded pill — animate that.
            return isHovered ? 0.24 : 0
        }
        if oldState == .preparing, newState == .recording {
            // Launcher-started recordings expand into the hover pill — animate.
            return isHovered ? 0.27 : 0
        }
        if oldState == .idle, newState == .idle, wasHovered != isHovered {
            return isHovered ? 0.36 : 0.3
        }
        if oldState == .idle || newState == .idle {
            return 0.27
        }
        return 0.24
    }

    private func layoutLabels(iconLabel: NSTextField, textLabel: NSTextField, in size: NSSize, hasTitle: Bool, animated: Bool) {
        if !hasTitle {
            let iconSize = iconLabel.attributedStringValue.size()
            let iconWidth = max(26, ceil(iconSize.width) + 4)
            let iconHeight = max(18, ceil(iconSize.height))
            let iconFrame = NSRect(
                x: (size.width - iconWidth) / 2,
                y: (size.height - iconHeight) / 2,
                width: iconWidth,
                height: iconHeight
            )
            if animated {
                iconLabel.animator().frame = iconFrame
                textLabel.animator().alphaValue = 0
                textLabel.animator().frame = .zero
            } else {
                iconLabel.frame = iconFrame
                textLabel.alphaValue = 0
                textLabel.frame = .zero
            }
            return
        }

        let iconSize = iconLabel.attributedStringValue.size()
        let textSize = textLabel.attributedStringValue.size()
        let hasIcon = !iconLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let gap: CGFloat = hasIcon ? 4 : 0
        let horizontalPadding: CGFloat = 12

        let iconWidth = hasIcon ? max(24, ceil(iconSize.width) + 2) : 0
        let iconHeight = max(18, ceil(iconSize.height))
        let availableTextWidth = max(0, size.width - (horizontalPadding * 2) - iconWidth - gap)
        let textWidth = min(ceil(textSize.width) + 2, availableTextWidth)
        let textHeight = max(16, ceil(textSize.height))

        let totalWidth = iconWidth + gap + textWidth
        let originX = max((size.width - totalWidth) / 2, horizontalPadding)

        let iconFrame = NSRect(
            x: originX,
            y: (size.height - iconHeight) / 2,
            width: iconWidth,
            height: iconHeight
        )
        let textFrame = NSRect(
            x: originX + iconWidth + gap,
            y: (size.height - textHeight) / 2,
            width: textWidth,
            height: textHeight
        )
        if animated {
            iconLabel.animator().alphaValue = hasIcon ? 1 : 0
            iconLabel.animator().frame = iconFrame
            textLabel.animator().alphaValue = 1
            textLabel.animator().frame = textFrame
        } else {
            iconLabel.alphaValue = hasIcon ? 1 : 0
            iconLabel.frame = iconFrame
            textLabel.alphaValue = 1
            textLabel.frame = textFrame
        }
    }

    static func transcribingPillSizeForTesting(title: String, screenWidth: CGFloat) -> NSSize {
        transcribingPillSize(title: title, screenWidth: screenWidth)
    }

    static func computerUseTranscriptPillSizeForTesting(
        transcript: String,
        screenWidth: CGFloat,
        screenHeight: CGFloat = 900
    ) -> NSSize {
        computerUseTranscriptPillSize(
            transcript: transcript,
            screen: NSRect(x: 0, y: 0, width: screenWidth, height: screenHeight)
        )
    }

    private static func transcribingPillSize(title: String, screenWidth: CGFloat) -> NSSize {
        let font = NSFont.systemFont(ofSize: 11, weight: .regular)
        let iconWidth: CGFloat = 18
        let gap: CGFloat = 6
        let horizontalPadding: CGFloat = 14
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 8
        let preferredWidth = horizontalPadding + iconWidth + gap + textWidth + horizontalPadding
        let minWidth = min(CGFloat(190), max(120, screenWidth - 32))
        let maxWidth = max(minWidth, min(420, screenWidth - 32))
        return NSSize(width: min(max(preferredWidth, minWidth), maxWidth), height: 32)
    }

    private static func computerUseTranscriptPillSize(transcript: String, screen: NSRect) -> NSSize {
        let normalized = normalizedComputerUseTranscript(transcript)
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let iconWidth: CGFloat = 18
        let gap: CGFloat = 8
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 12
        let chromeWidth = horizontalPadding + iconWidth + gap + horizontalPadding
        let minWidth = min(CGFloat(280), max(160, screen.width - 48))
        let maxWidth = max(minWidth, min(720, screen.width - 48))
        let singleLineTextWidth = ceil((normalized as NSString).size(withAttributes: [.font: font]).width) + 2
        let preferredWidth = min(maxWidth, max(minWidth, chromeWidth + singleLineTextWidth))
        let textWidth = max(40, preferredWidth - chromeWidth)
        let textHeight = transcriptTextHeight(normalized, font: font, width: textWidth)
        let maxHeight = max(CGFloat(56), screen.height - 48)
        let preferredHeight = max(CGFloat(44), ceil(textHeight) + (verticalPadding * 2))
        return NSSize(width: preferredWidth, height: min(preferredHeight, maxHeight))
    }

    private static func transcriptTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return max(16, ceil(bounding.height))
    }

    private static func normalizedComputerUseTranscript(_ transcript: String) -> String {
        transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func pointerIsInsidePanel() -> Bool {
        guard let panel else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    /// While the launcher is open, only the 44pt circle capsule keeps the
    /// hover alive — drifting down into the caption strip starts the collapse.
    private func pointerIsInsideActiveHoverRegion() -> Bool {
        guard let panel else { return false }
        var region = panel.frame
        if isHovered, launcherView?.isHidden == false,
           state == .idle || state == .recording || state == .preparing {
            region = NSRect(
                x: region.minX,
                y: region.maxY - 44,
                width: region.width,
                height: 44
            )
        }
        return region.contains(NSEvent.mouseLocation)
    }

    fileprivate func handleHoverMouseMoved() {
        guard isHovered, !isDragging else { return }
        if pointerIsInsideActiveHoverRegion() {
            hoverExitWorkItem?.cancel()
        } else {
            scheduleHoverExit()
        }
    }

    // MARK: - Hover launcher (dictation / meeting / meeting+video)

    /// Which launcher circle carries the processing ring (0 call /
    /// 1 dictation / 2 video).
    private var processingLauncherIndex: Int? {
        guard processingStatus != nil else { return nil }
        switch processingKind {
        case .meetingAudio: return 0
        case .dictation: return 1
        case .meetingVideo: return 2
        }
    }

    private func makeLauncherRoot() -> IndicatorLauncherView {
        IndicatorLauncherView(
            activeMeeting: isMeetingRecording && !isMeetingVideoRecording,
            activeDictation: isDictationCapturing,
            activeVideo: isMeetingVideoRecording,
            onDictation: { [weak self] in self?.togglePillDictation() },
            onMeeting: { [weak self] in self?.togglePillMeeting(video: false) },
            onMeetingVideo: { [weak self] in self?.togglePillMeeting(video: true) },
            onCancelDictation: { [weak self] in self?.onCancelToggleDictation?() },
            onCancelMeeting: { [weak self] in self?.onDiscardMeeting?() },
            processingIndex: processingLauncherIndex,
            processingCaption: processingStatus,
            revealToken: launcherRevealToken
        )
    }

    /// While expanded, state repaints refresh the launcher content in place;
    /// the initial reveal happens in finishHoverMorph after the morph so the
    /// icons never overlap the capsule animation.
    private func refreshLauncherIfVisible(frameSize: NSSize, wasRenderedHovered: Bool) {
        if isHovered {
            if wasRenderedHovered {
                updateLauncher(visible: true, frameSize: frameSize)
            }
        } else {
            updateLauncher(visible: false, frameSize: frameSize)
        }
    }

    private func updateLauncher(visible: Bool, frameSize: NSSize, fadeIn: Bool = false) {
        guard visible, let contentView else {
            // Keep the hidden tree CURRENT: a capture that ends while the
            // launcher is collapsed must not flash its stale "active" fill
            // on the next reveal (the hosting view is persistent).
            if let existing = launcherView as? LauncherHostingView<IndicatorLauncherView> {
                existing.rootView = makeLauncherRoot()
            }
            launcherView?.isHidden = true
            return
        }

        // One persistent hosting view: the rootView is UPDATED (not recreated)
        // so SwiftUI diffs internally — hover captions and the appear-fade
        // survive state changes instead of resetting on every render.
        if launcherView == nil || launcherView?.isHidden == true {
            launcherRevealToken += 1
        }
        let root = makeLauncherRoot()
        let host: LauncherHostingView<IndicatorLauncherView>
        if let existing = launcherView as? LauncherHostingView<IndicatorLauncherView> {
            existing.rootView = root
            host = existing
        } else {
            launcherView?.removeFromSuperview()
            host = LauncherHostingView(rootView: root)
            host.wantsLayer = true
            host.layer?.backgroundColor = .clear
            host.appearance = NSAppearance(named: .darkAqua)
            launcherView = host
        }
        // Keep the launcher topmost (above the dots host and glass).
        contentView.addSubview(host)
        host.frame = NSRect(origin: .zero, size: frameSize)
        let wasHidden = host.isHidden
        host.isHidden = false
        if fadeIn, wasHidden {
            // Post-morph reveal: quick fade once the capsule has settled.
            host.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                host.animator().alphaValue = 1
            }
        } else if !fadeIn {
            host.alphaValue = 1
        }
    }

    private var lastDictationToggleAt: Date = .distantPast

    private func togglePillDictation() {
        // Debounce: a second click before the session becomes active would
        // stop a near-empty recording (nothing to transcribe → no paste).
        let now = Date()
        guard now.timeIntervalSince(lastDictationToggleAt) > 0.5 else { return }
        lastDictationToggleAt = now
        if isDictationCapturing {
            onStopToggleDictation?()
        } else {
            startFromPill { [weak self] in self?.onStartDictation?() }
        }
    }

    private func togglePillMeeting(video: Bool) {
        if isMeetingRecording {
            // One meeting at a time: only the matching circle stops it.
            if isMeetingVideoRecording == video {
                onStopMeeting?()
            }
            return
        }
        startFromPill { [weak self] in
            if video {
                self?.onStartMeetingWithVideo?()
            } else {
                self?.onStartMeeting?()
            }
        }
    }

    /// ✕ = cancel: discards without transcription/summary. Cancels every
    /// active capture (dictation immediately; meeting with confirmation).
    private func startFromPill(_ action: @escaping () -> Void) {
        guard state == .idle || state == .recording else { return }
        hoverExitWorkItem?.cancel()
        let wasIdle = state == .idle
        action()
        // Failed start (permissions, etc.) leaves state at idle — restore the
        // strip/launcher instead of an empty expanded pill.
        if wasIdle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.state == .idle else { return }
                self.setState(.idle, config: self.configStore.load())
            }
        }
    }
}

/// Hosting view that reacts to the first click even while the panel isn't key.
private final class LauncherHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The pill's glass recipe (hudWindow blur, forced dark) as a SwiftUI
/// background — used by the launcher captions so they match the capsule.
/// The behind-window backdrop ignores SwiftUI clipping, so the capsule shape
/// comes from a native stretchable maskImage instead.
private struct HUDGlassCapsule: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.capsuleMask(radius: 11)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    private static func capsuleMask(radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Three quick-start circles shown when hovering the idle strip:
/// meeting (audio) / dictation / meeting with screen video.
/// Hovering a circle shows a caption capsule 4pt below the pill, centered
/// under that circle and styled like the pill itself.
private struct IndicatorLauncherView: View {
    var activeMeeting = false
    var activeDictation = false
    var activeVideo = false
    let onDictation: () -> Void
    let onMeeting: () -> Void
    let onMeetingVideo: () -> Void
    var onCancelDictation: (() -> Void)? = nil
    var onCancelMeeting: (() -> Void)? = nil
    /// Which circle is post-processing (0 call / 1 dictation / 2 video): it
    /// gets a spinning stage ring and its hover caption shows the stage.
    var processingIndex: Int? = nil
    var processingCaption: String? = nil
    /// Bumped on every fresh reveal — clears a caption stuck from the last
    /// session (a hidden hosting view never receives its hover-exit).
    var revealToken = 0
    @State private var hoveredIndex: Int?
    @State private var cancelHoveredIndex: Int?
    @State private var captionWidth: CGFloat = 0

    private var pillColor: Color { Color(red: 0.118, green: 0.118, blue: 0.118) }
    private let rowWidth: CGFloat = 128
    private var captions: [String] {
        [
            activeMeeting ? tr("Stop call", "Стоп звонок") : tr("Call", "Звонок"),
            activeDictation ? tr("Stop dictation", "Стоп диктовка") : tr("Dictation", "Диктовка"),
            activeVideo ? tr("Stop recording", "Стоп запись") : tr("Call with video", "Звонок с видео")
        ]
    }

    private var cancelCaptions: [String] {
        [tr("Cancel", "Отмена"), tr("Cancel", "Отмена"), tr("Cancel", "Отмена")]
    }

    private func captionText(for index: Int, isCancel: Bool) -> String {
        if isCancel { return cancelCaptions[index] }
        if index == processingIndex, let processingCaption {
            return processingCaption
        }
        return captions[index]
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                LauncherCircle(
                    systemName: "waveform",
                    activeColor: activeMeeting ? Color(nsColor: FloatingIndicatorController.captureOrange) : nil,
                    activeIconIsDark: true,
                    hoverTint: Color(nsColor: FloatingIndicatorController.captureOrange),
                    processingTint: processingIndex == 0 ? Color(nsColor: FloatingIndicatorController.captureOrange) : nil,
                    onCancel: activeMeeting ? onCancelMeeting : nil,
                    onCancelHoverChange: { cancelHover(0, $0) },
                    action: onMeeting
                ) { hover(0, $0) }
                LauncherCircle(
                    systemName: "text.bubble",
                    activeColor: activeDictation ? Color.white.opacity(0.92) : nil,
                    activeIconIsDark: true,
                    processingTint: processingIndex == 1 ? Color.white.opacity(0.9) : nil,
                    onCancel: activeDictation ? onCancelDictation : nil,
                    onCancelHoverChange: { cancelHover(1, $0) },
                    action: onDictation
                ) { hover(1, $0) }
                LauncherCircle(
                    systemName: "display",
                    activeColor: activeVideo ? Color(nsColor: FloatingIndicatorController.captureRed) : nil,
                    activeIconIsDark: true,
                    hoverTint: Color(nsColor: FloatingIndicatorController.captureRed),
                    processingTint: processingIndex == 2 ? Color(nsColor: FloatingIndicatorController.captureRed) : nil,
                    onCancel: activeVideo ? onCancelMeeting : nil,
                    onCancelHoverChange: { cancelHover(2, $0) },
                    action: onMeetingVideo
                ) { hover(2, $0) }
            }
            .padding(.horizontal, 6)
            .frame(height: 44)

            ZStack(alignment: .topLeading) {
                let activeIndex = cancelHoveredIndex ?? hoveredIndex
                if let index = activeIndex {
                    Text(captionText(for: index, isCancel: cancelHoveredIndex != nil))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        // Exactly the capsule's recipe — hudWindow blur under
                        // the neutral tint — so captions match the pill glass.
                        .background {
                            ZStack {
                                HUDGlassCapsule()
                                Capsule().fill(pillColor.opacity(0.45))
                            }
                        }
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { width in
                            captionWidth = width
                        }
                        .position(x: captionX(for: index), y: 11)
                }
            }
            .frame(width: rowWidth, height: 22)
        }
        // The appear fade is AppKit-driven (updateLauncher fadeIn:) so it can
        // start exactly when the capsule morph completes.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: revealToken) { _, _ in
            hoveredIndex = nil
            cancelHoveredIndex = nil
        }
    }

    /// Centered under the hovered circle, clamped so the capsule stays
    /// inside the window.
    private func captionX(for index: Int) -> CGFloat {
        let circleCenter: CGFloat = 6 + 16 + CGFloat(index) * 42
        let half = max(captionWidth / 2, 1)
        return min(max(circleCenter, half), rowWidth - half)
    }

    private func hover(_ index: Int, _ hovering: Bool) {
        if hovering {
            hoveredIndex = index
        } else if hoveredIndex == index {
            hoveredIndex = nil
        }
    }

    private func cancelHover(_ index: Int, _ hovering: Bool) {
        if hovering {
            cancelHoveredIndex = index
        } else if cancelHoveredIndex == index {
            cancelHoveredIndex = nil
        }
    }
}

private struct LauncherCircle: View {
    let systemName: String
    /// nil = idle circle (chrome on hover only); non-nil = this mode is LIVE:
    /// the circle stays filled with its mode color and the click stops it.
    var activeColor: Color? = nil
    /// Dictation's active fill is near-white — use a dark glyph on it.
    var activeIconIsDark = false
    /// Cancel ✕: a persistent outlined circle so it reads as its own control.
    var alwaysOutlined = false
    var iconWeight: Font.Weight = .medium
    /// Idle hover highlight in the mode's color (nil = neutral white).
    var hoverTint: Color? = nil
    /// Post-processing: a stage ring in the mode's color spins around the
    /// glyph (the launcher analogue of the strip's mini loader).
    var processingTint: Color? = nil
    /// Live mode: a small ✕ badge riding the circle's top-right outline
    /// cancels THIS capture; the big circle itself stays the stop toggle.
    var onCancel: (() -> Void)? = nil
    var onCancelHoverChange: ((Bool) -> Void)? = nil
    let action: () -> Void
    let onHoverChange: (Bool) -> Void
    @State private var isHovering = false
    @State private var badgeHovering = false

    private var isLive: Bool { activeColor != nil }

    init(
        systemName: String,
        activeColor: Color? = nil,
        activeIconIsDark: Bool = false,
        alwaysOutlined: Bool = false,
        iconWeight: Font.Weight = .medium,
        hoverTint: Color? = nil,
        processingTint: Color? = nil,
        onCancel: (() -> Void)? = nil,
        onCancelHoverChange: ((Bool) -> Void)? = nil,
        action: @escaping () -> Void,
        onHoverChange: @escaping (Bool) -> Void
    ) {
        self.systemName = systemName
        self.activeColor = activeColor
        self.activeIconIsDark = activeIconIsDark
        self.alwaysOutlined = alwaysOutlined
        self.iconWeight = iconWeight
        self.hoverTint = hoverTint
        self.processingTint = processingTint
        self.onCancel = onCancel
        self.onCancelHoverChange = onCancelHoverChange
        self.action = action
        self.onHoverChange = onHoverChange
    }

    private var iconColor: Color {
        if activeColor != nil {
            return activeIconIsDark ? Color.black.opacity(0.8) : .white
        }
        // Hovering an idle circle paints the glyph in the mode's full color.
        if isHovering, let hoverTint { return hoverTint }
        return .white.opacity(isHovering ? 1 : 0.85)
    }

    private var outlineOpacity: CGFloat {
        if isHovering { return 0.16 }
        if alwaysOutlined || activeColor != nil { return 0.16 }
        return 0
    }

    /// Active fill: the mode color with a soft lighter top — a "lit" disc on
    /// the accent's tonal level instead of a flat fill.
    @ViewBuilder private var circleFill: some View {
        if let activeColor {
            Circle().fill(
                LinearGradient(
                    colors: [lightened(activeColor, by: 0.28), activeColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else if isHovering, let hoverTint {
            // Mode-colored hover: a WHISPER of the mode color — the full-color
            // glyph must stand clear of it, not sink into it.
            Circle().fill(hoverTint.opacity(0.15))
        } else {
            Circle().fill(Color.white.opacity(isHovering ? 0.18 : 0))
        }
    }

    private var outlineStroke: Color {
        // Barely-there ring — the fill and glyph carry the color.
        if isHovering, let hoverTint { return hoverTint.opacity(0.2) }
        return .white.opacity(outlineOpacity)
    }

    private func lightened(_ color: Color, by amount: CGFloat) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return color }
        return Color(
            red: min(1, rgb.redComponent + (1 - rgb.redComponent) * amount),
            green: min(1, rgb.greenComponent + (1 - rgb.greenComponent) * amount),
            blue: min(1, rgb.blueComponent + (1 - rgb.blueComponent) * amount)
        )
    }

    private var glyph: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: isLive ? .semibold : iconWeight))
            .foregroundStyle(iconColor)
    }

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: 32, height: 32)
                .background {
                    if isLive {
                        // Recording feedback lives on the FILL: it breathes
                        // 100%↔60% on the shared wall clock (the dark glyph
                        // stays steady), synced across live circles.
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            let phase = (sin(t * (2 * Double.pi / 1.4)) + 1) / 2
                            circleFill.opacity(0.6 + 0.4 * phase)
                        }
                    } else {
                        circleFill
                    }
                }
                .overlay(Circle().strokeBorder(outlineStroke, lineWidth: 1))
                .overlay {
                    if let processingTint {
                        // Spinning stage ring around the glyph, shared clock.
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            Circle()
                                .trim(from: 0, to: 0.35)
                                .stroke(processingTint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                                .frame(width: 25, height: 25)
                                .rotationEffect(.degrees((t / 0.9 * 360).truncatingRemainder(dividingBy: 360)))
                        }
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover {
            isHovering = $0
            onHoverChange($0)
        }
        // Cancel badge: its center rides ON the circle's outline at the
        // top-right; revealed only while hovering the live circle.
        .overlay(alignment: .topTrailing) {
            if isLive, isHovering || badgeHovering, let onCancel {
                Button(action: onCancel) {
                    // Hand-drawn ✕ (two capsules) instead of the SF glyph —
                    // the font glyph sits optically off-center in a 14pt disc.
                    ZStack {
                        Capsule().fill(.white.opacity(0.95)).frame(width: 6.5, height: 1.3)
                        Capsule().fill(.white.opacity(0.95)).frame(width: 1.3, height: 6.5)
                    }
                    .rotationEffect(.degrees(45))
                    .frame(width: 14, height: 14)
                        // Soft neutral (the pill's graphite), not hard black —
                        // no extra contrast needed on the colored fill.
                        .background(Circle().fill(Color(red: 0.118, green: 0.118, blue: 0.118).opacity(0.8)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 2.3, y: -2.3)
                .transition(.opacity)
                .onHover {
                    badgeHovering = $0
                    onCancelHoverChange?($0)
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: badgeHovering)
        .animation(.easeOut(duration: 0.15), value: isLive)
    }
}

private extension NSColor {
    static func colorWith(hex: Int, alpha: CGFloat) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    static func colorWith(hexString: String, alpha: CGFloat = 1.0) -> NSColor {
        var h = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        h = h.hasPrefix("#") ? String(h.dropFirst()) : h
        guard h.count == 6, let value = UInt64(h, radix: 16) else {
            return .colorWith(hex: 0x1e1e1e, alpha: alpha)
        }
        return .colorWith(hex: Int(value), alpha: alpha)
    }
}
