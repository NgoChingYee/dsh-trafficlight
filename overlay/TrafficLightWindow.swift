import AppKit
import SwiftUI

/// Native drag strip covering just the grip icon, embedded via SwiftUI
/// (NSViewRepresentable → NativeDragStrip). On mouse-down it temporarily adds
/// .titled + movableByWindowBackground so the borderless+nonactivating panel
/// can enter a real NSWindow.performDrag session — the system moves the window
/// with compositor sync, which is far smoother than manual setFrameOrigin.
/// `acceptsFirstMouse` lets the non-activating panel pick up the click that
/// starts the drag.
final class GripDragView: NSView {
    weak var mover: PanelMover?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        mover?.beginNativeDrag()
        // performDrag(with:) only works on a window that has a title bar / is
        // activatable (borderless+nonactivating can't enter a window drag
        // session). Temporarily add .titled + .movableByWindowBackground, run
        // the system drag session (compositor-synced, smooth), then undo.
        let originalMask = window.styleMask
        window.styleMask.insert(.titled)
        window.isMovableByWindowBackground = true
        window.performDrag(with: event) // blocking; returns on release
        window.isMovableByWindowBackground = false
        window.styleMask = originalMask
        mover?.nativeDragEnded()
    }

    /// Draw the three-line drag-handle glyph so the strip looks like a handle.
    /// Scales with the view size so it always fits a small 22pt icon.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let fill = NSColor.white.withAlphaComponent(0.6)
        fill.setFill()
        let w = bounds.width
        let h = bounds.height
        let cx = w / 2
        let cy = h / 2
        let lineW = min(13, w * 0.6)
        let lineH = max(1.1, h * 0.07)
        let gap = lineW * 0.24
        for i in -1...1 {
            let rect = NSRect(x: cx - lineW / 2, y: cy + CGFloat(i) * gap - lineH / 2, width: lineW, height: lineH)
            NSBezierPath(roundedRect: rect, xRadius: lineH / 2, yRadius: lineH / 2).fill()
        }
    }
}

/// Right-edge resize strip. Dragging left widens the panel; dragging right
/// narrows it. Uses absolute mouse location so a setFrame during the drag
/// cannot feed back into the delta calculation.
final class ResizeEdgeView: NSView {
    weak var mover: PanelMover?
    private var startWidth: CGFloat = 0
    private var startMouseX: CGFloat = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startWidth = window.frame.width
        startMouseX = NSEvent.mouseLocation.x
        mover?.effectView?.state = .inactive
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = startMouseX - NSEvent.mouseLocation.x
        mover?.setManualWidth(startWidth + delta)
    }

    override func mouseUp(with event: NSEvent) {
        mover?.effectView?.state = .active
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let x = bounds.maxX - 2
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 8, width: 2, height: bounds.height - 16),
                     xRadius: 1, yRadius: 1).fill()
    }
}

/// SwiftUI bridge for the right-edge resize strip.
struct ResizeEdgeStrip: NSViewRepresentable {
    let mover: PanelMover

    func makeNSView(context: Context) -> ResizeEdgeView {
        let view = ResizeEdgeView()
        view.mover = mover
        return view
    }

    func updateNSView(_ nsView: ResizeEdgeView, context: Context) {
        nsView.mover = mover
    }
}

/// Custom hosting view that hosts the SwiftUI content plus the frosted-glass
/// backdrop. Only the frosted layer is handled here; the drag strip is placed
/// by SwiftUI so it is always present.
final class TrafficLightHostingView<Content: View>: NSHostingView<Content> {
    /// Frosted-glass layer behind the SwiftUI content (real macOS vibrancy).
    private var effectView: NSVisualEffectView?
    /// Cached rounded mask — rebuilt only when the panel size actually changes.
    private var effectMask: CAShapeLayer?
    private var effectMaskSize: NSSize = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if effectView == nil {
            let fx = NSVisualEffectView()
            fx.material = .hudWindow // dark translucent frosted glass
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.autoresizingMask = [.width, .height]
            fx.frame = bounds
            addSubview(fx, positioned: .below, relativeTo: nil)
            effectView = fx
            updateEffectMask()
        }
    }

    override func layout() {
        super.layout()
        effectView?.frame = bounds
        updateEffectMask()
    }

    /// Keep the frosted layer's rounded corners in sync with the panel size.
    /// The mask layer is cached: recreating a CAShapeLayer on every layout
    /// during a drag is a visible source of stutter.
    private func updateEffectMask() {
        guard let layer = effectView?.layer else { return }
        if abs(effectMaskSize.width - bounds.width) < 0.5,
           abs(effectMaskSize.height - bounds.height) < 0.5 {
            return
        }
        effectMaskSize = bounds.size
        if effectMask == nil { effectMask = CAShapeLayer() }
        effectMask?.path = CGPath(roundedRect: bounds, cornerWidth: 16, cornerHeight: 16, transform: nil)
        layer.mask = effectMask
    }
}

final class TrafficLightHostingController: NSHostingController<AnyView> {
    convenience init(rootView: some View) {
        self.init(rootView: AnyView(rootView))
    }

    override func loadView() {
        let hostingView = TrafficLightHostingView<AnyView>(rootView: rootView)
        self.view = hostingView
    }
}

extension NSPanel {
    /// Builds the system-wide floating traffic-light panel.
    ///
    /// Desktop-pet style overlay:
    /// - Borderless + transparent + `nonactivatingPanel` so it never steals focus.
    /// - Level is raised *above* normal/floating app windows (raw 6) but still
    ///   *below* macOS modal/alert windows (≈8), so an approval dialog is never
    ///   hidden behind the light. `hidesOnDeactivate = false` + re-fronting
    ///   observers (see AppDelegate) keep it pinned across every app switch.
    /// - Click-through everywhere except the grip icon (drag) and the close /
    ///   minimize buttons.
    static func trafficLightPanel<Content: View>(rootView: Content) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 134),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Above app windows (floating=3) yet below modal alerts (~8).
        panel.level = NSWindow.Level(rawValue: 6)
        panel.ignoresMouseEvents = false // events needed for dragging the grip
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.contentViewController = TrafficLightHostingController(rootView: rootView)

        // Pin the panel size. Assigning a contentViewController makes AppKit
        // resize the window to the hosting view's *initial* fitting size
        // (title "DSH" / empty detail → quite narrow). Later the real title
        // arrives but the window width never follows, so the title bar would
        // be squeezed and the title truncated to "…". Pin explicit min/max so
        // nothing collapses the capsule; PanelMover.fitToContent then widens
        // the panel to fit the actual rows when they change.
        panel.setContentSize(NSSize(width: 300, height: 134))
        panel.minSize = NSSize(width: 300, height: 36)
        panel.maxSize = NSSize(width: 560, height: 400)

        if let screen = NSScreen.main {
            let margin: CGFloat = 16
            let x = screen.visibleFrame.maxX - panel.frame.width - margin
            let y = screen.visibleFrame.maxY - panel.frame.height - margin
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        return panel
    }
}
