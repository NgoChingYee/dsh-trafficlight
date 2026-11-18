// mock-bridge.mjs — a stand-alone replica of the dsh-trafficlight bridge.
//
// Use it to test the macOS overlay WITHOUT running dsh. It serves the exact
// same payload shape the real plugin serves — a LIST of subscribed sessions,
// each with its own title + light state — cycling their states so you can see
// red / yellow / green per row live. It also honours POST/DELETE
// /subscriptions so the overlay's per-row unsubscribe button works.
//
//   node mock-bridge.mjs            # listens on http://127.0.0.1:18765/state
//   (then run the overlay: ./.build/release/TrafficLightOverlay)
import http from 'node:http'

const DEFAULT_PORT = 18_765
const port = Number(process.env.DSH_TL_PORT ?? DEFAULT_PORT)

// Fake sessions. `title` mirrors how dsh titles a session from its first user
// message; `detail` carries the transient blocked reason.
const FAKE = [
  { sessionId: 'ses-aaaa-0001', title: 'Android 中高级岗面试复习', detail: 'DSH 需要批准: 执行 shell 命令' },
  { sessionId: 'ses-bbbb-0002', title: 'HarmonyOS 桌面小组件开发', detail: 'DSH 向你提问: 继续推离线方案吗？' },
  { sessionId: 'ses-cccc-0003', title: 'dsh 红绿灯订阅制改造', detail: '' },
]

// Step -> per-index state.
const STEPS = [
  ['running', 'blocked', 'done'],
  ['running', 'running', 'done'],
  ['running', 'done', 'blocked'],
  ['done', 'blocked', 'running'],
  ['done', 'done', 'done'],
]

let step = 0
const subscribed = new Set(FAKE.map((s) => s.sessionId))
const subscribers = new Set()

function sessionState(sessionId) {
  const idx = FAKE.findIndex((s) => s.sessionId === sessionId)
  if (idx < 0) return 'idle'
  return STEPS[step][idx] ?? 'idle'
}

function currentSnapshot() {
  const sessions = FAKE.filter((s) => subscribed.has(s.sessionId)).map((s) => ({
    sessionId: s.sessionId,
    title: s.title,
    state: sessionState(s.sessionId),
    detail: sessionState(s.sessionId) === 'blocked' ? s.detail : '',
  }))
  let state = 'idle'
  if (sessions.some((s) => s.state === 'blocked')) state = 'blocked'
  else if (sessions.some((s) => s.state === 'running')) state = 'running'
  else if (sessions.length > 0) state = 'done'
  return {
    state,
    title: sessions.find((s) => s.state !== 'idle')?.title ?? (sessions[0]?.title ?? 'DSH'),
    sessions,
    subscribed: [...subscribed],
    updatedAt: Date.now(),
  }
}

function broadcast() {
  const snap = currentSnapshot()
  for (const res of subscribers) {
    try {
      res.write(`event: trafficlight\ndata: ${JSON.stringify(snap)}\n\n`)
    } catch {
      subscribers.delete(res)
    }
  }
}

setInterval(() => {
  step = (step + 1) % STEPS.length
  broadcast()
}, 3000)

function readJson(req) {
  return new Promise((resolve) => {
    let buf = ''
    req.on('data', (c) => (buf += String(c)))
    req.on('end', () => {
      try {
        resolve(JSON.parse(buf))
      } catch {
        resolve(undefined)
      }
    })
    req.on('error', () => resolve(undefined))
  })
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', 'http://x')
  const json = (code, obj) => {
    res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' })
    res.end(JSON.stringify(obj))
  }
  if (req.method === 'GET' && (url.pathname === '/state' || url.pathname === '/')) {
    json(200, currentSnapshot())
    return
  }
  if (req.method === 'GET' && url.pathname === '/stream') {
    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache',
      connection: 'keep-alive',
    })
    res.write('retry: 2000\n\n')
    res.write(`event: trafficlight\ndata: ${JSON.stringify(currentSnapshot())}\n\n`)
    subscribers.add(res)
    req.on('close', () => subscribers.delete(res))
    return
  }
  if (req.method === 'GET' && url.pathname === '/subscriptions') {
    json(200, { ok: true, value: { subscribed: [...subscribed] } })
    return
  }
  if (req.method === 'POST' && url.pathname === '/subscriptions') {
    const body = await readJson(req)
    const id = String(body?.sessionId ?? '')
    if (!id) return json(400, { ok: false, error: { code: 'bad-request', message: 'sessionId required' } })
    const changed = !subscribed.has(id)
    subscribed.add(id)
    broadcast()
    return json(200, { ok: true, value: { subscribed: [...subscribed], changed } })
  }
  if (req.method === 'DELETE' && url.pathname === '/subscriptions') {
    const id = url.searchParams.get('sessionId') ?? ''
    if (!id) return json(400, { ok: false, error: { code: 'bad-request', message: 'sessionId required' } })
    const changed = subscribed.delete(id)
    broadcast()
    return json(200, { ok: true, value: { subscribed: [...subscribed], changed } })
  }
  json(404, { ok: false, error: { code: 'not-found', message: 'no route' } })
})

server.listen(port, '127.0.0.1', () => {
  console.log(`[mock-bridge] traffic-light bridge on http://127.0.0.1:${port}/state`)
  console.log('[mock-bridge] 3 demo sessions cycling running/blocked/done every 3s')
  console.log('[mock-bridge] POST/DELETE /subscriptions?sessionId=... to add/remove rows')
})