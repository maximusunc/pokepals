#!/usr/bin/env python3
"""Generate the hedge-maze world seed (server/priv/world_seeds/maze.json).

A gigantic, server-canonical hedge maze. The maze is a PERFECT maze (exactly one
path between any two cells) carved by a recursive-backtracker, so the centre is
always reachable from the south entrance. Walls become tall HEDGE segments; the
generator merges colinear walls into long runs so the world is a few hundred
hedges, not thousands of little ones.

Layout:
  * A square grid of NxN corridor cells, walls (hedges) between and around them.
  * A 3x3 open PLAZA at the dead centre with the portal back to the Vale in the
    middle of it. Reaching it pays 10 coins (server-authoritative; see
    world_channel.ex). The portal is the ONLY way back besides the Return button.
  * A single ENTRANCE gap in the south perimeter; the player spawns just inside it.

Geometry is data-only: world_controller/solids/world_art read the "hedges" array
(segments with a thickness) the same way the Ruin reads its columns. Re-run this
to retune size/spacing; commit the regenerated maze.json.

  python3 tools/generate_maze.py
"""

import json
import os
import random

# ── Tunables ─────────────────────────────────────────────────────────────────
SEED = 0xC0FFEE          # fixed, so the maze is identical every regenerate
CELLS = 19               # NxN corridor cells (odd → a single centre cell). "Gigantic".
CORRIDOR = 72.0          # walkable width of a corridor (px)
HEDGE = 28.0             # hedge wall thickness (px)
PLAZA_RADIUS = 1         # plaza is (2*PLAZA_RADIUS+1) cells square, centred
PAD = 22.0               # thin margin between the perimeter hedge and the world bounds

WORLD_ID = "maze"
VALE_ID = "11111111-1111-1111-1111-111111111111"
OUT = os.path.join(os.path.dirname(__file__), "..", "server", "priv", "world_seeds", "maze.json")

# Doubled-grid size: corridor cells at odd indices, walls at even indices.
G = 2 * CELLS + 1
CENTER = CELLS // 2


def width(k):
    """World width of grid cell index k (even = hedge, odd = corridor)."""
    return HEDGE if k % 2 == 0 else CORRIDOR


# Cumulative offset to the START of grid cell k, and the total span.
_offsets = [0.0]
for k in range(G):
    _offsets.append(_offsets[-1] + width(k))
SPAN = _offsets[G]
ORIGIN = -SPAN / 2.0


def center_of(k):
    """World coordinate of the CENTRE of grid cell index k along one axis."""
    return ORIGIN + _offsets[k] + width(k) / 2.0


def cell_grid(cx, cy):
    """Grid index of a corridor cell (cx, cy)."""
    return (2 * cx + 1, 2 * cy + 1)


def carve_maze():
    """Recursive-backtracker. Returns the set of open passages between cells."""
    rng = random.Random(SEED)
    visited = [[False] * CELLS for _ in range(CELLS)]
    passages = set()  # frozenset({(cx,cy),(nx,ny)})
    stack = [(CENTER, CENTER)]
    visited[CENTER][CENTER] = True
    while stack:
        cx, cy = stack[-1]
        nbrs = []
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < CELLS and 0 <= ny < CELLS and not visited[nx][ny]:
                nbrs.append((nx, ny))
        if not nbrs:
            stack.pop()
            continue
        nx, ny = rng.choice(nbrs)
        visited[nx][ny] = True
        passages.add(frozenset({(cx, cy), (nx, ny)}))
        stack.append((nx, ny))
    return passages


def build_wall_grid(passages):
    """True = hedge present. Corridor cells open; open passages punch through walls."""
    grid = [[True] * G for _ in range(G)]
    for cx in range(CELLS):
        for cy in range(CELLS):
            gx, gy = cell_grid(cx, cy)
            grid[gx][gy] = False
    for pas in passages:
        (ax, ay), (bx, by) = tuple(pas)
        gx = ax + bx + 1
        gy = ay + by + 1
        grid[gx][gy] = False

    # Centre PLAZA: open the (2r+1) square of cells and every wall between them.
    plaza = range(CENTER - PLAZA_RADIUS, CENTER + PLAZA_RADIUS + 1)
    for cx in plaza:
        for cy in plaza:
            gx, gy = cell_grid(cx, cy)
            grid[gx][gy] = False
            if cx + 1 in plaza:
                grid[gx + 1][gy] = False
            if cy + 1 in plaza:
                grid[gx][gy + 1] = False

    # SOUTH entrance: open the perimeter wall directly below the centre column.
    grid[2 * CENTER + 1][G - 1] = False
    return grid


