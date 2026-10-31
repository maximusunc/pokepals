#!/usr/bin/env node
// SC-1 (docs/scaling-design.md): a crowd of bot players that speak the REAL client protocol (Phoenix
// channels v2 over a WebSocket, exactly as scripts/net/net.gd does), join one world, and wander about
// near its spawn, sending their transforms at the client's rate (20 Hz). They measure what a real
// player would feel:
//   - how many peer updates / bytes per second each one receives (a peer update is one entry in a
//     "states" bundle since SC-3, or one "state" frame from an older server),
//   - LATENCY: every bot stamps its packets with the send time ("t", ms), and the server relays the
//     transform untouched, so a receiver on the same machine can tell how old each peer update is
//     when it lands. A server that can't keep up shows here first, as latency climbing.
//
// Node 22+ (built-in WebSocket; no npm install). Usage:
//   node tools/loadtest/bots.mjs --url ws://127.0.0.1:4000/ws --world <world-uuid> --bots 100 \
//        --seconds 30 [--hz 20] [--ramp 10] [--radius 300] [--prefix lt] [--first 0] [--json out.json]
// With --first / --bots, several bot processes can share one run (each takes its own index range),
// so the bot side can use more than one CPU core.

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
  if (a.startsWith("--")) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith("--") ? all[i + 1] : "true"]);
  return acc;
}, []));
const URL_BASE = (args.url || "ws://127.0.0.1:4000/ws").replace(/\/+$/, "");
const WORLD = args.world;
const BOTS = Number(args.bots || 10);
const FIRST = Number(args.first || 0);
const SECONDS = Number(args.seconds || 30);
const HZ = Number(args.hz || 20);
const RAMP = Number(args.ramp || 10);       // seconds over which the bots join
const RADIUS = Number(args.radius || 300);  // how far from spawn they wander
const PREFIX = args.prefix || "lt";
if (!WORLD) { console.error("--world <uuid> is required"); process.exit(2); }

const topic = `world:${WORLD}`;
// The bots' own health: if this process's event loop is lagging, it's reading slowly and the latency
// it reports is partly ITS fault (TCP backs up into the server). Reported so a run can be trusted.
import { monitorEventLoopDelay } from "node:perf_hooks";
const loopLag = monitorEventLoopDelay({ resolution: 20 });
loopLag.enable();
const now = () => Date.now();

// ── aggregate stats (reset each reporting window) ──────────────────────────────────────────────────────
const total = { connected: 0, joined: 0, failed: 0, closed: 0, sent: 0, recvState: 0, recvOther: 0, bytes: 0 };
let win = { sent: 0, recvState: 0, recvOther: 0, bytes: 0, frames: 0, lat: [] };
const allLat = [];           // every latency sample during the steady part (after the ramp)
const steadyFrom = () => startedAt + (RAMP + 2) * 1000;
let startedAt = 0;
let maxLoopLag = 0;  // worst per-second p99 event-loop lag seen after the ramp

function pct(arr, p) {
  if (arr.length === 0) return null;
  const s = Float64Array.from(arr).sort();
  return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))];
}

class Bot {
  constructor(i) {
    this.i = i;
    this.token = `${PREFIX}-bot-${i}`;
    this.ref = 1;
    this.joinRef = null;
    this.joined = false;
    this.pos = null;
    this.home = null;
    this.target = null;
    this.timers = [];
  }

  send(frame) {
    if (this.ws && this.ws.readyState === 1) this.ws.send(JSON.stringify(frame));
  }

  start() {
    const url = `${URL_BASE}/websocket?vsn=2.0.0&token=${encodeURIComponent(this.token)}`;
    const ws = new WebSocket(url);
    this.ws = ws;
    ws.onopen = () => {
      total.connected++;
      this.joinRef = String(this.ref++);
      this.send([this.joinRef, this.joinRef, topic, "phx_join", { known_etag: "" }]);
      // Phoenix closes a silent socket; heartbeat like the client does.
      this.timers.push(setInterval(() => this.send([null, String(this.ref++), "phoenix", "heartbeat", {}]), 25000));
    };
    ws.onmessage = (ev) => this.onFrame(ev.data);
    ws.onerror = () => {};
    ws.onclose = () => {
      if (!this.joined) total.failed++;
      total.closed++;
      this.stop();
    };
  }

