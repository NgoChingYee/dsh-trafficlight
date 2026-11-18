#!/usr/bin/env bash
# trafficlight.sh — 一句命令启动 DSH 任务状态红绿灯（macOS 悬浮窗）。
#
#   bash scripts/trafficlight.sh
#
# 行为：
#   1. 若未编译或 Swift 源码比二进制新 → 自动 swift build -c release。
#   2. 若已有实例在跑 → 提示并复用（加 --restart 强制重启）。
#   3. 后台启动悬浮窗（nohup + 日志 ~/.dsh/trafficlight-overlay.log）。
#
# 前提：数据源已就绪 —— dsh web（插件自带桥）或 mock-bridge.mjs 二选一；
#       否则悬浮窗显示「未连接 DSH」。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/overlay/.build/release/TrafficLightOverlay"
LOG="${TL_LOG:-$HOME/.dsh/trafficlight-overlay.log}"

RESTART=0
[[ "${1:-}" == "--restart" ]] && RESTART=1

if pgrep -x TrafficLightOverlay >/dev/null 2>&1; then
  if [[ "$RESTART" == "0" ]]; then
    echo "红绿灯已在运行（PID $(pgrep -x TrafficLightOverlay | head -1)）。"
    echo "如需重启：bash scripts/trafficlight.sh --restart"
    exit 0
  fi
  echo "停止旧实例…"
  pkill -x TrafficLightOverlay || true
  sleep 1
fi

# 需要重编？(无二进制，或任一 .swift 比二进制新)
NEED_BUILD=0
if [[ ! -x "$BIN" ]]; then
  NEED_BUILD=1
else
  if find "$ROOT/overlay" -maxdepth 1 -name "*.swift" -newer "$BIN" -print -quit | grep -q .; then
    NEED_BUILD=1
  fi
fi

if [[ "$NEED_BUILD" == "1" ]]; then
  echo "源码有更新，重新编译…"
  (cd "$ROOT/overlay" && bash build.sh >/dev/null)
fi

echo "启动红绿灯悬浮窗…"
mkdir -p "$(dirname "$LOG")"
nohup "$BIN" >"$LOG" 2>&1 &
disown
sleep 1
if pgrep -x TrafficLightOverlay >/dev/null 2>&1; then
  echo "✅ 已启动（PID $(pgrep -x TrafficLightOverlay | head -1)），日志：$LOG"
else
  echo "❌ 启动失败，日志见 $LOG"
  exit 1
fi