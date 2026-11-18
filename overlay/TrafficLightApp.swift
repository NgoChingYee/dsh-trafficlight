import AppKit
import SwiftUI

@main
struct TrafficLightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No window scene — the floating panel is created manually by the
        // AppDelegate so SwiftUI doesn't spawn a default window.
        Settings {
            EmptyView()
        }
    }
}

/// Drives the floating panel's position and auto-fit behaviour. Dragging is
/// handled by AppKit's native window-move session (GripDragView +
/// NSPanel.performDrag) — the system moves the window with compositor sync,
/// which is far smoother than a SwiftUI DragGesture round-tripping through
/// setFrameOrigin.
final class PanelMover: ObservableObject {
    weak var panel: NSPanel?
    /// Frosted-glass layer; its live-vibrancy recomposition is suspended while
    /// dragging so window movement stays smooth.
    weak var effectView: NSVisualEffectView?
    private let positionKey = "dsh_tl_origin"
    private let manualWidthKey = "dsh_tl_manual_width"
    private let minWidth: CGFloat = 150
    private let maxWidth: CGFloat = 560
    private let minimizedHeight: CGFloat = 40
    private var lastExpandedHeight: CGFloat = 134
    private var manualWidth: CGFloat?
    private(set) var isMinimal = false
    /// True while the user drags; auto-fit resizes are deferred until release
    /// so a poll landing mid-drag can't fight the movement.
    private(set) var isDragging = false
    private var lastSessions: [SessionStatus] = []

    init() {
        if let saved = UserDefaults.standard.object(forKey: manualWidthKey) as? CGFloat,
           saved >= minWidth, saved <= maxWidth {
            manualWidth = saved
        }
    }

    /// Called when a native drag session begins (before performDrag blocks).
    func beginNativeDrag() {
        isDragging = true
        effectView?.state = .inactive // drop live blur recomposition while moving
    }

    /// Called when the native drag session returns (user released the mouse).
    func nativeDragEnded() {
        isDragging = false
        effectView?.state = .active
        savePosition()
        // Re-apply any auto-fit that was deferred during the drag.
        fitToContent(lastSessions)
    }

    /// Collapse/expand the panel while keeping its top edge fixed on screen.
    func setMinimized(_ minimized: Bool) {
        guard let panel else { return }
        let newHeight = minimized ? minimizedHeight : lastExpandedHeight
        var frame = panel.frame
        let dy = frame.height - newHeight
        frame.origin.y += dy
        frame.size.height = newHeight
        panel.setFrame(frame, display: true)
    }

    /// Apply the user-configured window opacity (0.1..1) to the floating panel.
    func setPanelOpacity(_ value: Double) {
        panel?.alphaValue = CGFloat(min(1, max(0.1, value)))
    }

    /// Compact size for minimal (single-lamp) mode.
    private let minimalSize: (CGFloat, CGFloat) = (104, 58)

    /// Switch between minimal (single-lamp) and full layouts. In minimal mode
    /// the panel is pinned to a small fixed size; otherwise auto-fit resumes.
    func setMinimal(_ minimal: Bool) {
        guard let panel else { return }
        if isDragging { return }
        isMinimal = minimal
        if minimal {
            let (w, h) = minimalSize
            setFrameKeepTopRight(width: w, height: h)
        } else {
            // Restore auto-fit sizing based on the current subscription list.
            fitToContent(lastSessions)
        }
    }

    /// Set a user-chosen width from the right-edge resize handle. The manual
    /// value takes priority over content-based auto-fit until the key is reset.
    func setManualWidth(_ width: CGFloat) {
        guard let panel, !isMinimal else { return }
        let clamped = min(maxWidth, max(minWidth, width))
        manualWidth = clamped
        UserDefaults.standard.set(clamped, forKey: manualWidthKey)
        setFrameKeepTopRight(width: clamped, height: panel.frame.height)
    }

