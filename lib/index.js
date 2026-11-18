import { StatusMachine } from "./host/status.js";
import { defaultSettingsFile, SettingsStore } from "./host/settings.js";
import { SubscriptionStore, defaultSubsFile } from "./host/subscriptions.js";
import { startStandaloneServer, registerWebRoutes } from "./host/bridge.js";
const DEFAULT_PORT = 18_765;
/** Required services. */
export const inject = ['webServer', 'systemPrompt'];
/** Model-facing announcement (so agents cooperate and avoid surprise asks). */
export const GUIDANCE = '本机已安装 dsh-trafficlight 插件：你把想关注的会话加入订阅后（在 dsh 会话菜单里点「添加订阅」），' +
    '该会话的任务状态会以红/黄/绿三色灯的形式在 macOS 全局悬浮窗中逐条展示' +
    '（红灯=等待批准或提问阻塞，黄灯=任务执行中，绿灯=任务已完成）；悬浮窗中每行可单独取消订阅。' +
    '在 dsh 设置面板（通用区）可调悬浮窗透明度（滑块）和极简模式（开关）；极简模式只显示' +
    '拖动按钮、关闭按钮和一个跟随“最近一次更新状态”的大信号灯，忽略是哪个会话触发的。';
export function apply(ctx) {
    const subs = new SubscriptionStore(ctx, defaultSubsFile());
    const settings = new SettingsStore(ctx, defaultSettingsFile());
    const status = new StatusMachine(ctx, subs, settings);
    // Live fold of the session/event firehose.
    ctx.effect(() => status.attach(), 'dsh-trafficlight: firehose');
    // Standalone loopback bridge (fixed port) for the native macOS overlay.
    const rawPort = Number(process.env.DSH_TL_PORT ?? '18765');
    const port = Number.isFinite(rawPort) && rawPort > 0 ? rawPort : DEFAULT_PORT;
    ctx.effect(() => startStandaloneServer(status, port, ctx), 'dsh-trafficlight: bridge');
    // Same snapshot under the dsh webServer for in-page widgets.
    ctx.effect(() => registerWebRoutes(ctx, status), 'dsh-trafficlight: web routes');
    // Announce the plugin to the model so it can avoid redundant prompts.
    ctx.effect(() => {
        return ctx.systemPrompt.section({
            name: 'plugin:dsh-trafficlight',
            order: 216,
            text: GUIDANCE,
        });
    }, 'dsh-trafficlight: prompt section');
}
