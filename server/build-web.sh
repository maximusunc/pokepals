#!/usr/bin/env bash
#
# build-web.sh — (re)build the Godot Web export that the relay serves.
#
# The server serves the browser client straight out of `priv/static/` (see
# ../docs/web-export.md). This script runs the Godot headless export of the
# "Web" preset into that directory. Because the Docker image bakes `priv/` in
# at *build* time, the intended loop is:
#
#     docker compose down
#     ./build-web.sh          # <- re-export the client (this script)
#     docker compose up -d --build
#
# i.e. export first, THEN rebuild the image so it copies the fresh export in.
#
# Godot binary: override with GODOT=/path/to/godot if it isn't on PATH as
# `godot` (e.g. a versioned `Godot_v4.6-stable_linux.x86_64`). Also needs python3.
# Extra arguments are passed to tools/packs/build_packs.py (see its --help).

set -euo pipefail

# Resolve paths relative to this script so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR"
PROJECT_DIR="$(cd "$SERVER_DIR/.." && pwd)/pokepals"
EXPORT_DIR="$SERVER_DIR/priv/static"

GODOT="${GODOT:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "error: Godot binary '$GODOT' not found on PATH." >&2
  echo "       Install Godot 4.6 (with the Web export templates), or point GODOT at it:" >&2
  echo "       GODOT=/path/to/Godot_v4.6-stable_linux.x86_64 $0" >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || { echo "error: python3 is needed (it splits the export into world packs)." >&2; exit 1; }

echo ">> Godot:   $("$GODOT" --version 2>/dev/null | head -n1)"
echo ">> Project: $PROJECT_DIR"
echo ">> Output:  $EXPORT_DIR/"

mkdir -p "$EXPORT_DIR"

# One command does the whole export: it builds each world headless to learn which art it uses, exports
# the base (index.html/.js/.wasm/.pck/...) WITHOUT the art only a single other world needs, writes that
# art as one pack per world under packs/ plus packs/manifest.json, and finally re-runs every world from
# the exported base + its packs to prove nothing went missing. It works on a scratch copy of the
# project, so the checkout gets no Godot `.import` churn. Details: docs/web-export.md ("World packs").
#   ./build-web.sh --monolithic    one big pck with everything, no packs (an emergency fallback)
#   ./build-web.sh --skip-verify   skip the final check (faster, while iterating)
python3 "$PROJECT_DIR/tools/packs/build_packs.py" --godot "$GODOT" --out "$EXPORT_DIR" "$@"

# Pre-compress the big files. `Plug.Static` (gzip: true) serves `<file>.gz` instead of `<file>` to
# browsers that send `Accept-Encoding: gzip` (all of them), with `Content-Encoding: gzip` and the
# ORIGINAL file's MIME type, so `.wasm` still streams-compiles. The uncompressed originals stay
# alongside as the fallback. -9 is slow but this runs once per build; -n drops the timestamp so
# unchanged files gzip to identical bytes (stable caching/ETags).
echo ">> Pre-compressing (gzip -9) the export for Plug.Static"
rm -f "$EXPORT_DIR"/*.gz "$EXPORT_DIR"/packs/*.gz
for f in "$EXPORT_DIR"/*.wasm "$EXPORT_DIR"/*.pck "$EXPORT_DIR"/*.js "$EXPORT_DIR"/*.html "$EXPORT_DIR"/packs/*.pck "$EXPORT_DIR"/packs/*.json; do
  [ -f "$f" ] || continue
  gzip -9 -n -k -f "$f"
  printf '   %-24s %10s -> %10s bytes\n' "$(basename "$f")" "$(wc -c <"$f" | tr -d ' ')" "$(wc -c <"$f.gz" | tr -d ' ')"
done

echo
echo ">> Web export written to $EXPORT_DIR/"
echo ">> Next: docker compose up -d --build   (bakes the new export into the image)"
