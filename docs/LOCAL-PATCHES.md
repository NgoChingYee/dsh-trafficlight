# dsh-trafficlight 悬浮窗防消失补丁

插件：`@chivaskong96/dsh-trafficlight@0.3.0`（npm 发布包）
文件：`overlay/TrafficLightApp.swift`
修改位置：`AppDelegate.setupAlwaysOnTop()`

## 问题

已订阅会话在 Web 端正常，菜单栏 🚦 图标也在，但 macOS 悬浮面板偶尔不可见。
原因：面板 level=6，切到全屏应用 / Stage Manager 桌面切换 / 其他应用置顶时可能被盖住且不再恢复；
或外接显示器断开后，保存的窗口坐标不再落在任何屏幕上，面板被移到屏幕外。

## 修复内容

1. 在 `setupAlwaysOnTop()` 里新增一个每 2 秒触发的定时器，主线程调用
   `panel.orderFrontRegardless()`，让面板周期性重新置顶。
2. 新增 `ensureOnScreen(_:)`：若面板 frame 不与任何屏幕的 visibleFrame 相交，
   则把它移回主屏右上角（保留 16pt 边距）。

## 完整替换代码

把 `setupAlwaysOnTop()` 整段替换为：

```swift
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
```

## 重新应用步骤

插件升级或重装会覆盖该文件。重新应用：

1. 按上面替换 `overlay/TrafficLightApp.swift` 的 `setupAlwaysOnTop()`。
2. 重新编译：

```bash
DSH_TL_OVERLAY_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk \
  bash "$HOME/.dsh/profiles/desktop/node_modules/@chivaskong96/dsh-trafficlight/overlay/build.sh"
```

3. 重启悬浮窗：

```bash
bash "$HOME/.dsh/profiles/desktop/node_modules/@chivaskong96/dsh-trafficlight/scripts/trafficlight.sh" --restart
```

本机环境：Swift 6.2.4 + macOS 26.2 SDK（不要用 build.sh 默认的 15.4 SDK，会与编译器不匹配）。

---

## 补丁二：订阅按钮在暗色模式下看不清文字

文件：`lib/client.js`（运行时实际加载）和 `src/client/index.tsx`（源码），`SubscribeAction` 按钮的 `style`。

问题：未订阅时按钮文字色用了 `var(--dsw-alias-label-secondary, rgba(0,0,0,0.55))`，但该 CSS 变量在会话头部 slot 里未生效，回退到半透明黑色，暗色背景上几乎不可见。

修复：改为不依赖主题变量、明暗背景都清晰的颜色。把按钮 style 里这三行替换为：

```js
border: "1px solid " + (active ? "#5b8cff" : "rgba(128,128,128,0.45)"),
background: active ? "rgba(91,140,255,0.14)" : "transparent",
color: active ? "#5b8cff" : "currentColor",
```

（TSX 源码里用单引号，值相同。）`currentColor` 让未订阅文字继承会话头部的主题文字色，明暗模式都跟随主题；已订阅用亮蓝色。

生效：改 `lib/client.js` 后刷新 DSH 页面即可（client bundle 由前端模块加载器加载）。若之后执行 `build:client` 重建，需确保 `src/client/index.tsx` 已同步修改（本补丁已同步）。

---

## 补丁三：点击浮窗会话行跳转回对应对话

改动文件：
- `lib/host/bridge.js`（实际运行）+ `src/host/bridge.ts`（源码）
- `lib/client.js`（实际运行）+ `src/client/index.tsx`（源码）
- `overlay/StatusClient.swift`
- `overlay/TrafficLightView.swift`

链路：
1. Swift 会话行 `.onTapGesture { client.openSession(session.sessionId) }`。
2. `StatusClient.openSession(_:)` 向 `POST http://127.0.0.1:18765/focus` 提交 `{ sessionId }`；仅当桥返回 `202` 时 `NSWorkspace.shared.open(URL(string: "dsh://open")!)` 唤起桌面窗口。
3. Host bridge 的 `/focus` 只接受当前已订阅的会话 ID，压入一个有界队列（最多 32 条）。Web 路由 `GET /api/dsh-tl/focus` 一次性取出队列中的会话 ID。
4. Web client 每 800ms 轮询 `/api/dsh-tl/focus`，拿到会话 ID 后调用 `uiWorkspace.openSession(id)`；旧宿主回退到 `sessions.open(id)`；`apply()` dispose 时 `clearInterval`。

重要：DSH Desktop 只支持 `dsh://open` 唤起窗口，不支持携带 sessionId；精确会话跳转必须靠上面的本地桥 + Web client。`@chivaskong96/dsh-trafficlight@0.3.0` 的 npm 包缺少可重建的 devDependencies（`@deepseek-ai/dsh-client-runtime@^0.1.5-rc.1` 已从 npm 移除），所以本机直接补丁实际加载的 `lib/*.js` 并同步源码。