def emit_hedges(grid):
    """Merge colinear True cells into long hedge runs (segments + thickness)."""
    covered = [[False] * G for _ in range(G)]
    hedges = []

    def add(gx0, gy0, gx1, gy1):
        hedges.append({
            "from": [round(center_of(gx0), 1), round(center_of(gy0), 1)],
            "to": [round(center_of(gx1), 1), round(center_of(gy1), 1)],
            "thickness": HEDGE,
        })

    # Horizontal runs (length >= 2) along even rows.
    for gy in range(0, G, 2):
        gx = 0
        while gx < G:
            if grid[gx][gy]:
                start = gx
                while gx < G and grid[gx][gy]:
                    gx += 1
                end = gx - 1
                if end - start >= 1:
                    add(start, gy, end, gy)
                    for k in range(start, end + 1):
                        covered[k][gy] = True
            else:
                gx += 1

    # Vertical runs (length >= 2) along even columns.
    for gx in range(0, G, 2):
        gy = 0
        while gy < G:
            if grid[gx][gy]:
                start = gy
                while gy < G and grid[gx][gy]:
                    gy += 1
                end = gy - 1
                if end - start >= 1:
                    add(gx, start, gx, end)
                    for k in range(start, end + 1):
                        covered[gx][k] = True
            else:
                gy += 1

    # Any leftover hedge cell (e.g. an isolated junction post) → a unit hedge.
    for gx in range(G):
        for gy in range(G):
            if grid[gx][gy] and not covered[gx][gy]:
                add(gx, gy, gx, gy)
    return hedges


def main():
    passages = carve_maze()
    grid = build_wall_grid(passages)
    hedges = emit_hedges(grid)

    cx_world = center_of(2 * CENTER + 1)
    cy_world = center_of(2 * CENTER + 1)
    # Spawn just inside the south entrance, in the entrance corridor cell.
    spawn_gy = 2 * (CELLS - 1) + 1
    spawn_x = center_of(2 * CENTER + 1)
    spawn_y = center_of(spawn_gy)

    half = SPAN / 2.0 + PAD
    plaza_half = (PLAZA_RADIUS + 0.5) * (CORRIDOR + HEDGE)

    spec = {
        "_comment": (
            "THE HEDGE MAZE — a gigantic perfect maze of tall hedges. Generated by "
            "tools/generate_maze.py (recursive-backtracker; re-run to retune). The portal "
            "home sits in the centre plaza; reaching the centre pays 10 coins "
            "(server-authoritative, see world_channel.ex). A Return-to-the-Vale button is "
            "always offered in case you get lost. 'hedges' are wall SEGMENTS with a "
            "thickness — solids.gd collides against them, world_art.gd draws them."
        ),
        "world_id": WORLD_ID,
        "regions": [
            {"id": "hedge_maze", "min": [round(-half, 1), round(-half, 1)],
             "max": [round(half, 1), round(half, 1)], "tint": [0.42, 0.58, 0.40]},
            {"id": "heart", "min": [round(cx_world - plaza_half, 1), round(cy_world - plaza_half, 1)],
             "max": [round(cx_world + plaza_half, 1), round(cy_world + plaza_half, 1)],
             "tint": [0.96, 0.86, 0.52]},
        ],
        "bounds": {"min": [round(-half, 1), round(-half, 1)], "max": [round(half, 1), round(half, 1)]},
        "collision": {"body_radius": 6, "margin": 2},
        "ground_color": [0.40, 0.52, 0.34],
        "atmosphere": {
            "day_tint": [1.02, 1.0, 0.92],
            "vignette": {"strength": 0.30, "color": [0.05, 0.08, 0.05]},
            "wind": {"strength": 1.8, "speed": 1.0},
            "ground_noise": {"contrast": 0.12, "tint": [0.28, 0.40, 0.24]},
            "pollen": {"amount": 22, "color": [0.86, 0.94, 0.74]},
            "glow": {"pulse_speed": 1.3},
        },
        "player_spawn": [round(spawn_x, 1), round(spawn_y, 1)],
        "companion_spawn": [round(spawn_x - 26, 1), round(spawn_y - 18, 1)],
        "hedges": hedges,
        "flowers": [
            [round(cx_world - 30, 1), round(cy_world + 26, 1), 0.95, 0.85, 0.40],
            [round(cx_world + 32, 1), round(cy_world + 20, 1), 0.92, 0.62, 0.30],
            [round(cx_world - 18, 1), round(cy_world - 30, 1), 0.70, 0.55, 0.85],
        ],
        "interactables": [],
        "_goal_comment": (
            "reach_center: detected client-side (within 'radius' of 'center'); the reward "
            "is decided + minted SERVER-side, gated on this goal type (world_channel.ex)."
        ),
        "goal": {
            "type": "reach_center",
            "center": [round(cx_world, 1), round(cy_world, 1)],
            "radius": 70.0,
            "reward": 10,
            "label": "Find the heart of the maze",
        },
        "_return_comment": "Where the always-available 'Return to the Vale' button sends you.",
        "return": {"world": VALE_ID, "portal": "vale_maze_portal", "label": "Return to the Vale"},
        "portals": [
            {"id": "maze_heart", "type": "portal", "position": [round(cx_world, 1), round(cy_world, 1)],
             "color": [0.74, 0.66, 0.96], "label": "a shimmering portal",
             "target_world": VALE_ID, "target_portal": "vale_maze_portal"},
        ],
    }

    with open(OUT, "w") as f:
        json.dump(spec, f, indent="\t")
        f.write("\n")
    print(f"Wrote {os.path.relpath(OUT)}: {CELLS}x{CELLS} maze, {len(hedges)} hedges, "
           f"span {SPAN:.0f}px, centre ({cx_world:.0f},{cy_world:.0f}).")


if __name__ == "__main__":
    main()