    /// Resize the panel to the given size anchoring its top-right corner.
    private func setFrameKeepTopRight(width: CGFloat, height: CGFloat) {
        guard let panel else { return }
        var frame = panel.frame
        let dx = frame.width - width
        frame.origin.x += dx // keep right edge fixed
        frame.size.width = width
        let dy = frame.height - height
        frame.origin.y += dy // keep top edge fixed
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    /// Auto-fit the capsule to the subscribed session list.
    ///
    /// Called whenever the row list changes (and once at appear). The width
    /// grows to fit the longest row title (right edge anchored, 300–560pt) and
    /// the height grows with the row count (top edge anchored, capped so a big
    /// subscription list scrolls instead of filling the screen). This also
    /// repairs the historical bug where the panel was frozen at the *initial*
    /// SwiftUI fitting size and a later, wider title got truncated to "…".
    func fitToContent(_ sessions: [SessionStatus]) {
        guard let panel else { return }
        lastSessions = sessions
        // Never resize a panel the user is currently dragging — a setFrame
        // landing mid-drag visibly stutters the movement.
        if isDragging { return }
        // Default auto-fit width, captured from the user-tuned overlay width.
        let baseWidth: CGFloat = 165
        let maxWidth: CGFloat = 560
        let chrome: CGFloat = 110 // row chrome around the title text
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        var longest: CGFloat = 0
        for s in sessions {
            let tw = (s.title as NSString).size(withAttributes: [.font: font]).width
            longest = max(longest, tw)
        }
        let neededWidth = min(max(baseWidth, chrome + longest.rounded(.up)), maxWidth)
        let targetWidth = isMinimal ? (panel.frame.width) : (manualWidth ?? neededWidth)

        let header: CGFloat = 36
        let rowH: CGFloat = 36
        let maxVisible: Int = 6
        let visible = min(sessions.count, maxVisible)
        let scrolled = max(0, sessions.count - maxVisible)
        let scrollArea: CGFloat = CGFloat(min(scrolled, 3)) * rowH
        let neededHeight: CGFloat = sessions.isEmpty
            ? 88
            : header + 1 + CGFloat(visible) * rowH + (scrolled > 0 ? 16 + scrollArea : 0) + 10

        var frame = panel.frame
        var changed = false
        let dw = targetWidth - frame.width
        if abs(dw) > 0.5 {
            frame.size.width = neededWidth
            frame.origin.x -= dw // keep the right edge anchored (capsule sits top-right)
            changed = true
        }
        let dh = neededHeight - frame.height
        if abs(dh) > 0.5 {
            frame.size.height = neededHeight
            frame.origin.y += dh // keep the top edge anchored
            changed = true
        }
        if changed {
            panel.setFrame(frame, display: true)
        }
        lastExpandedHeight = neededHeight
    }

    /// Quit the overlay app (main-actor: touches NSApp).
    @MainActor func quit() {
        NSApp.terminate(nil)
    }

    func restorePosition() {
        guard let panel else { return }
        guard let saved = UserDefaults.standard.array(forKey: positionKey) as? [CGFloat],
              saved.count == 2 else { return }
        panel.setFrameOrigin(NSPoint(x: saved[0], y: saved[1]))
    }

    private func savePosition() {
        guard let panel else { return }
        let p = panel.frame.origin
        UserDefaults.standard.set([p.x, p.y], forKey: positionKey)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var stateItem: NSMenuItem?
    private var client: StatusClient?
    private var mover: PanelMover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let client = StatusClient()
        let mover = PanelMover()
        self.client = client
        self.mover = mover

        let panel = NSPanel.trafficLightPanel(
            rootView: TrafficLightView()
                .environmentObject(client)
                .environmentObject(mover)
        )
        mover.panel = panel
        // Wire the frosted layer to the mover (blur suspended during drag).
        if let content = panel.contentView {
            for sub in content.subviews {
                if let fx = sub as? NSVisualEffectView, mover.effectView == nil {
                    mover.effectView = fx
                }
            }
        }
        mover.restorePosition()
        mover.setPanelOpacity(client.opacity) // apply persisted transparency on launch
        mover.setMinimal(client.minimalMode) // start in the persisted layout mode
        panel.orderFrontRegardless()
        self.panel = panel

        setupStatusItem()
        setupAlwaysOnTop()
    }

    /// Keep the panel pinned on top across every app-switch / space change.
    private func setupAlwaysOnTop() {
        let center = NotificationCenter.default
        let reFront = { [weak self] in self?.panel?.orderFrontRegardless() }
        center.addObserver(forName: NSApplication.didResignActiveNotification,
                           object: nil, queue: .main, using: { _ in reFront() })
        center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                           object: nil, queue: .main, using: { _ in reFront() })
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main, using: { _ in reFront() })
        // Periodic keep-alive: a fullscreen app, a Stage Manager space switch,
        // or another app raising its window can cover a level-6 panel without
        // firing any of the observers above. Re-front on a timer so the light
        // always comes back, and pull the panel back if it drifted off-screen
        // (e.g. an external display was disconnected and its saved origin no
        // longer intersects any screen).
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let panel = self.panel else { return }
                panel.orderFrontRegardless()
                self.ensureOnScreen(panel)
            }
        }
    }

    /// If the panel's frame no longer intersects any attached screen, move it
    /// back to the top-right of the main display. This is the usual cause of a
    /// "the light vanished but the menu-bar icon is still there" report after
    /// unplugging an external monitor or changing display arrangement.
    private func ensureOnScreen(_ panel: NSPanel) {
        let frame = panel.frame
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if onScreen { return }
        guard let main = NSScreen.main else { return }
        let margin: CGFloat = 16
        var f = frame
        f.origin.x = main.visibleFrame.maxX - f.width - margin
        f.origin.y = main.visibleFrame.maxY - f.height - margin
        panel.setFrame(f, display: true)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "🚦"
            button.toolTip = "DSH 任务状态红绿灯"
        }
        let menu = NSMenu()
        let stateItem = NSMenuItem(title: "状态：连接中…", action: nil, keyEquivalent: "")
        self.stateItem = stateItem
        menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出红绿灯", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item

        // Keep the menu item's status line roughly in sync with the light.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let client = self.client,
                  let stateItem = self.stateItem else { return }
            let label: String
            switch client.state {
            case .blocked: label = "状态：阻塞（红灯）"
            case .running: label = "状态：执行中（黄灯）"
            case .done: label = "状态：已完成（绿灯）"
            case .idle: label = "状态：空闲"
            case .offline: label = "状态：未连接 DSH"
            }
            DispatchQueue.main.async { stateItem.title = label }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