  onFrame(data) {
    const len = typeof data === "string" ? data.length : data.byteLength || 0;
    win.bytes += len;
    total.bytes += len;
    let f;
    try { f = JSON.parse(data); } catch { return; }
    const [, , , event, payload] = f;
    if (event === "states" && payload && Array.isArray(payload.s)) {
      // SC-3: one bundle per server tick: [[id, px, py, fx, fy, cx, cy, lx, ly, t?], ...]
      win.frames++;
      for (const e of payload.s) {
        if (!Array.isArray(e) || e[0] === this.myId) continue;
        win.recvState++;
        total.recvState++;
        if (typeof e[9] === "number") {
          const lat = now() - e[9];
          win.lat.push(lat);
          if (now() >= steadyFrom()) allLat.push(lat);
        }
      }
      return;
    }
    if (event === "welcome" && payload) this.myId = payload.id;
    if (event === "state") {
      win.recvState++;
      total.recvState++;
      if (payload && typeof payload.t === "number") {
        const lat = now() - payload.t;
        win.lat.push(lat);
        if (now() >= steadyFrom()) allLat.push(lat);
      }
      return;
    }
    win.recvOther++;
    total.recvOther++;
    if (event === "phx_reply" && f[1] === this.joinRef) {
      if (payload.status === "ok") {
        this.joined = true;
        total.joined++;
      } else {
        total.failed++;
        this.ws.close();
      }
    } else if (event === "world_spec" && !this.home) {
      const s = payload.player_spawn || payload.spec?.player_spawn || [0, 0];
      this.home = { x: Number(s[0]) || 0, y: Number(s[1]) || 0 };
      this.pos = { x: this.home.x + rnd(-40, 40), y: this.home.y + rnd(-40, 40) };
      this.pickTarget();
      this.timers.push(setInterval(() => this.tick(), 1000 / HZ));
    }
  }

  pickTarget() {
    const a = Math.random() * Math.PI * 2;
    const r = Math.sqrt(Math.random()) * RADIUS;
    this.target = { x: this.home.x + Math.cos(a) * r, y: this.home.y + Math.sin(a) * r };
  }

  // Walk toward a wander target at the avatar's pace, the companion trailing; the same small packet
  // the client sends (p, pf, c, cl), plus our send time.
  tick() {
    if (!this.joined) return;
    const dt = 1 / HZ;
    const dx = this.target.x - this.pos.x, dy = this.target.y - this.pos.y;
    const d = Math.hypot(dx, dy);
    const speed = 140;
    let fx = 0, fy = 1;
    if (d < 8) this.pickTarget();
    else {
      fx = dx / d; fy = dy / d;
      this.pos.x += fx * Math.min(d, speed * dt);
      this.pos.y += fy * Math.min(d, speed * dt);
    }
    this.send([this.joinRef, String(this.ref++), topic, "state", {
      p: [round1(this.pos.x), round1(this.pos.y)], pf: [round2(fx), round2(fy)],
      c: [round1(this.pos.x - fx * 30), round1(this.pos.y - fy * 30 + 10)], cl: [round2(fx), round2(fy)],
      t: now(),
    }]);
    win.sent++;
    total.sent++;
  }

  stop() {
    for (const t of this.timers) clearInterval(t);
    this.timers = [];
  }
}

const rnd = (a, b) => a + Math.random() * (b - a);
const round1 = (v) => Math.round(v * 10) / 10;
const round2 = (v) => Math.round(v * 100) / 100;

// ── run ─────────────────────────────────────────────────────────────────────────────────────────────────
const bots = [];
startedAt = now();
for (let k = 0; k < BOTS; k++) {
  const bot = new Bot(FIRST + k);
  bots.push(bot);
  setTimeout(() => bot.start(), (RAMP * 1000 * k) / Math.max(1, BOTS));
}

const tag = `[bots ${FIRST}..${FIRST + BOTS - 1}]`;
const report = setInterval(() => {
  const n = Math.max(1, total.joined);
  const p50 = pct(win.lat, 50), p95 = pct(win.lat, 95);
  console.log(`${tag} t=${((now() - startedAt) / 1000).toFixed(0)}s joined=${total.joined} failed=${total.failed} ` +
    `sent/s=${win.sent} recv/bot/s=${(win.recvState / n).toFixed(0)} KB/bot/s=${(win.bytes / n / 1024).toFixed(1)} ` +
    `lat p50=${p50 ?? "-"}ms p95=${p95 ?? "-"}ms loop_lag_p99=${(loopLag.percentile(99) / 1e6).toFixed(0)}ms`);
  loopLag.reset();
  win = { sent: 0, recvState: 0, recvOther: 0, bytes: 0, frames: 0, lat: [] };
}, 1000);
setInterval(() => {
  if (now() >= steadyFrom()) maxLoopLag = Math.max(maxLoopLag, loopLag.percentile(99) / 1e6);
}, 900);

setTimeout(() => {
  clearInterval(report);
  const steadySecs = Math.max(1, SECONDS - RAMP - 2);
  const n = Math.max(1, total.joined);
  const summary = {
    bots: BOTS, joined: total.joined, failed: total.failed, closed_early: total.closed,
    sent_total: total.sent,
    recv_state_per_bot_per_s: Math.round(total.recvState / n / SECONDS),
    kb_per_bot_per_s: Math.round((total.bytes / n / 1024 / SECONDS) * 10) / 10,
    latency_ms: { p50: pct(allLat, 50), p95: pct(allLat, 95), p99: pct(allLat, 99), max: pct(allLat, 100), samples: allLat.length },
    steady_seconds: steadySecs,
    bot_loop_lag_max_ms: Math.round(maxLoopLag),
  };
  console.log(`${tag} SUMMARY ${JSON.stringify(summary)}`);
  if (args.json) {
    import("node:fs").then((fs) => fs.writeFileSync(args.json, JSON.stringify(summary)));
  }
  for (const b of bots) { b.stop(); try { b.ws?.close(); } catch {} }
  setTimeout(() => process.exit(0), 500);
}, SECONDS * 1000);
