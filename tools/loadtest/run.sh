#!/bin/bash
# SC-1 (docs/scaling-design.md): step the crowd up and record where the server stops keeping up.
#
#   tools/loadtest/run.sh [world_uuid] [steps] [seconds_per_step]
#
# Needs: the server running as a named node with the "loadtest" cookie, e.g. from server/:
#   elixir --sname srv --cookie loadtest -S mix run --no-halt
# and Node 22+ and Elixir on PATH. For each step it runs the server probe (server CPU, mailboxes)
# alongside the bots (what players feel: messages, bandwidth, latency), and stops early once latency
# blows past 2 s, since past that point the world is unplayable and the numbers stop meaning much.
# Bots are spread over several Node processes so the bot side can use more than one core; on a
# single machine the bots still compete with the server for CPU, so run them from another machine
# (--url) for the server's true ceiling.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORLD="${1:-11111111-1111-1111-1111-111111111111}"   # the Vale
STEPS="${2:-10 50 100 200 300 500 1000}"
SECS="${3:-40}"
URL="${URL:-ws://127.0.0.1:4000/ws}"
NODE_NAME="${SERVER_NODE:-srv@$(hostname -s)}"
OUT="${OUT:-$HERE/results}"
mkdir -p "$OUT"
STAMP="$(date +%Y%m%d-%H%M%S)"

printf "%6s %7s %9s %10s %9s %9s %9s %6s %11s %12s\n" bots joined recv/bot/s KB/bot/s p50_ms p95_ms p99_ms util world_mbox relay_mbox_max
for N in $STEPS; do
  RAMP=$(( N / 25 + 3 ))                      # join ~25 bots a second, like a busy evening
  PROCS=$(( (N + 149) / 150 )); [ $PROCS -gt 3 ] && PROCS=3
  PER=$(( (N + PROCS - 1) / PROCS ))
  SAMPLES=$(( SECS / 2 ))
  elixir --sname "probe$N" --cookie loadtest "$HERE/probe.exs" "$NODE_NAME" 2 "$SAMPLES" > "$OUT/$STAMP-probe-$N.log" 2>&1 &
  PROBE=$!
  PIDS=()
  for ((k = 0; k < PROCS; k++)); do
    FIRST=$(( k * PER )); COUNT=$PER
    [ $(( FIRST + COUNT )) -gt $N ] && COUNT=$(( N - FIRST ))
    [ $COUNT -le 0 ] && continue
    node "$HERE/bots.mjs" --url "$URL" --world "$WORLD" --bots $COUNT --first $FIRST --seconds "$SECS" --ramp "$RAMP" \
      --json "$OUT/$STAMP-bots-$N-$k.json" > "$OUT/$STAMP-bots-$N-$k.log" 2>&1 &
    PIDS+=($!)
  done
  wait "${PIDS[@]}"
  wait $PROBE 2>/dev/null
  # Combine: the bot summaries (joined summed, rates averaged, latency = the worst process's), and the
  # probe's steady-state rows (the second half of the step).
  LINE=$(node -e '
    const fs = require("fs"); const [out, stamp, n] = process.argv.slice(1);
    const s = fs.readdirSync(out).filter(f => f.startsWith(`${stamp}-bots-${n}-`) && f.endsWith(".json")).map(f => JSON.parse(fs.readFileSync(`${out}/${f}`)));
    const joined = s.reduce((a, x) => a + x.joined, 0);
    const avg = k => s.reduce((a, x) => a + x[k] * x.joined, 0) / Math.max(1, joined);
    const worst = k => Math.max(...s.map(x => x.latency_ms[k] ?? 0));
    console.log([joined, Math.round(avg("recv_state_per_bot_per_s")), avg("kb_per_bot_per_s").toFixed(1), worst("p50"), worst("p95"), worst("p99")].join(" "));
  ' "$OUT" "$STAMP" "$N")
  PROBE_STEADY=$(awk 'NR > 2 && $2 ~ /^[0-9.]+$/ && $7 > 0 { rows[++n] = $0 } END {
      if (n == 0) { print "- - -"; exit }
      u = 0; wm = 0; sm = 0; c = 0
      for (i = int(n / 2) + 1; i <= n; i++) { split(rows[i], f, " "); u += f[2]; if (f[5] > wm) wm = f[5]; if (f[9] > sm) sm = f[9]; if (f[11] > sm) sm = f[11]; c++ }
      printf "%.2f %d %d\n", u / c, wm, sm }' "$OUT/$STAMP-probe-$N.log")
  read -r J R K P50 P95 P99 <<< "$LINE"
  read -r U WM SM <<< "$PROBE_STEADY"
  printf "%6s %7s %9s %10s %9s %9s %9s %6s %11s %12s\n" "$N" "$J" "$R" "$K" "$P50" "$P95" "$P99" "$U" "$WM" "$SM" | tee -a "$OUT/$STAMP-summary.txt"
  if [ "${P95:-0}" != "null" ] && [ "${P95:-0}" -gt 2000 ] 2>/dev/null; then
    echo "stopping: p95 latency ${P95} ms is past the point of being playable" | tee -a "$OUT/$STAMP-summary.txt"
    break
  fi
  sleep 5   # let the server drain and Presence settle between steps
done
echo "logs: $OUT/$STAMP-*"
