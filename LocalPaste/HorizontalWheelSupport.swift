import AppKit
import SwiftUI

/// Leaves native horizontal gestures alone and redirects a vertical-only wheel.
enum HorizontalWheelEvent {
    // Mos tags the interpolated frames it posts to the target process (ScrollUtils.swift).
    private static let mosSmoothEventMarker: Int64 = 0x4D4F53534D4F4F54

    static func isMosSmoothFrame(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == mosSmoothEventMarker
    }

    static func redirect(_ event: NSEvent) -> NSEvent? {
        guard event.type == .scrollWheel,
              event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
              let copy = event.cgEvent?.copy() else { return nil }

        // Keep AppKit's line/pixel resolution, direction, acceleration and phases.
        // Copy raw fixed-point bits as well as line and point deltas.
        let axes: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2)
        ]
        let deltas = axes.map { copy.getIntegerValueField($0.0) }
        // Core Graphics may normalize related fields when a delta is changed.
        // Save every source value before clearing the vertical axis.
        for (vertical, _) in axes { copy.setIntegerValueField(vertical, value: 0) }
        for ((_, horizontal), delta) in zip(axes, deltas) {
            copy.setIntegerValueField(horizontal, value: delta)
        }
        return NSEvent(cgEvent: copy)
    }
}

/// Placed inside the history scroll view so wheel handling stays in its viewport.
struct HorizontalWheelSupport: NSViewRepresentable {
    func makeNSView(context: Context) -> WheelRegionView { WheelRegionView() }
    func updateNSView(_ nsView: WheelRegionView, context: Context) { }
    static func dismantleNSView(_ nsView: WheelRegionView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class WheelRegionView: NSView {
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window,
                      window.isVisible, window.attachedSheet == nil,
                      !self.isHiddenOrHasHiddenAncestor,
                      let scrollView = self.enclosingScrollView else { return event }

                // Process-targeted events from scroll utilities can arrive with screen coordinates
                // but no window. Resolve them only when our panel is the hit window.
                let windowless = event.windowNumber == 0
                guard windowless || event.window === window else { return event }
                let location = event.locationInWindow
                let panelPoint = windowless ? window.convertPoint(fromScreen: location) : location
                guard self.visibleRect.contains(self.convert(panelPoint, from: nil)),
                      !windowless || NSWindow.windowNumber(at: location, belowWindowWithWindowNumber: 0) == window.windowNumber else {
                    return event
                }

                if windowless || HorizontalWheelEvent.isMosSmoothFrame(event) {
                    self.scrollByWheelDelta(event, in: scrollView)
                } else {
                    guard let horizontal = HorizontalWheelEvent.redirect(event) else { return event }
                    scrollView.scrollWheel(with: horizontal)
                }
                return nil
            }
        }

        private func scrollByWheelDelta(_ event: NSEvent, in scrollView: NSScrollView) {
            let delta = event.scrollingDeltaX == 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            guard delta != 0 else { return }

            // Apply each frame's distance without depending on AppKit's gesture tracking.
            let distance = event.hasPreciseScrollingDeltas ? delta : delta * scrollView.horizontalLineScroll
            let clipView = scrollView.contentView
            var proposedBounds = clipView.bounds
            proposedBounds.origin.x -= distance
            let origin = clipView.constrainBoundsRect(proposedBounds).origin
            if origin != clipView.bounds.origin {
                clipView.scroll(to: origin)
                scrollView.reflectScrolledClipView(clipView)
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
