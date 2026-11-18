import SwiftUI

/// Logical light state (mirrors the dsh-trafficlight wire `TrafficState`).
enum TrafficState: String, Codable {
    case idle
    case running
    case blocked
    case done
    case offline
}

/// One subscribed session row as delivered by the bridge.
struct SessionStatus: Codable, Identifiable, Equatable {
    let sessionId: String
    let title: String
    let state: String
    let detail: String?

    var id: String { sessionId }

    var light: TrafficState { TrafficState(rawValue: state) ?? .idle }
}

/// Wire snapshot returned by the bridge at http://127.0.0.1:18765/state.
struct TrafficSnapshot: Codable {
    let state: String
    let title: String
    let sessions: [SessionStatus]
    let subscribed: [String]?
    let opacity: Double?
    let minimalMode: Bool?
    let breathCount: Int?
    let breathBeat: Double?
    let detail: String?
    let updatedAt: Int
}

struct TrafficLightView: View {
    @EnvironmentObject private var client: StatusClient
    @EnvironmentObject private var mover: PanelMover
    @State private var minimized = false
    /// Bumped when the latest big-lamp state changes; drives the minimal lamp's breathing.
    @State private var latestBreath = 0

    /// Rows shown without scrolling before the panel caps its height.
    private let maxVisibleRows = 6
    private let rowHeight: CGFloat = 36

    private var statusLabel: String {
        if client.sessions.isEmpty {
            return "未订阅会话"
        }
        switch client.state {
        case .blocked: return "有会话阻塞 · 等待处理"
        case .running: return "任务执行中"
        case .done: return "全部完成"
        case .idle: return "等待开始"
        case .offline: return "未连接 DSH"
        }
    }

    var body: some View {
        (client.minimalMode ? AnyView(minimalBody) : AnyView(fullBody))
            .onAppear {
                mover.setMinimal(client.minimalMode)
                mover.fitToContent(client.sessions)
            }
            .onChange(of: client.sessions) { _, newSessions in
                mover.fitToContent(newSessions)
            }
            .onChange(of: client.opacity) { _, newValue in
                mover.setPanelOpacity(newValue)
            }
            .onChange(of: client.minimalMode) { _, newValue in
                mover.setMinimal(newValue)
            }
            .onChange(of: minimized) { _, newValue in
                mover.setMinimized(newValue)
            }
    }

    /// Full layout: persistent title bar + subscribed-session rows.
    private var fullBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                NativeDragStrip(size: 22)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(client.sessions.isEmpty ? "DSH 红绿灯" : statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if minimized {
                    statusDot
                }
                minimizeButton
                closeButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 34)

            if !minimized {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 10)

