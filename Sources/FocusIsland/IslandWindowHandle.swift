import AppKit
import SwiftUI

/// AppKit owns movement and continuous frame changes, so dragging is not coupled
/// to SwiftUI's quarter-second metric updates.
struct IslandWindowHandle: NSViewRepresentable {
    enum Kind { case move, resize }
    let kind: Kind
    func makeNSView(context: Context) -> HandleView { HandleView(kind: kind) }
    func updateNSView(_ view: HandleView, context: Context) {}

    final class HandleView: NSView {
        let kind: Kind
        private var initialFrame: NSRect?
        private var initialMouse = NSPoint.zero
        init(kind: Kind) {
            self.kind = kind
            super.init(frame: .zero)
            toolTip = kind == .move ? "Drag to move the island to any monitor" : "Drag to resize the island"
            setAccessibilityElement(true)
            setAccessibilityLabel(kind == .move ? "Move island" : "Resize island")
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: kind == .move ? .openHand : .crosshair) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.withAlphaComponent(0.4).setFill()
            if kind == .move {
                for x in [bounds.midX - 2, bounds.midX + 2] {
                    for y in [bounds.midY - 4, bounds.midY, bounds.midY + 4] {
                        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.6, height: 1.6)).fill()
                    }
                }
            } else {
                NSColor.white.withAlphaComponent(0.4).setStroke()
                for inset in [4.0, 8.0, 12.0] {
                    let line = NSBezierPath()
                    line.move(to: NSPoint(x: bounds.maxX - inset, y: 3))
                    line.line(to: NSPoint(x: bounds.maxX - 3, y: inset))
                    line.lineWidth = 1
                    line.stroke()
                }
            }
        }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if kind == .move { window.performDrag(with: event); return }
            initialFrame = window.frame
            initialMouse = NSEvent.mouseLocation
        }
        override func mouseDragged(with event: NSEvent) {
            guard kind == .resize, let window, let initialFrame else { return }
            let mouse = NSEvent.mouseLocation
            let width = min(window.maxSize.width, max(window.minSize.width, initialFrame.width + mouse.x - initialMouse.x))
            let height = min(window.maxSize.height, max(window.minSize.height, initialFrame.height - mouse.y + initialMouse.y))
            window.setFrame(NSRect(x: initialFrame.minX, y: initialFrame.maxY - height, width: width, height: height), display: true, animate: false)
        }
        override func mouseUp(with event: NSEvent) { initialFrame = nil }
    }
}
