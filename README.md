# dsh-trafficlight — DSH 任务状态红绿灯（订阅制多会话）

> **Fork notice:** This repository is a fork adapted for DSH Desktop `0.2.2-rc.3`.
> See [FORK-NOTES.md](./FORK-NOTES.md) for the packaged fixes and [LOCAL-PATCHES.md](./docs/LOCAL-PATCHES.md) for the full patch log.

一个 **dsh 宿主（Host）插件** + **浏览器半区（Web GUI 订阅按钮）** + **macOS 全局悬浮窗**，
把**你订阅的每个会话**的任务状态用红/黄/绿三色灯在屏幕右上角的悬浮窗里**逐行实时展示**。

![红绿灯三种状态](./images/demo.png)

| 灯 | 会话状态 | 触发条件 |
|---|---|---|
| 🔴 红灯 | `blocked` 阻塞 | 该会话等待批准（`approval/asked`→`decided`）或向你提问（`ask_user_question`） |
| 🟡 黄灯 | `running` 执行中 | 该会话回合进行中（`turn/start` … `turn/end`）且未阻塞 |
| 🟢 绿灯 | `done` 已完成 | 该会话回合已结束 |
| ⚪ 暗灯 | `idle` / `offline` | 已订阅但尚未开始 / 未连接 dsh |

**订阅制**：悬浮窗只展示你在 Web GUI 中**主动订阅**的会话（而不是全部会话）。
订阅入口是会话头部操作行的「🚦 订阅」按钮（`conversation.session.header.actions` 官方附加槽）。
订阅列表持久化在 `~/.dsh/storages/dsh-trafficlight.json`，重启 dsh web 后保留。

悬浮窗布局：
- **顶部常驻标题栏**：订阅数 + 执行中/阻塞计数摘要；左侧 ⠿ 拖动手柄；右侧「− / +」最小化与「×」关闭。
- **标题栏下方**：每个订阅会话一行——小号红/黄/绿灯 + 会话标题（常驻首条消息）+ 阻塞时显示瞬态
  `detail`（如「DSH 需要批准: xxx」）；每行右侧「⊖」可**单独取消订阅**，本行立即从悬浮窗消失。
- 面板宽度/高度**自适应内容**（宽度 300–560pt 随最长标题撑开，高度随行数增长并封顶，
  超出部分滚动），右侧/顶部锚定，不遮下方操作。
- 取消订阅后该会话不再出现在列表里；列表清空时显示空态提示。
- **拖拽**：按住标题栏左侧 ⠿ 手柄即可拖动悬浮窗（系统级 `performDrag`，顺滑跟手）；
  位置记入 `UserDefaults`，下次启动自动恢复。

> `title`（常驻）与 `detail`（瞬态）由两个独立字段承载：插件把会话标题锁进 `title`，
> 阻塞文案放进 `detail`，互不覆盖。
> **标题即会话头部标题**：插件跟随 `session/title` 事件（dsh-session-title 服务追加的
> 规范标题事件，用户重命名或自动标题都会写该事件），取最新一条——与界面头部显示一致；
> 尚无该事件时退化为会话首条用户消息。

---

## 版本支持（Compatibility）

| 插件版本 | 支持的 dsh | 说明 |
|---|---|---|
| **v0.3.x**（当前） | **dsh 0.1.x web profile**（在 `dsh 0.1.5-rc.1` 上验证；bundle `@deepseek-ai/dsh-base` / `@deepseek-ai/dsh-web-app` 0.1.5-rc.1，`@deepseek-ai/cordis` 4.0.x） | 客户端 bundle 以 **scoped 包名注册**（`@chivaskong96/dsh-trafficlight`），注入 `dsh-client-locale` + `dsh-client-ui-conversation`（slots 注册表宿主），适配 `client-modules` 按包名校验/查找工厂的加载语义 |
| v0.2.x 及更早 | 旧版 dsh 0.1.0-rc.* 加载器 | 客户端以未 scoped 的短 id 注册；在 0.1.5-rc.1 上客户端半区不会加载（头部无「🚦 订阅」按钮） |

---

## 快速开始（Quick Start）

```bash
# 1. 安装（自动激活，无需手动编辑任何文件）
dsh plugin --profile web add @chivaskong96/dsh-trafficlight

# 2. 重启
dsh web
```

> 其它 profile 把 `web` 换成对应名字，或设置 `DSH_PROFILE=tui`。

重启后：
- 打开任意会话，在**会话头部操作行**点「🚦 订阅」→ 该会话进入红绿灯列表；
- 首次订阅时会**自动拉起** macOS 悬浮窗（未运行时）；窗口右上角逐行显示每个订阅
  会话的红/黄/绿灯 + 状态，行内「⊖」可单独取消订阅；