                if client.sessions.isEmpty {
                    emptyState
                } else {
                    rows
                }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .trailing) {
            ResizeEdgeStrip(mover: mover)
                .frame(width: 10)
                .frame(maxHeight: .infinity)
                .padding(.top, 38)
                .help("拖动调整宽度")
        }
    }

    /// Minimal layout (极简模式): drag handle + a single large lamp + close.
    /// The lamp shows the most recently-updated state across all subscribed
    /// sessions, regardless of which session it came from.
    private var minimalBody: some View {
        HStack(spacing: 12) {
            NativeDragStrip(size: 22)
                .frame(width: 22, height: 22)
            BreathingLamp(
                color: client.latestState.lampColor,
                active: !client.sessions.isEmpty && client.latestState != .offline,
                size: 40,
                breath: latestBreath,
                breaths: client.breathCount,
                beatDuration: client.breathBeat
            )
            .onChange(of: client.latestState) { _, _ in
                latestBreath += 1
            }
            .help("最近状态：" + client.latestState.statusText)
            // Close collapses everything — no minimize button in minimal mode.
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minWidth: 0)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Second line of the header: session count + aggregate title.
    private var subtitle: String {
        let count = client.sessions.count
        if count == 0 { return "在 DSH 会话菜单中添加订阅" }
        let running = client.sessions.filter { $0.light == .running }.count
        let blocked = client.sessions.filter { $0.light == .blocked }.count
        var parts = ["\(count) 个订阅"]
        if running > 0 { parts.append("\(running) 执行中") }
        if blocked > 0 { parts.append("\(blocked) 阻塞") }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Lamp(color: .gray, active: false, size: 20)
            Text("暂无订阅会话\n在 DSH 会话右侧「…」菜单选择「添加订阅」")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(height: 52)
    }

    private var rows: some View {
        let all = client.sessions
        let visible = Array(all.prefix(maxVisibleRows))
        let showMore = all.count > maxVisibleRows
        return VStack(spacing: 0) {
            ForEach(visible) { session in
                SessionRow(
                    session: session,
                    recent: client.isStateRecent(session.sessionId),
                    breaths: client.breathCount,
                    beatDuration: client.breathBeat,
                    onOpen: { client.openSession(session.sessionId) }
                ) {
                    client.unsubscribe(session.sessionId)
                }
                if session.id != visible.last?.id {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                        .padding(.leading, 44)
                }
            }
            if showMore {
                Text("还有 \(all.count - maxVisibleRows) 个订阅 · 请展开菜单管理")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.vertical, 5)
                ScrollView {
                    ForEach(all.dropFirst(maxVisibleRows)) { session in
                        SessionRow(
                            session: session,
                            recent: client.isStateRecent(session.sessionId),
                            breaths: client.breathCount,
                            beatDuration: client.breathBeat,
                            onOpen: { client.openSession(session.sessionId) }
                        ) {
                            client.unsubscribe(session.sessionId)
                        }
                    }
                }
                .frame(height: CGFloat(all.count - maxVisibleRows) * rowHeight)
            }
        }
    }
}

/// One subscribed session: lamp + title + state line (+ transient detail when
/// blocked) + unsubscribe. The lamp breathes when `recent` turns true — i.e.
/// right after this session's state changed — then settles back to resting.
private struct SessionRow: View {
    let session: SessionStatus
    let recent: Bool
    /// Breathing config from settings (forwarded to the lamp).
    let breaths: Int
    let beatDuration: TimeInterval
    let onOpen: () -> Void
    let onUnsubscribe: () -> Void

    /// Bumped whenever a change arrives; drives the breathing lamp.
    @State private var breath = 0
    private let lampSize: CGFloat = 21

