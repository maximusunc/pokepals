#!/usr/bin/env python3
"""Generate the companion pixel-art sprite sheet — a "foxlike kit".

Unlike the player, the companion is EXPRESSIVE: its body language is the readout of a mood
sim (tail wag, ear droop/perk, bounce). So the sheet is authored as a small RIG, not one flat
strip: a directional walk-cycle BODY (no ears, no tail) plus separate EAR and TAIL pieces that
companion_sprite.gd slides around at runtime from the live mood signals. Every mood motion is
an integer translation (tail = horizontal slide, ears = vertical slide), so it stays crisp.

Layout — 128x160 sheet, 32x32 frames:
    rows 0-2 = BODY: down / side / up,   cols 0-3 = walk cycle (col 0 = idle)
    row  3   = EARS: cols 0-2 = down / side / up
    row  4   = TAIL: cols 0-2 = down / side / up
Side art faces right; left is the side column mirrored at runtime. Each rig piece is drawn at
its final in-frame position (same bottom-centre anchor as the body), so compositing is just
"blit at the same origin, plus the mood offset".

No third-party deps (PNG written with zlib + struct). --preview prints the frames as ASCII.
Run from anywhere:  python3 pokepals/tools/gen_companion_sprite.py [--preview]
"""

import os
import sys
import zlib
import struct

# --- Palette (earthy brown, echoing art.json's companion entry for continuity) ----------
TRANSPARENT = (0, 0, 0, 0)
PALETTE = {
    ".": TRANSPARENT,
    "C": (140, 102, 69, 255),   # body mid   (body  [0.55,0.40,0.27])
    "D": (105, 76, 50, 255),    # body shade (back seam, lower mass, paws)
    "L": (201, 165, 120, 255),  # rim light  (up-left edge)
    "A": (184, 143, 97, 255),   # accent: belly / muzzle (accent [0.72,0.56,0.38])
    "I": (150, 110, 96, 255),   # inner ear
    "E": (40, 34, 40, 255),     # eyes
    "N": (52, 42, 44, 255),     # nose
    "o": (38, 28, 32, 255),     # outline (auto-traced)
}
BODY = set("CDLAIEN")  # solid chars for the outline/rim passes

SIZE = 32
COLS, ROWS = 4, 5  # 4 walk frames; rows: body x3, ears, tail


# --- Tiny raster helpers ----------------------------------------------------------------
def blank():
    return [["." for _ in range(SIZE)] for _ in range(SIZE)]


def put(g, x, y, ch):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        g[y][x] = ch


def disk(g, cx, cy, r, ch):
    r2 = r * r
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r2:
                put(g, x, y, ch)


def tri_up(g, cx, y_apex, y_base, halfw, ch):
    """A filled triangle pointing up — a fox ear."""
    span = max(1, y_base - y_apex)
    for y in range(y_apex, y_base + 1):
        w = round(halfw * (y - y_apex) / span)
        for x in range(cx - w, cx + w + 1):
            put(g, x, y, ch)


def trace_outline(g):
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
    for y in range(SIZE):
        for x in range(SIZE):
            if g[y][x] in ("C", "D"):
                ux, uy = x - 1, y - 1
                up_left = "." if (ux < 0 or uy < 0) else g[uy][ux]
                if up_left == ".":
                    g[y][x] = "L"


def finish(g):
    add_rim(g)
    return trace_outline(g)


# --- BODY (no ears, no tail — those are rig pieces) --------------------------------------
def paws(g, frame, lx, rx, y=28):
    """Two little paws that alternate a step; the body's vertical bob is added in code."""
    l_up = 1 if frame == 1 else 0
    r_up = 1 if frame == 3 else 0
    l_fwd = 1 if frame == 1 else 0
    r_fwd = 1 if frame == 3 else 0
    disk(g, lx - l_fwd, y - l_up, 1.6, "D")
    disk(g, rx + r_fwd, y - r_up, 1.6, "D")


def build_body_down(frame):
    g = blank()
    paws(g, frame, 12, 20)
    disk(g, 16, 21, 7.0, "C")        # body
    disk(g, 16, 23, 3.8, "A")        # belly
    disk(g, 16, 15, 5.2, "C")        # head (face on the body, like the procedural look)
    disk(g, 16, 17, 2.2, "A")        # muzzle
    put(g, 16, 17, "N")              # nose
    put(g, 13, 14, "E")              # eyes
    put(g, 19, 14, "E")
    return finish(g)


def build_body_side(frame):
    g = blank()
    paws(g, frame, 12, 18)
    disk(g, 15, 21, 7.0, "C")        # body
    disk(g, 15, 24, 3.4, "A")        # belly
    disk(g, 19, 15, 4.6, "C")        # head, pushed toward facing (right)
    disk(g, 22, 16, 2.0, "A")        # snout
    put(g, 23, 16, "N")              # nose tip
    put(g, 20, 14, "E")              # single visible eye
    return finish(g)