重新应用：
- Host 改动需停用/启用 bundle（或重启 DSH）后加载：对 Loader entryId `include:dsh-trafficlight` disable 再 enable。
- Web client 改动需刷新 DSH 页面。
- Swift overlay 重新编译并 restart：
  `DSH_TL_OVERLAY_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk bash overlay/build.sh`
  `bash scripts/trafficlight.sh --restart`

验证要点：
- `POST http://127.0.0.1:18765/focus` 对已订阅会话应返回 `202 {"ok":true}`，未订阅返回 `404`。
- `GET http://127.0.0.1:<webPort>/api/dsh-tl/focus` 应能取到刚提交的 `sessionId`，再次取为 `null`。

---

## 补丁四：右边缘拖拽调整悬浮窗宽度（普通模式）

改动文件：
- `overlay/TrafficLightApp.swift`：PanelMover 增加 `manualWidthKey = "dsh_tl_manual_width"`、`minWidth = 300`、`maxWidth = 560`、`manualWidth`、`isMinimal`；初始化读取已保存宽度；`setMinimal(_:)` 记录模式；新增 `setManualWidth(_:)`；`fitToContent(_:)` 普通模式使用 `manualWidth ?? neededWidth`，极简模式不改尺寸。
- `overlay/TrafficLightWindow.swift`：新增 `ResizeEdgeView: NSView` 与 `ResizeEdgeStrip: NSViewRepresentable`。鼠标按下记录起始宽度与鼠标 X；拖动时 `startWidth + (startMouseX - NSEvent.mouseLocation.x)` 调整宽度（保持右上锚点）；`resetCursorRects` 使用 `resizeLeftRight` 光标；绘制右侧半透明细条。
- `overlay/TrafficLightView.swift`：普通模式 fullBody 右边缘叠加 `ResizeEdgeStrip`，宽 10pt，顶部 padding 38pt（避开关闭/最小化按钮），鼠标提示“拖动调整宽度”；极简模式不显示把手。

用户行为：普通模式拖动悬浮窗右边缘即可改宽，范围 150–560pt；宽度保存到 UserDefaults，标题或订阅变化不再覆盖手动宽度。极简模式仍固定小尺寸。默认自动宽度为 165pt（用户最终调好的宽度约 164.74pt，取整为 165pt），最小宽度为 150pt，最大宽度为 560pt（原默认/最小均为 300pt）。若要恢复自动宽度：退出悬浮窗后清除该 App 的 `dsh_tl_manual_width` 默认值，或在新版本里提供重置入口。

本机已执行：`defaults delete TrafficLightOverlay dsh_tl_manual_width`，删除旧的 300pt 手动宽度，使 150pt 默认值立即生效。重新编译与重启命令同补丁三。

---

## 补丁五：悬浮窗标题使用真实对话标题并跨重启保留

改动文件：`lib/host/subscriptions.js`（实际运行）+ `src/host/subscriptions.ts`（源码）；`lib/host/status.js`（实际运行）+ `src/host/status.ts`（源码）。

问题：订阅文件只保存会话 ID；重启后非活动会话未进入 live session store，标题无法回填，且旧占位符 `sessionId.slice(0, 8)` 对所有会话都得到 `会话 session-`，无法区分。

修复：
- `SubscriptionStore` 增加 `titles: Map<string,string>`，兼容旧数组格式和新对象格式：
  ```json
  {
    "subscriptions": ["session-id"],
    "titles": { "session-id": "真实标题" }
  }
  ```
- `title(sessionId)` 优先返回缓存标题；没有时读取 DSH 会话标题投影缓存：
  `~/.dsh/storages/session_projcache/sessions/<sessionId>.json` 的 `record.rows.title.val`。
- `setTitle(sessionId,title)` 在 sessionTitle 服务、`session/title` 事件或首条用户消息解析出标题后保存。
- `StatusMachine.snapshot()` 对非活动订阅会话使用缓存标题并显示绿灯；活动会话仍优先使用 `ctx.sessionTitle.get(session)` 的结果。
- `placeholderTitle()` 改用会话 ID 后 8 位，避免全是 `会话 session-`。

验证结果：bridge `/state` 返回两个真实标题：`test插件` 与 `💻 Yayi-B端`；持久化文件同时包含两个订阅 ID 与标题，重启/重载后可恢复。

标题优先级修正：`SubscriptionStore.title()` 每次都先读 DSH 会话标题投影 `~/.dsh/storages/session_projcache/sessions/<id>.json` 的 `record.rows.title.val`，再回退到持久化标题；`StatusMachine.snapshot()` 只有 `t.titleAuthoritative` 为真时才使用活动会话的 `t.sessionTitle`。避免新用户消息把真实标题覆盖成消息原文。此前缓存被消息原文污染时，需要把订阅文件 `titles` 中的对应值纠正为投影标题，或等待下一次投影刷新。
