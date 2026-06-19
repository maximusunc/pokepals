#!/usr/bin/env python3
"""Generate the player pixel-art sprite sheet — "The Hooded Wanderer".

Why this exists: the art is authored *here*, in code, as a small set of named colors
and a few composable primitives, so the whole look lives in the diff and is trivially
tweakable (change a number, re-run). No third-party deps — the PNG is written by hand
with zlib + struct so it runs anywhere, and a --preview mode prints the frames as ASCII
so you can eyeball the silhouette without opening Godot.

Output: assets/sprites/player.png — a 128x96 sheet, 32x32 frames,
    rows = facing (down, side, up); cols = 4-frame walk cycle (col 0 = idle).
Left-facing is the SIDE row drawn flipped at runtime (see sprite_actor.gd).

Run from anywhere:  python3 pokepals/tools/gen_player_sprite.py [--preview]
"""

import os
import sys
import zlib
import struct

# --- Palette -----------------------------------------------------------------
# Colors echo data/art.json's player entry so the sprite still pairs with the
# earthy procedural companion: cloak = player "body", face = player "accent".
# A subtle up-left rim ('L') matches the world's light.dir for cohesion.
TRANSPARENT = (0, 0, 0, 0)
PALETTE = {
    ".": TRANSPARENT,
    "C": (194, 133, 102, 255),  # cloak mid   (body  [0.76,0.52,0.40])
    "D": (138, 94, 71, 255),    # cloak shade (lower folds / hem)
    "L": (240, 206, 166, 255),  # rim light   (up-left edge highlight)
    "F": (245, 207, 171, 255),  # face        (accent [0.96,0.81,0.67])
    "E": (44, 36, 46, 255),     # eyes
    "S": (105, 77, 54, 255),    # satchel     (bark [0.41,0.30,0.21])
    "s": (146, 110, 78, 255),   # satchel highlight / strap
    "b": (74, 53, 42, 255),     # boots
    "o": (38, 28, 32, 255),     # outline (auto-traced silhouette)
}
BODY = set("CDLFESsb")  # everything that counts as "solid" for outline/rim passes

SIZE = 32          # frame is SIZE x SIZE
COLS, ROWS = 4, 3  # 4 walk frames, 3 facings


# --- Tiny raster helpers (operate on a SIZE x SIZE list-of-lists of chars) ----
def blank():
    return [["." for _ in range(SIZE)] for _ in range(SIZE)]


def put(g, x, y, ch):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        g[y][x] = ch


def disk(g, cx, cy, r, ch):
    """Filled circle; fractional radius gives rounder small shapes."""
    r2 = r * r
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r2:
                put(g, x, y, ch)


def cloak(g, top_y, bot_y, w_top, w_bot, dy=0, hem_dx=0):
    """A bell-shaped body: half-width grows linearly top->bottom, swaying at the hem.
    Lower third is shaded 'D' to read as heavy fabric falling into shadow."""
    span = max(1, bot_y - top_y)
    for y in range(top_y, bot_y + 1):
        f = (y - top_y) / span
        w = round(w_top + (w_bot - w_top) * f)
        dx = round(hem_dx * f)
        left, right = 16 - w + dx, 16 + w - 1 + dx
        ch = "D" if f > 0.6 else "C"
        for x in range(left, right + 1):
            put(g, x, y + dy, ch)


def trace_outline(g):
    """Any transparent pixel touching the silhouette becomes the dark outline."""
    out = [row[:] for row in g]
    for y in range(SIZE):
        for x in range(SIZE):
            if g[y][x] != ".":
                continue
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < SIZE and 0 <= ny < SIZE and g[ny][nx] in BODY:
                    out[y][x] = "o"
                    break
    return out


def add_rim(g):
    """Catch a 1px highlight on the up-left edge of the cloak/hood (matches light.dir)."""
    for y in range(SIZE):
        for x in range(SIZE):
            if g[y][x] in ("C", "D"):
                ux, uy = x - 1, y - 1
                up_left = "." if (ux < 0 or uy < 0) else g[uy][ux]
                if up_left == ".":
                    g[y][x] = "L"


# --- Per-frame walk parameters -----------------------------------------------
# A 2-pose cycle reads as walking: frames 1 & 3 lift the body 1px (a "pass" pose)
# and sway the hem opposite ways; frames 0 & 2 are grounded "contact" poses.
def walk_params(frame):
    bob = -1 if frame in (1, 3) else 0
    hem_dx = {0: 0, 1: 1, 2: 0, 3: -1}[frame]
    return bob, hem_dx