def build_body_up(frame):
    g = blank()
    paws(g, frame, 12, 20)
    disk(g, 16, 21, 7.0, "C")        # back of the body
    disk(g, 16, 15, 5.2, "C")        # back of the head — no face (eyes hidden when walking away)
    for y in range(12, 27):          # darker seam down the spine
        put(g, 16, y, "D")
    return finish(g)


# --- EAR pieces (slid vertically by ear_offset at runtime) -------------------------------
def build_ears_down():
    g = blank()
    tri_up(g, 11, 4, 11, 3, "C")
    tri_up(g, 21, 4, 11, 3, "C")
    tri_up(g, 11, 7, 11, 2, "I")     # inner ear
    tri_up(g, 21, 7, 11, 2, "I")
    return finish(g)


def build_ears_side():
    g = blank()
    tri_up(g, 17, 4, 11, 3, "C")     # near ear
    tri_up(g, 21, 5, 11, 2, "C")     # far ear, a touch back
    tri_up(g, 17, 7, 11, 2, "I")
    return finish(g)


def build_ears_up():
    g = blank()
    tri_up(g, 11, 4, 11, 3, "C")     # backs of the ears — no inner colour
    tri_up(g, 21, 4, 11, 3, "C")
    tri_up(g, 11, 7, 11, 2, "D")
    tri_up(g, 21, 7, 11, 2, "D")
    return finish(g)


# --- TAIL pieces (slid horizontally to wag; body draws over the hidden part) -------------
def build_tail_down():
    g = blank()
    disk(g, 22, 25, 2.6, "C")        # a fluffy curl peeking out beside the body
    disk(g, 24, 22, 2.0, "C")
    disk(g, 24, 20, 1.5, "A")        # light tip
    return finish(g)


def build_tail_side():
    g = blank()
    disk(g, 10, 22, 3.2, "C")        # big tail sweeping out the back (left, when facing right)
    disk(g, 7, 20, 3.0, "C")
    disk(g, 5, 18, 2.4, "C")
    disk(g, 4, 16, 1.6, "A")         # light tip
    return finish(g)


def build_tail_up():
    g = blank()
    disk(g, 16, 26, 3.0, "C")        # full tail hanging down behind (most visible facing away)
    disk(g, 16, 29, 2.4, "C")
    disk(g, 16, 31, 1.5, "A")        # light tip
    return finish(g)


# row -> list of frame-builders (cols). Rig rows fill only cols 0-2 (down/side/up).
GRID = [
    [lambda c=c: build_body_down(c) for c in range(4)],
    [lambda c=c: build_body_side(c) for c in range(4)],
    [lambda c=c: build_body_up(c) for c in range(4)],
    [build_ears_down, build_ears_side, build_ears_up],
    [build_tail_down, build_tail_side, build_tail_up],
]


# --- PNG writer (no deps) ---------------------------------------------------------------
def _chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def encode_png(width, height, rgba_rows):
    raw = bytearray()
    for row in rgba_rows:
        raw.append(0)
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))
    return (b"\x89PNG\r\n\x1a\n"
            + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + _chunk(b"IEND", b""))


def build_sheet():
    # grids[row][col] -> 32x32 char grid (None where a rig row has no frame).
    grids = []
    for r in range(ROWS):
        row_cells = []
        for c in range(COLS):
            row_cells.append(GRID[r][c]() if c < len(GRID[r]) else None)
        grids.append(row_cells)
    w, h = COLS * SIZE, ROWS * SIZE
    rows = []
    for ry in range(h):
        out = []
        r, fy = divmod(ry, SIZE)
        for rx in range(w):
            c, fx = divmod(rx, SIZE)
            cell = grids[r][c]
            out.append(PALETTE["." if cell is None else cell[fy][fx]])
        rows.append(out)
    return w, h, rows, grids


def preview(grids):
    names = ["body-down", "body-side", "body-up", "ears(d/s/u)", "tail(d/s/u)"]
    for r in range(ROWS):
        print(f"\n=== {names[r]} ===")
        for fy in range(SIZE):
            cells = []
            for c in range(COLS):
                cell = grids[r][c]
                cells.append("".join(cell[fy]) if cell is not None else " " * SIZE)
            print("   ".join(cells))


def main():
    w, h, rows, grids = build_sheet()
    if "--preview" in sys.argv:
        preview(grids)
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.normpath(os.path.join(here, "..", "assets", "sprites", "companion.png"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as fh:
        fh.write(encode_png(w, h, rows))
    print(f"wrote {out}  ({w}x{h})")


if __name__ == "__main__":
    main()