    var body: some View {
        HStack(spacing: 9) {
            BreathingLamp(
                color: session.light.lampColor,
                active: session.light != .idle && session.light != .offline,
                size: lampSize,
                breath: breath,
                breaths: breaths,
                beatDuration: beatDuration
            )
            .onChange(of: recent) { _, newValue in
                if newValue { breath += 1 }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(session.statusText)
                    .font(.system(size: 10))
                    .foregroundColor(session.light.lampColor.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUnsubscribe) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("取消订阅此会话")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .help("打开此会话")
    }
}

/// Per-row status line: always visible, colored by the light state.
private extension SessionStatus {
    var statusText: String {
        switch light {
        case .blocked:
            return detail?.isEmpty == false ? detail! : "阻塞 · 等待处理"
        case .running:
            return "执行中"
        case .done:
            return "已完成 · 待指示"
        case .idle:
            return "等待开始"
        case .offline:
            return "未连接"
        }
    }
}

private extension TrafficState {
    var lampColor: Color {
        switch self {
        case .blocked: return Color.red
        case .running: return Color.yellow
        case .done: return Color.green
        case .idle: return Color.gray
        case .offline: return Color.gray
        }
    }

    /// Short label for a bare light state (used by the minimal-mode tooltip).
    var statusText: String {
        switch self {
        case .blocked: return "阻塞 · 等待处理"
        case .running: return "执行中"
        case .done: return "已完成"
        case .idle: return "等待开始"
        case .offline: return "未连接"
        }
    }
}

extension TrafficLightView {
    /// Top-right close affordance. Same interactive strip as the grip
    /// (see TrafficLightHostingView.interactiveZones).
    private var closeButton: some View {
        Button {
            mover.quit()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .help("关闭红绿灯")
    }

    /// Minimize / expand toggle: hides (or restores) the row list,
    /// leaving only the persistent title bar.
    private var minimizeButton: some View {
        Button {
            let newValue = !minimized
            withAnimation(.easeInOut(duration: 0.15)) { minimized = newValue }
        } label: {
            Image(systemName: minimized ? "plus" : "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .help(minimized ? "展开红绿灯" : "隐藏红绿灯")
    }

    /// Tiny state dot — only shown in the title bar while minimized.
    private var statusDot: some View {
        Circle()
            .fill(labelColor)
            .frame(width: 8, height: 8)
            .shadow(color: labelColor, radius: 4, x: 0, y: 0)
    }

    private var labelColor: Color {
        switch client.state {
        case .blocked: return Color.red
        case .running: return Color.yellow
        case .done: return Color.green
        case .idle: return Color.white.opacity(0.6)
        case .offline: return Color.gray
        }
    }
}

struct Lamp: View {
    let color: Color
    let active: Bool
    var size: CGFloat = 16

    var body: some View {
        Circle()
            .fill(active ? color : color.opacity(0.16))
            .frame(width: size, height: size)
            .shadow(color: active ? color : .clear, radius: active ? size * 0.45 : 0, x: 0, y: 0)
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
    }
}

/// A lamp that "breathes" when its underlying state changes: instead of the old
/// one-shot size jump, it scales up and back down a few beats, then settles at
/// its resting size. `breath` is a monotonic counter that a parent increments
/// on each state change — every increment starts one breathing cycle.
struct BreathingLamp: View {
    let color: Color
    let active: Bool
    let size: CGFloat
    /// Bump to retrigger the cycle (row / minimal lamp counts state changes).
    let breath: Int
    /// How many up-and-down beats per state change.
    var breaths: Int = 3
    /// One beat = scale up over `beat`, hold, then scale back over `beat`.
    var beatDuration: TimeInterval = 0.35

    @State private var scale: CGFloat = 1
    @State private var cycleTask: Task<Void, Never>?

    var body: some View {
        // Use scaleEffect for visual scaling — changing `size` directly would
        // trigger a layout pass that deforms the panel's rounded corners.
        Lamp(color: color, active: active, size: size)
            .scaleEffect(scale)
            .onChange(of: breath) { _, newValue in
                guard newValue > 0 else { return }
                cycleTask?.cancel()
                let fresh = Task { @MainActor in
                    await runCycle()
                }
                cycleTask = fresh
            }
            .onDisappear { cycleTask?.cancel() }
    }

    /// Scale up then settle to rest, `breaths` times, using a natural ease.
    @MainActor
    private func runCycle() async {
        for _ in 0..<breaths {
            withAnimation(.easeInOut(duration: beatDuration)) { scale = 1.35 }
            try? await Task.sleep(for: .seconds(beatDuration))
            withAnimation(.easeInOut(duration: beatDuration)) { scale = 1 }
            try? await Task.sleep(for: .seconds(beatDuration))
        }
        scale = 1
    }
}

/// SwiftUI-embedded native drag strip for the grip icon. AppKit mouse events
/// (mouseDown / mouseDragged / mouseUp) move the window directly — no SwiftUI
/// gesture round-trip — and because it is placed by SwiftUI layout it always
/// exists. The strip draws the three-line handle glyph itself and only occupies
/// the icon's footprint, so only the icon drags the window.
struct NativeDragStrip: NSViewRepresentable {
    @EnvironmentObject private var mover: PanelMover
    var size: CGFloat = 30

    func makeNSView(context: Context) -> GripDragView {
        let view = GripDragView()
        view.mover = mover
        return view
    }

    func updateNSView(_ nsView: GripDragView, context: Context) {
        nsView.mover = mover
    }
}