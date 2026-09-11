import AppKit
import SwiftUI

/// Leaves native horizontal gestures alone and redirects a vertical-only wheel.
enum HorizontalWheelEvent {
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
                      event.window === window, window.isVisible,
                      window.attachedSheet == nil, !self.isHiddenOrHasHiddenAncestor,
                      self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
                      let scrollView = self.enclosingScrollView,
                      let horizontal = HorizontalWheelEvent.redirect(event) else { return event }
                scrollView.scrollWheel(with: horizontal)
                return nil
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
