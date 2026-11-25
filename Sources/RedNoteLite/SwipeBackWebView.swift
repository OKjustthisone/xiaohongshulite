import AppKit
import WebKit

/// WKWebView subclass providing native macOS right-swipe-to-go-back gestures:
/// 1. Two-finger trackpad swipe left-to-right (normalized for macOS Natural Scrolling setting)
/// 2. Left-edge mouse drag left-to-right (within 44pt of left border)
final class SwipeBackWebView: WKWebView {
    var shouldHandleSwipeBack: (() -> Bool)?
    var onSwipeBackProgress: ((CGFloat) -> Void)?
    var onSwipeBackTriggered: (() -> Void)?

    private let triggerThreshold: CGFloat = 85.0
    private var isTrackingTrackpadSwipe = false
    private var accumulatedSwipeX: CGFloat = 0
    private var swipeCooldownUntil: Date = .distantPast

    // Left-edge mouse drag tracking (for non-trackpad mouse users)
    private var isTrackingEdgeDrag = false
    private var edgeDragStartX: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        guard shouldHandleSwipeBack?() == true else {
            resetTrackpadSwipe()
            super.scrollWheel(with: event)
            return
        }

        // Ignore momentum tail events so one swipe never double-triggers
        if event.momentumPhase != [] {
            if isTrackingTrackpadSwipe {
                return
            }
            super.scrollWheel(with: event)
            return
        }

        if Date() < swipeCooldownUntil {
            super.scrollWheel(with: event)
            return
        }

        // Normalize physical left-to-right finger movement regardless of Natural Scrolling setting
        let rightwardDelta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        let verticalDelta = abs(event.scrollingDeltaY)

        switch event.phase {
        case .began:
            isTrackingTrackpadSwipe = false
            accumulatedSwipeX = 0
            super.scrollWheel(with: event)

        case .changed:
            if isTrackingTrackpadSwipe {
                accumulatedSwipeX = max(0, accumulatedSwipeX + rightwardDelta)
                let progress = min(1.0, accumulatedSwipeX / triggerThreshold)
                onSwipeBackProgress?(progress)
                return
            } else if rightwardDelta > 2.5 && rightwardDelta > verticalDelta * 1.35 {
                isTrackingTrackpadSwipe = true
                accumulatedSwipeX = rightwardDelta
                let progress = min(1.0, accumulatedSwipeX / triggerThreshold)
                onSwipeBackProgress?(progress)
                return
            }
            super.scrollWheel(with: event)

        case .ended, .cancelled:
            if isTrackingTrackpadSwipe {
                let shouldTrigger = accumulatedSwipeX >= triggerThreshold
                resetTrackpadSwipe()
                if shouldTrigger {
                    swipeCooldownUntil = Date().addingTimeInterval(0.45)
                    onSwipeBackTriggered?()
                }
                return
            }
            super.scrollWheel(with: event)

        default:
            super.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if shouldHandleSwipeBack?() == true && localPoint.x <= 44 {
            isTrackingEdgeDrag = true
            edgeDragStartX = localPoint.x
        } else {
            isTrackingEdgeDrag = false
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isTrackingEdgeDrag {
            let localPoint = convert(event.locationInWindow, from: nil)
            let deltaX = max(0, localPoint.x - edgeDragStartX)
            if deltaX > 10 {
                let progress = min(1.0, deltaX / triggerThreshold)
                onSwipeBackProgress?(progress)
                return
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isTrackingEdgeDrag {
            let localPoint = convert(event.locationInWindow, from: nil)
            let deltaX = max(0, localPoint.x - edgeDragStartX)
            isTrackingEdgeDrag = false
            onSwipeBackProgress?(0)
            if deltaX >= triggerThreshold {
                onSwipeBackTriggered?()
                return
            }
        }
        super.mouseUp(with: event)
    }

    private func resetTrackpadSwipe() {
        if isTrackingTrackpadSwipe || accumulatedSwipeX > 0 {
            isTrackingTrackpadSwipe = false
            accumulatedSwipeX = 0
            onSwipeBackProgress?(0)
        }
    }
}