- 无需手动启动悬浮窗（[第 3 节](#3-运行-macos-悬浮窗一般不需要手动)）。

---

## 1. 安装 dsh 插件（dsh profile / npm）

```bash
dsh plugin --profile web add @chivaskong96/dsh-trafficlight
dsh web
```

安装时 DSH 会自动检测包内的 `dsh.bundle.patch` 声明，将插件加入 profile 的
bundles 列表，重启后自动加载 `cordis.patch.yml` 中的 insert 条目。

### 从源码安装（开发者）

```bash
cd ~/.dsh/profiles/web
pnpm add --lockfile=false /path/to/dsh-trafficlight
dsh web
```

改源码后需重新构建：

```bash
npm run build
```

## 2. 使用

1. 打开一个会话，在**会话头部操作行**点「🚦 订阅」→ 该会话进入红绿灯列表。
2. 再点一次（「已订阅」状态）即取消订阅。
3. 屏幕右上角悬浮窗逐行显示每个订阅会话的红/黄/绿灯；行内「⊖」可随时移除单条。
4. 菜单栏 🚦 可看聚合状态 / 退出。

## 3. 运行 macOS 悬浮窗（一般不需要手动）

插件会在**首次点击「🚦 订阅」时自动拉起悬浮窗**（若未运行），dsh web 重启且存在
存量订阅时也会自动恢复。因此日常使用无需手动启动。

> ⚠️ **悬浮窗是「两进程」架构**：dsh 插件 / `mock-bridge.mjs` 只是数据源（提供 JSON），
> 真正画红绿灯的是独立的 Swift app。自动启动由宿主进程 spawn（`overlay-launcher.ts`，
> 二进制路径可用 `DSH_TL_OVERLAY_BIN` 覆盖；完整 `pnpm add` 安装不含 overlay/ 时跳过）。
> 手动启动（调试用）：

```bash
# 终端 A：先起数据源（二选一）
node mock-bridge.mjs                       # 演示用：3 个假会话循环红/黄/绿 + 支持订阅增删
# 或：装好 dsh 插件并启动 dsh web（插件自带桥）

# 终端 B：一句话启动悬浮窗（自动重编 + 后台运行；重复执行会提示已在运行，
# 加 --restart 强制重启）
bash scripts/trafficlight.sh
# 日志：~/.dsh/trafficlight-overlay.log（可用 TL_LOG=/path 覆盖）
```

未连接 dsh（桥未起）时显示「未连接 DSH」；无订阅时显示空态提示。

### 关闭悬浮窗
1. 胶囊右上角「×」按钮。
2. 菜单栏 🚦 →「退出红绿灯」。
3. `pkill -f TrafficLightOverlay`；重新打开再跑一次可执行文件即可。

> **构建提示**：`swift build` 默认给子进程套 `sandbox-exec`，沙箱环境下会报
> `Operation not permitted`；`build.sh` 已加 `--disable-sandbox` 规避。
> SwiftPM 产出裸可执行文件（非 `.app`），代码里 `setActivationPolicy(.accessory)`
> 使其表现为无 Dock 图标的菜单栏 agent；要纯正 `.app` 请用 Xcode 打开（`Info.plist` 已含 `LSUIElement`）。

## 4. 不跑 dsh 也能预览（Mock 桥）

```bash
cd <dsh-trafficlight 目录>
node mock-bridge.mjs          # 3 个演示会话循环 running/blocked/done，支持订阅增删
# 另开终端启动 overlay，即可看到多行红绿灯切换 + 行内取消订阅
```

---

## 架构

```
┌─────────────────────────┐         session/event 事件流
│   dsh web (host 进程)    │  ◄───────────────────────────────  (cordis 火流)
│  ┌───────────────────┐  │
│  │ dsh-trafficlight  │  │  维护 每会话 状态 (idle/running/blocked/done)
│  │  StatusMachine    │  │  + 订阅集合 SubscriptionStore(持久化 JSON)
│  └─────────┬─────────┘  │
│            │ snapshot   │
│  ┌─────────┴─────────┐  │  loopback HTTP (固定端口 18765) + SSE
│  │  bridge (node:http)│  │  GET /state · GET /stream
│  └─────┬───────┬──────┘  │  GET|POST|DELETE /subscriptions
└────────┼───────┼─────────┘
         │       │
   ┌─────┴──┐    │  http://127.0.0.1:18765/state  (每 0.7s 轮询)
   │ Web GUI │    └───────────────────────────────┐
   │ 🚦订阅键 │  (POST/DELETE /api/dsh-tl/subscriptions)  │
   └─────────┘                                    ▼
                                     ┌────────────────────────────┐
                                     │  TrafficLightOverlay (Swift) │
                                     │  多行列表：每会话一行红绿灯    │
                                     │  行内 ⊖ = 取消订阅            │
                                     └────────────────────────────┘
```

设计要点：
- **原生 overlay**：`NSPanel` 无边框、透明、鼠标穿透（仅拖动手柄/关闭/取消订阅按钮可点）、
  置顶（level 6，低于 macOS 告警弹窗）、跨空间 / 全屏保持置顶、不抢焦点。
- **本地桥接**：插件用 `node:http` 在 `127.0.0.1:18765` 起仅本机可达的服务；同时挂
  dsh webServer 前缀 `/api/dsh-tl/*` 供浏览器半区使用（loopback 校验）。
- **浏览器半区**：`src/client/index.tsx` 注册 `conversation.session.header.actions` 槽
  条目（会话头部的「🚦 订阅」按钮），经 `window.__ModuleLoader__` 由宿主扫描装载。
  会话列表侧栏 "…" 菜单（重命名/fork/归档）在 `dsh-client-ui-workspace` 中为硬编码且无
  扩展点，故订阅入口放在会话头部操作行（同为会话绑定位置、官方支持的附加槽）。
- **零额外运行时依赖**：桥接只用 Node 内置 `http`；overlay 只用 SwiftUI/AppKit。

---

## 目录

```
dsh-trafficlight/
├── package.json / tsconfig*.json        # 宿主插件 + 浏览器半区（dsh.client 声明）
├── .gitignore / .npmignore              # git 与 npm 发布规则
├── LICENSE                              # MIT 开源证书
├── src/
│   ├── index.ts                         # apply(ctx)：挂载火流 + 桥 + 页内路由 + 提示段
│   ├── core/types.ts                    # 前后共享 wire 类型（多会话快照）
│   ├── host/
│   │   ├── status.ts                    # 状态机：session/event → 每会话 4 态 + 聚合 + 标题回填
│   │   ├── subscriptions.ts             # 订阅集合 + 持久化（~/.dsh/storages）
│   │   ├── overlay-launcher.ts          # 订阅时自动拉起 macOS 悬浮窗
│   │   └── bridge.ts                    # 独立 loopback 桥 (18765) + /api/dsh-tl/* 路由
│   └── client/index.tsx                 # 浏览器半区：会话头部「🚦 订阅」槽按钮
├── mock-bridge.mjs                      # 无 dsh 时的演示桥（多会话 + 订阅增删）
├── scripts/
│   └── trafficlight.sh                  # 一键启动/重启悬浮窗
└── overlay/                             # 原生 macOS 悬浮窗（Swift，多行列表）
    ├── TrafficLightApp.swift            # @main App + 菜单栏 🚦 + 面板拖动/自适应
    ├── TrafficLightWindow.swift         # 透明/置顶/毛玻璃 NSPanel + 原生拖拽条
    ├── TrafficLightView.swift           # 多行列表：每会话一行灯 + 标题 + 状态 + 取消订阅
    ├── StatusClient.swift               # 轮询桥 → @Published 会话列表 + 最近变更高亮
    ├── Package.swift / build.sh / Info.plist
```

## 状态映射细节（实现逻辑）

- **会话标题（跟随头部）**：跟随 `session/title` 事件（含用户重命名与自动标题，取最新一条），
  与界面会话头部一致；尚无该事件时退化为首条用户消息，并在会话日志水合后回填权威标题。
- **每会话状态**：`blocked`（有未决批准/提问）> `running`（回合打开）> `done`（回合结束且
  有标题）> `idle`（已订阅未开始）。未订阅的会话仍被跟踪但**不出现在快照里**（订阅列表为准）。
- **聚合状态**：任一订阅会话阻塞 → 红；否则任一运行 → 黄；否则全部完成 → 绿；无订阅 → 暗。
- `turn/start` → `open=true`，清阻塞；`turn/end` → `open=false`，清阻塞。
- `approval/asked`/`approval/decided` 与 `tool/call(ask_user_question)`/`tool/result` →
  维护每会话阻塞集合；阻塞文案放 `detail`。
- 订阅变更（Web 按钮 / overlay 行内 ⊖ / API）立即生效并持久化、广播给所有客户端。

## 已知限制 / 可扩展点

- **会话侧栏 "…" 菜单不可扩展**：`dsh-client-ui-workspace` 的 `SessionNodeItem` 菜单为
  硬编码（重命名/fork/归档），无插槽；订阅入口因此放在会话头部操作行
  （`conversation.session.header.actions`，官方附加槽）。若坚持要进 "…" 菜单，只能对
  `dsh-client-ui-workspace` 做 DOM 注入（脆弱、随版本漂移），或改官方包源码。
- **窗口自适应已支持**：宽度随最长行标题 300–560pt，高度随行数（默认最多显示 6 行，
  超出滚动区域），右侧/顶部锚定，避免早期「初始拟合尺寸冻结导致标题截成 …」的问题。
- **标题来源**：`title` 取用户首条文本；如需 dsh 的会话总结标题，可接入 `session-title` 包。
- **单屏渲染**：仅在主屏；多屏可参照 `PassThroughWindow` 按 `NSScreen.screens` 每屏一个。
- **端到端 .app**：编译/签名建议用 Xcode（`overlay/Info.plist` 已就绪）。
