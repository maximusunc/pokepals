# Kithbound

A cozy, 2D, companion-centered world game built in **Godot 4.6** with **GDScript**,
mobile-friendly from the start.

> **Status — Rung 3 complete ✅ · now in Rung 4:** the single-player *companion + world* core
> (Rungs 1–2) is proven, and first two-player shared presence (Rung 3) proved out — two players
> see each other *and* each other’s bonded companion move through the same space. We’re now in
> **Rung 4** (a small persistent shared world); step 1 swaps the transport for WebSockets and
> stands up a *minimal authoritative* Elixir/Phoenix server. Still a test of FEEL, not features.
> See [`CLAUDE.md`](CLAUDE.md) for the full vision and the staged roadmap.

The Godot project lives in the [`pokepals/`](pokepals/) subdirectory. (An earlier
turn-based battle prototype still lives under `scripts/battle/` + `scripts/ui/` +
`scenes/battle.tscn`; it predates the pivot to Kithbound and is kept for reference.)

## Architecture

Two disciplines held from day one:

1. **Separate logic from presentation.** The companion's *mind* —
   [`scripts/world/companion_brain.gd`](pokepals/scripts/world/companion_brain.gd) —
   is pure behavior logic: a `RefCounted` that takes positions and world events in
   and returns *intent* out (where it wants to go, what it's looking at, how it
   feels). It references no nodes, UI, or rendering.
2. **Keep the world layer presentation-agnostic.** The brain works in abstract
   geometry (`Vector2`), so it isn't welded to 2D and could later run under a
   different presentation or on a server. The presentation layer
   ([`scripts/presentation/`](pokepals/scripts/presentation)) reads that intent and
   makes it look alive — easing, eyes that turn toward what it's attending to, bobs
   and hops.

```
pokepals/
  scripts/world/         PURE world/companion logic (companion_brain, world_data) — no UI refs
  scripts/presentation/  player, companion view, world art, camera, joystick, world controller
  scenes/                world.tscn (main scene) + player.tscn + companion.tscn
  data/                  companion.json (feel tunables), world.json (hand-placed clearing)
  tests/                 headless tests for the pure logic + scene smoke tests
```

## Play it

1. Install [Godot 4.6](https://godotengine.org/download) (standard build, no C#).
2. Open the project: `godot --path pokepals` (or open `pokepals/project.godot` in
   the editor) and press **Play**. The main scene is `scenes/world.tscn`.
3. Wander with **arrow keys / WASD** (or the on-screen thumbstick on touch). Your
   companion trails behind, idles and glances back when you stop, and perks up to
   investigate when you press **Space** to examine a prop (the humming stone, the
   lantern, the wildflowers).

To play it on a phone (where the touch feel actually lives), see
[`docs/mobile-testing.md`](docs/mobile-testing.md) — iOS (needs a Mac) and
Android (no Mac, fastest) walkthroughs. Export presets for both ship in
[`pokepals/export_presets.cfg`](pokepals/export_presets.cfg).

## Run the tests

Fast, dependency-free headless tests cover the pure logic; smoke tests drive the
real scenes end to end.

```sh
# One-time per fresh checkout: import the project so class_name globals register.
godot --headless --path pokepals --import

# Pure-logic tests (companion brain + the legacy battle core):
godot --headless --path pokepals --script res://tests/run_tests.gd

# Scene smoke tests (drive the real scenes; verify wiring runs without errors):
godot --headless --path pokepals --script res://tests/smoke_world.gd
godot --headless --path pokepals --script res://tests/smoke_ui.gd
```

Opening the project in the Godot editor once does the same import as the first
command. (CI-friendly: the test runner's exit code is the number of failures.)

## Tune the feel

The companion's whole personality is data. Edit
[`pokepals/data/companion.json`](pokepals/data/companion.json) — follow distances,
walk/run speed, idle rhythm, curiosity, clinginess — and replay to feel the
difference, no code changes. Reshape the clearing in
[`pokepals/data/world.json`](pokepals/data/world.json).
