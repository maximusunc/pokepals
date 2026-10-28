#!/usr/bin/env bash
#
# redeploy.sh — pull the latest code and restart the server, in one command.
#
#   ./redeploy.sh                  # deploy main
#   ./redeploy.sh some-branch      # deploy another branch (e.g. to try it before merging)
#   ./redeploy.sh --no-web         # skip re-exporting the browser client (faster)
#
# Steps, stopping at the first one that fails:
#   1. make sure the checkout has no local edits (Godot's own .import churn is reset automatically)
#   2. switch to the branch and fast-forward it from GitHub
#   3. re-export the browser client into server/priv/static (server/build-web.sh)
#   4. docker compose down, then up -d --build (the relay migrates + seeds the DB itself on boot)
#   5. wait for /health to answer "ok"
#
# Your saves are safe: it never runs `down -v`, so the Postgres volume is kept.
# Godot binary for step 3: GODOT=/path/to/godot ./redeploy.sh (defaults to `godot` on PATH).

set -euo pipefail

# Everything lives in main(), called on the last line. Bash reads a script as it runs, so pulling a
# NEW version of this very file mid-run could otherwise make it execute half-old, half-new lines;
# a function is read in full before it starts.
main() {
  local branch="main"
  local web=1
  for arg in "$@"; do
    case "$arg" in
      --no-web) web=0 ;;
      -h|--help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      -*) fail "unknown option '$arg' (try --help)" ;;
      *) branch="$arg" ;;
    esac
  done

  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$root"

  local compose
  if docker compose version >/dev/null 2>&1; then
    compose="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    compose="docker-compose"
  else
    fail "docker compose isn't available on this machine"
  fi

  step "1/5  Checking for local changes"
  # Exporting with Godot rewrites its generated .import files; those are safe to throw away.
  local churn
  churn="$(git diff --name-only HEAD -- '*.import')"
  if [ -n "$churn" ]; then
    echo "     resetting $(echo "$churn" | wc -l | tr -d ' ') Godot-generated .import file(s)"
    git checkout -- $churn
  fi
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    git status --short --untracked-files=no
    fail "the files above have local edits, so pulling could clobber them. Commit, stash ('git stash') or discard ('git checkout -- <file>') them, then rerun."
  fi

  step "2/5  Pulling '$branch' from GitHub"
  local before
  before="$(git rev-parse --short HEAD)"
  git fetch origin "$branch" || fail "couldn't fetch '$branch' — check the branch name and the network"
  if [ "$(git branch --show-current)" != "$branch" ]; then
    git checkout "$branch" 2>/dev/null || git checkout -b "$branch" --track "origin/$branch"
  fi
  git merge --ff-only "origin/$branch" || fail "'$branch' has diverged from GitHub; sort it out by hand (git status / git log)"
  local after
  after="$(git rev-parse --short HEAD)"
  if [ "$before" = "$after" ]; then
    echo "     already up to date at $after (rebuilding anyway)"
  else
    echo "     $before -> $after"
    git log --oneline "$before..$after" | sed 's/^/       /'
  fi

  if [ "$web" = 1 ]; then
    step "3/5  Re-exporting the browser client"
    ./server/build-web.sh || fail "the web export failed (see above). Rerun with --no-web to deploy without it."
  else
    step "3/5  Skipping the browser client (--no-web)"
  fi

  step "4/5  Rebuilding and restarting the server"
  cd "$root/server"
  $compose down
  $compose up -d --build || fail "docker compose couldn't start the stack (see above)"

  step "5/5  Waiting for the server to come up"
  local port="${PORT:-4000}"
  local i
  for i in $(seq 1 60); do
    if [ "$(curl -fsS "http://localhost:$port/health" 2>/dev/null)" = "ok" ]; then
      echo
      echo "✅ Server is up on :$port, running $(git -C "$root" log -1 --format='%h %s')"
      exit 0
    fi
    sleep 2
  done
  echo
  echo "Last server logs:"
  $compose logs --tail 40 relay || true
  fail "the server didn't answer /health within 2 minutes (logs above)"
}

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m❌ %s\033[0m\n' "$1" >&2; exit 1; }

main "$@"
