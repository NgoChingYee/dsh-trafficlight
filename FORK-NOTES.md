# dsh-trafficlight fork notes

这是基于 `@chivaskong96/dsh-trafficlight@0.3.0` 的本地 fork，面向 **DSH Desktop 0.2.2-rc.3** 修复和增强。

包名仍保持 `@chivaskong96/dsh-trafficlight`，因为插件的 Cordis patch 和 client 注入依赖该标识；修改的是 fork 内容、版本号、说明和仓库地址。

## 已包含改动

- 修复从 GitHub 安装副本缺少 `lib/` 构建产物导致插件启用失败的问题（包内已含 `lib/`）。
- 修复悬浮窗偶发消失：每 2 秒重新置顶，并把移出屏幕的窗口拉回主屏。
- 修复暗色模式下会话头部「🚦 订阅」按钮文字看不清的问题。
- 点击悬浮窗中的订阅会话，可把 DSH 窗口带到前台并打开对应会话：
  - 浮窗 → 本机 `POST /focus`
  - DSH Web → `GET /api/dsh-tl/focus`
  - 页面调用 `uiWorkspace.openSession(id)`，兼容 `sessions.open(id)`。
- 悬浮窗标题优先使用真实对话标题：
  - DSH `sessionTitle` 服务；
  - 会话标题投影缓存 `session_projcache`；
  - 可靠持久化到订阅文件；
  - 不再用普通用户消息覆盖真实标题。
- 订阅文件支持新旧格式：
  - 旧：`["session-id"]`
  - 新：`{ "subscriptions": ["session-id"], "titles": { "session-id": "真实标题" } }`
- 普通模式右侧边缘可拖动调整宽度；手动宽度持久化。
- 默认自动宽度 `165pt`，最小 `150pt`，最大 `560pt`。
- 保留已编译的 macOS arm64 `TrafficLightOverlay` 二进制。

完整补丁细节见 [docs/LOCAL-PATCHES.md](./docs/LOCAL-PATCHES.md)。

## 安装

从仓库安装：

```bash
dsh plugin --profile desktop add github:erinwangstudio-art/dsh-trafficlight
```

或在 DSH 插件管理里添加该 Git 仓库地址。

安装后重启 DSH Desktop。若悬浮窗没有自动出现，在任意会话头部点击「🚦 订阅」，或手动启动：

```bash
bash "$HOME/.dsh/profiles/desktop/node_modules/@chivaskong96/dsh-trafficlight/scripts/trafficlight.sh"
```

## 重要说明

- 上游 npm 包声明的开发依赖 `@deepseek-ai/dsh-client-runtime@^0.1.5-rc.1` 已无法从 npm 获取，因此本 fork 的 `lib/` 和已编译二进制是随仓库一起提供的运行产物。
- 如需重新构建 Swift 悬浮窗，在当前机器上可使用 macOS 26.2 SDK：

```bash
DSH_TL_OVERLAY_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk bash overlay/build.sh
```

- 上游许可见 `LICENSE`。
