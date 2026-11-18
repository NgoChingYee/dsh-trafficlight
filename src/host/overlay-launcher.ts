// host/overlay-launcher.ts — auto-start the macOS traffic-light overlay when
// the user subscribes a session (or when the host boots with subscriptions
// already persisted) and no overlay instance is running.
//
// The overlay binary ships with the plugin source tree; in a full `pnpm add`
// install it may be absent, in which case this is a no-op and the user starts
// the overlay manually (scripts/trafficlight.sh). Override the binary path
// with DSH_TL_OVERLAY_BIN when the app lives elsewhere.
import { execFile, spawn } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type { Context } from '@deepseek-ai/cordis'

const OVERLAY_NAME = 'TrafficLightOverlay'

/** Resolve the overlay binary path, or undefined when not present. */
export function overlayBinary(): string | undefined {
  const env = process.env.DSH_TL_OVERLAY_BIN
  if (env !== undefined && env !== '') {
    return fs.existsSync(env) ? env : undefined
  }
  // lib/host/overlay-launcher.js -> plugin root
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
  const candidate = path.join(root, 'overlay', '.build', 'release', OVERLAY_NAME)
  return fs.existsSync(candidate) ? candidate : undefined
}

function isRunning(): Promise<boolean> {
  return new Promise((resolve) => {
    execFile('pgrep', ['-x', OVERLAY_NAME], { timeout: 3000 }, (error) => {
      resolve(error === null)
    })
  })
}

/** Spawn the overlay detached unless it is already running. Best-effort;
 * failures are logged, never thrown. */
export async function maybeStartOverlay(ctx: Context): Promise<void> {
  const bin = overlayBinary()
  if (bin === undefined) {
    warn(ctx, 'overlay binary not found — skip auto-start (install overlay/ or set DSH_TL_OVERLAY_BIN)')
    return
  }
  try {
    if (await isRunning()) return // already up (user-started or earlier auto-start)
    const child = spawn(bin, [], { detached: true, stdio: 'ignore' })
    child.unref()
    info(ctx, `auto-started traffic-light overlay: ${bin}`)
  } catch (error) {
    warn(ctx, `overlay auto-start failed: ${String(error)}`)
  }
}

function warn(ctx: Context, message: string): void {
  try {
    ctx.logger?.warn?.(`[dsh-trafficlight] ${message}`)
  } catch {
    /* ignore */
  }
}

function info(ctx: Context, message: string): void {
  try {
    ctx.logger?.info?.(`[dsh-trafficlight] ${message}`)
  } catch {
    /* ignore */
  }
}