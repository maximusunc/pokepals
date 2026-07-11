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
# `godot` (e.g. a versioned `Godot_v4.6-stable_linux.x86_64`).

set -euo pipefail

# Resolve paths relative to this script so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR"
PROJECT_DIR="$(cd "$SERVER_DIR/.." && pwd)/pokepals"
EXPORT_DIR="$SERVER_DIR/priv/static"
EXPORT_PATH="$EXPORT_DIR/index.html"
PRESET="Web"

GODOT="${GODOT:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "error: Godot binary '$GODOT' not found on PATH." >&2
  echo "       Install Godot 4.6 (with the Web export templates), or point GODOT at it:" >&2
  echo "       GODOT=/path/to/Godot_v4.6-stable_linux.x86_64 $0" >&2
  exit 1
fi

echo ">> Godot:   $("$GODOT" --version 2>/dev/null | head -n1)"
echo ">> Project: $PROJECT_DIR"
echo ">> Output:  $EXPORT_DIR/"

mkdir -p "$EXPORT_DIR"

# --export-release writes index.html/.js/.wasm/.pck/... into priv/static.
# --headless keeps it CI/server-friendly (no window). Run from the project
# dir so the relative export_path in export_presets.cfg resolves.
cd "$PROJECT_DIR"
"$GODOT" --headless --export-release "$PRESET" "$EXPORT_PATH"

echo
echo ">> Web export written to $EXPORT_DIR/"
echo ">> Next: docker compose up -d --build   (bakes the new export into the image)"
