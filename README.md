# Pokepals

A 2D, turn-based creature-collector built in **Godot 4.6** with **GDScript**.

> **Status — Rung 1:** a single-player, offline turn-based battle prototype. The
> goal of this phase is to find out whether the core battle is *fun* before any
> networking, overworld, or persistence. See [`CLAUDE.md`](CLAUDE.md) for the full
> vision and the staged roadmap.

The Godot project lives in the [`pokepals/`](pokepals/) subdirectory.

## Architecture

The one rule that matters: **battle resolution is pure logic with zero UI/engine
dependencies.** It lives in [`pokepals/scripts/battle/`](pokepals/scripts/battle)
as static functions that take battle state in and return new state out —
deterministic, JSON-serializable, no node or scene-tree references. The UI reads
that state and renders it; it never computes outcomes itself. This module is meant
to move onto an authoritative server unchanged at a later rung.

```
pokepals/
  scripts/battle/   PURE battle logic (rng, type_chart, data_loader, battle_state, battle_logic)
  scripts/ui/       UI controllers that read state and render it
  scenes/           battle.tscn (main scene) + creature_panel.tscn
  data/             creatures.json, moves.json, types.json — data-driven, retune by editing
  tests/            headless GDScript tests for the pure core
```

## Play it

1. Install [Godot 4.6](https://godotengine.org/download) (standard build, no C#).
2. Open the project: `godot --path pokepals` (or open `pokepals/project.godot` in
   the Godot editor) and press **Play**. The main scene is `scenes/battle.tscn`.
3. A random matchup is drawn each battle. Pick a move each turn; watch the HP bars
   and the battle log. Type matchups follow a cycle: **aqua → ember → flora →
   spark → aqua** (each is super-effective against the next).

## Run the tests

The pure battle core is covered by fast, dependency-free headless tests
(determinism, purity, type wiring, and that battles conclude):

```sh
# One-time per fresh checkout: import the project so class_name globals register.
godot --headless --path pokepals --import

# Run the pure-logic tests (PASS/FAIL per check; exits non-zero on failure):
godot --headless --path pokepals --script res://tests/run_tests.gd

# Optional: drive the real Battle scene through a full turn loop headlessly:
godot --headless --path pokepals --script res://tests/smoke_ui.gd
```

Opening the project in the Godot editor once does the same import as the first
command. (CI-friendly: the test runner's exit code is the number of failures.)

## Retune the balance

All creatures, moves, and type relationships are data. Edit
[`pokepals/data/`](pokepals/data) — no code changes — and re-run to feel the
difference. This data-driven separation is deliberate: rebalance by editing data,
not logic.