def boots(g, frame, profile=False):
    """Two boots peeking under the hem; they alternate a lifted step. In profile
    one boot sits a touch forward (right) so a side-on stride reads clearly."""
    base_y = 29
    lx, rx = (14, 18) if not profile else (15, 19)
    l_up = 1 if frame == 1 else 0
    r_up = 1 if frame == 3 else 0
    disk(g, lx, base_y - l_up, 1.6, "b")
    disk(g, rx, base_y - r_up, 1.6, "b")


# --- The three facings --------------------------------------------------------
def build_down(frame):
    g = blank()
    bob, hem_dx = walk_params(frame)
    boots(g, frame)
    cloak(g, 11, 26, 4, 8, dy=bob, hem_dx=hem_dx)
    disk(g, 16, 7 + bob, 6.2, "C")              # hood dome
    disk(g, 16, 8 + bob, 3.4, "F")              # face opening
    put(g, 14, 8 + bob, "E")                    # eyes
    put(g, 18, 8 + bob, "E")
    disk(g, 21, 19 + bob, 1.8, "S")             # satchel at the hip
    put(g, 21, 18 + bob, "s")
    for x in range(11, 21):                      # strap across the chest
        put(g, x, 14 + (x - 11) // 3 + bob, "s")
    add_rim(g)
    return trace_outline(g)


def build_side(frame):
    g = blank()
    bob, hem_dx = walk_params(frame)
    boots(g, frame, profile=True)
    cloak(g, 11, 26, 4, 7, dy=bob, hem_dx=hem_dx)
    disk(g, 17, 7 + bob, 6.0, "C")              # hood, nudged toward facing (right)
    disk(g, 19, 8 + bob, 2.8, "F")              # face peeking out the front
    put(g, 21, 8 + bob, "F")                    # tip of the nose
    put(g, 20, 8 + bob, "E")                    # single visible eye
    disk(g, 11, 18 + bob, 2.0, "S")             # satchel slung on the back
    put(g, 11, 17 + bob, "s")
    add_rim(g)
    return trace_outline(g)


def build_up(frame):
    g = blank()
    bob, hem_dx = walk_params(frame)
    boots(g, frame)
    cloak(g, 11, 26, 4, 8, dy=bob, hem_dx=hem_dx)
    disk(g, 16, 7 + bob, 6.2, "C")              # back of the hood — no face (eyes hidden)
    for y in range(13, 25):                      # center seam down the cloak's back
        put(g, 16, y + bob, "D")
    for x in range(11, 21):                      # satchel strap visible from behind
        put(g, x, 14 + (x - 11) // 3 + bob, "s")
    add_rim(g)
    return trace_outline(g)


BUILDERS = [build_down, build_side, build_up]


# --- PNG writer (no deps) -----------------------------------------------------
def _chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def encode_png(width, height, rgba_rows):
    raw = bytearray()
    for row in rgba_rows:
        raw.append(0)  # filter type 0 (none)
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return (sig + _chunk(b"IHDR", ihdr)
            + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + _chunk(b"IEND", b""))


def build_sheet():
    grids = [[BUILDERS[r](c) for c in range(COLS)] for r in range(ROWS)]
    w, h = COLS * SIZE, ROWS * SIZE
    rows = []
    for ry in range(h):
        row = []
        r, fy = divmod(ry, SIZE)
        for rx in range(w):
            c, fx = divmod(rx, SIZE)
            row.append(PALETTE[grids[r][c][fy][fx]])
        rows.append(row)
    return w, h, rows, grids


def preview(grids):
    names = ["down", "side", "up "]
    for r in range(ROWS):
        print(f"\n=== {names[r]} ===")
        for fy in range(SIZE):
            print("   ".join("".join(grids[r][c][fy]) for c in range(COLS)))


def main():
    w, h, rows, grids = build_sheet()
    if "--preview" in sys.argv:
        preview(grids)
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.normpath(os.path.join(here, "..", "assets", "sprites", "player.png"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as fh:
        fh.write(encode_png(w, h, rows))
    print(f"wrote {out}  ({w}x{h})")


if __name__ == "__main__":
    main()
