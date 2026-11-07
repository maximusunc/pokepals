#!/usr/bin/env python3
"""Split the Web export into a BASE pck plus one downloadable pack per world.

    python3 pokepals/tools/packs/build_packs.py [--out server/priv/static] [--godot /path/to/godot]
                                                [--skip-verify] [--monolithic] [--keep-work]

What it does (the design is in docs/web-export.md, "World packs"):

  1. Copies the Godot project to a scratch directory and imports it there, so the real checkout never
     gets Godot's `.import` churn.
  2. AUDITS every world: builds each one headless (tools/packs/audit_world.gd) with `godot --verbose`
     and reads off which `res://assets/` files it really loads. Measured, not guessed.
  3. PLANS the split (see plan()): whatever the base worlds (the Vale, homes) load, plus the shared
     things pinned in packs.json, stays in the base. What only one other world loads becomes that
     world's pack. What a few other worlds share becomes a shared "kit" pack they all depend on.
     Anything the audit never saw stays in the base, so a gap makes the download bigger, never a
     sprite missing.
  4. Exports the BASE with the packed files excluded (the Web preset from export_presets.cfg, so its
     settings stay the single source of truth), writes each pack with make_pack.gd, names it by its
     content hash (`packs/<id>.<hash12>.pck`, cacheable forever), and writes `packs/manifest.json`.
  5. VERIFIES the result: builds every world again from the exported base, fetching its packs with the
     game's own client code (AssetPacks) from a local stand-in server, and checks it loads exactly the
     art the source project did.

The server reads `packs/manifest.json` (Server.Packs) and tells each client, alongside a world's spec,
which packs that world needs. Needs `godot` (4.6, with the Web export templates) and Python 3.
"""
import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent  # .../pokepals (the Godot project)
REPO = PROJECT.parent
SEEDS = REPO / "server" / "priv" / "world_seeds"
HOME_TEMPLATE = REPO / "server" / "priv" / "home" / "home.json"
HOME_FIXTURE = PROJECT / "tests" / "world_fixtures" / "home.json"
CONFIG = HERE / "packs.json"
WEB_PRESET = "Web"

ANSI = re.compile(r"\x1b\[[0-9;]*m")
LOADED = re.compile(r"^Loading resource: (res://assets/\S+)\s*$", re.M)
IMPORTED_BLOB = ".godot/"  # compiled copies live under res://.godot/imported/ — never the asset itself


def log(msg=""):
    print(msg, flush=True)


def fail(msg):
    print(f"\nerror: {msg}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------------------------------
# Running Godot
# ---------------------------------------------------------------------------------------------------

class Godot:
    def __init__(self, binary):
        self.binary = binary

    def run(self, args, cwd, timeout=600, check=True, env=None):
        proc = subprocess.run(
            [self.binary, "--headless", *map(str, args)],
            cwd=cwd, capture_output=True, text=True, timeout=timeout,
            env={**os.environ, **env} if env else None,
        )
        out = ANSI.sub("", proc.stdout + proc.stderr)
        if check and proc.returncode != 0:
            fail(f"godot {' '.join(map(str, args))} exited {proc.returncode}:\n{out[-2000:]}")
        return out


# ---------------------------------------------------------------------------------------------------
# Worlds to audit
# ---------------------------------------------------------------------------------------------------

def maximal_home():
    """The home world with every quality's living things and features switched on.

    A real home is built per player from a template (server/lib/server/home_world.ex), so any one
    player's home shows only some of the template's props. The base has to hold ALL of them, so the
    audit builds the most crowded home the template allows.
    """
    spec = json.loads(HOME_FIXTURE.read_text())
    template = json.loads(HOME_TEMPLATE.read_text())
    for quality in template.get("qualities", {}).values():
        for part in ("living", "feature"):
            for key, items in (quality.get(part) or {}).items():
                if isinstance(items, list):
                    spec.setdefault(key, []).extend(items)
    for card in template.get("legacy_cards", {}).values():
        keepsake = card.get("keepsake")
        if isinstance(keepsake, dict):
            spec.setdefault("props", []).append(keepsake)
    return spec


def world_specs(scratch):
    """{slug: (spec_json_path, world_id)} for every seed world plus the home."""
    out = {}
    for seed in sorted(SEEDS.glob("*.json")):
        out[seed.stem] = (seed, f"audit-{seed.stem}")
    home = scratch / "home-max.json"
    home.write_text(json.dumps(maximal_home()))
    out["home"] = (home, "home:audit")
    return out


# ---------------------------------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------------------------------

def loaded_assets(log_text):
    return {p for p in LOADED.findall(log_text) if IMPORTED_BLOB not in p}


def audit(godot, work, specs):
    """{slug: {res:// path, ...}} — the art each world loads when built."""
    seen = {}
    for slug, (spec, world_id) in specs.items():
        out = godot.run(["--verbose", "--path", work, "--script", "res://tools/packs/audit_world.gd",
                         "--", spec, world_id], cwd=work, timeout=300)
        if "AUDIT_DONE" not in out:
            fail(f"building '{slug}' headless did not finish:\n{out[-2000:]}")
        seen[slug] = loaded_assets(out)
        log(f"  audited {slug:<12} {len(seen[slug]):>4} art files")
    return seen


# ---------------------------------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------------------------------

def companion_form_globs(work):
    """res:// globs for the animal sheets the companion can shift into (pals.json: form != false)."""
    pals = json.loads((work / "data" / "pals.json").read_text())
    return [f"res://assets/pals/{name}_*" for name, entry in pals.get("species", {}).items()
            if entry.get("form", True) is not False]


def plan(seen, config, pins):
    """Decide where every observed file lives.

    Returns (packs, world_packs):
      packs        {pack_id: {"worlds": [slug, ...], "files": [res:// path, ...]}}
      world_packs  {slug: [pack_id, ...]}   (only worlds that need any)
    """
    base_worlds = set(config["base_worlds"])
    kit_max = int(config.get("kit_max_worlds", 3))
    base_files = set().union(*(seen.get(w, set()) for w in base_worlds))
    others = {w: files for w, files in seen.items() if w not in base_worlds}

    owners = {}
    for world, files in others.items():
        for path in files:
            owners.setdefault(path, []).append(world)

    packs = {}
    for path, worlds in sorted(owners.items()):
        if path in base_files or any(fnmatch.fnmatch(path, pin) for pin in pins):
            continue
        worlds = tuple(sorted(worlds))
        if len(worlds) > kit_max:
            continue  # general-purpose art: it stays in the base
        pack_id = worlds[0] if len(worlds) == 1 else "kit-" + "-".join(worlds)
        entry = packs.setdefault(pack_id, {"worlds": list(worlds), "files": []})
        entry["files"].append(path)

    world_packs = {}
    for pack_id, entry in sorted(packs.items()):
        for world in entry["worlds"]:
            world_packs.setdefault(world, []).append(pack_id)
    return packs, world_packs


# ---------------------------------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------------------------------

def write_presets(work, excluded):
    """Replace export_presets.cfg in the scratch copy with just the Web preset, minus `excluded`."""
    text = (work / "export_presets.cfg").read_text()
    sections = re.split(r"(?m)^(?=\[preset\.\d+(?:\.options)?\]$)", text)
    index = None
    for section in sections:
        m = re.match(r"\[preset\.(\d+)\]$", section.split("\n", 1)[0])
        if m and re.search(r'(?m)^name="%s"$' % WEB_PRESET, section):
            index = m.group(1)
    if index is None:
        fail(f'no "{WEB_PRESET}" preset in export_presets.cfg')
    keep = [s for s in sections if re.match(rf"\[preset\.{index}(?:\.options)?\]$", s.split("\n", 1)[0])]
    body = "".join(keep).replace(f"[preset.{index}", "[preset.0")
    m = re.search(r'(?m)^exclude_filter="(.*)"$', body)
    existing = [p for p in (m.group(1).split(",") if m else []) if p.strip()]
    merged = ",".join(existing + sorted(excluded))
    body = re.sub(r'(?m)^exclude_filter=".*"$', lambda _: f'exclude_filter="{merged}"', body, count=1)
    (work / "export_presets.cfg").write_text(body)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build_pack(godot, work, scratch, pack_id, files, out_packs):
    listing = scratch / f"{pack_id}.list"
    listing.write_text("\n".join(files) + "\n")
    tmp = scratch / f"{pack_id}.pck"
    godot.run(["--path", work, "--script", "res://tools/packs/make_pack.gd", "--", tmp, listing], cwd=work)
    if not tmp.exists():
        fail(f"pack '{pack_id}' was not written")
    digest = sha256_of(tmp)
    final = out_packs / f"{pack_id}.{digest[:12]}.pck"
    shutil.move(str(tmp), final)
    probe = next((f for f in files if f.endswith(".png")), files[0])
    return {
        "url": f"packs/{final.name}",
        "bytes": final.stat().st_size,
        "sha256": digest,
        "probe": probe,
        "files": len(files),
    }


# ---------------------------------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------------------------------

class _PackServer(SimpleHTTPRequestHandler):
    """A stand-in for the game server's two relevant routes, so the build can run the REAL client
    download path (AssetPacks) against the files it just wrote: GET /worlds/<id>/packs and the pack
    files themselves."""

    manifest = {}

    def log_message(self, *args):
        pass

    def do_GET(self):
        m = re.fullmatch(r"/worlds/([^/]+)/packs", unquote(self.path))
        if not m:
            return super().do_GET()
        slug = m.group(1).removeprefix("audit-")
        packs = []
        for pack_id in self.manifest["worlds"].get(slug, []):
            pack = self.manifest["packs"][pack_id]
            packs.append({"id": pack_id, **{k: pack[k] for k in ("url", "bytes", "sha256", "probe")}})
        body = json.dumps({"world_id": m.group(1), "name": slug.title(), "packs": packs}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def verify(godot, out_dir, specs, seen, world_packs, manifest, scratch, pins):
    """Run every world from the EXPORTED base, fetching its packs the way a player's client does.

    Each world is built with the real AssetPacks code (ask the server which packs it needs, download,
    check the hash, mount) against a local stand-in for the server, and must then load the same art
    the source project did. Pinned files are left out of the comparison: they live in the base so
    they can't go missing, and some (the companion's animal sheets) are chosen at random each run.
    """
    empty = scratch / "empty-cwd"
    empty.mkdir(exist_ok=True)
    _PackServer.manifest = manifest
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(_PackServer, directory=str(out_dir)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base_url = f"http://127.0.0.1:{server.server_address[1]}/"
    bad = 0
    try:
        for slug, (spec, world_id) in specs.items():
            # A fresh user:// per world (so nothing is cached from the last one): XDG_DATA_HOME is where
            # a headless Godot keeps it, and it keeps the check out of the real user's data.
            env = {"XDG_DATA_HOME": str(scratch / "xdg" / slug)}
            out = godot.run(["--verbose", "--main-pack", out_dir / "index.pck",
                             "--script", "res://tools/packs/audit_world.gd", "--", spec, world_id, base_url],
                            cwd=empty, timeout=300, check=False, env=env)
            def unpinned(paths):
                return {p for p in paths if not any(fnmatch.fnmatch(p, pin) for pin in pins)}
            got = unpinned(loaded_assets(out))
            want = unpinned(seen[slug])
            needs = bool(world_packs.get(slug))
            if "AUDIT_DONE" not in out or got != want or (needs and "PACKS_OK" not in out):
                bad += 1
                log(f"  FAIL {slug}: source loaded {len(want)} art files, packed build loaded {len(got)}")
                for p in sorted(want - got)[:15]:
                    log(f"       missing: {p}")
                for p in sorted(got - want)[:5]:
                    log(f"       extra:   {p}")
                if "AUDIT_DONE" not in out or (needs and "PACKS_OK" not in out):
                    log(out[-1500:])
            else:
                how = "downloaded " + ", ".join(world_packs[slug]) if needs else "no packs needed"
                log(f"  ok   {slug:<12} {len(got):>4} art files, identical to the source build ({how})")
    finally:
        server.shutdown()
    return bad == 0


# ---------------------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(REPO / "server" / "priv" / "static"), help="where the export goes")
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="godot binary (or $GODOT)")
    ap.add_argument("--skip-verify", action="store_true", help="skip the final packed-build check")
    ap.add_argument("--monolithic", action="store_true", help="no packs: one base pck with everything")
    ap.add_argument("--keep-work", action="store_true", help="keep the scratch directory (for debugging)")
    args = ap.parse_args()

    if shutil.which(args.godot) is None and not Path(args.godot).exists():
        fail(f"Godot binary '{args.godot}' not found. Install Godot 4.6 (with the Web export templates) "
             f"or set GODOT=/path/to/godot.")
    godot = Godot(args.godot)
    config = json.loads(CONFIG.read_text())
    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    scratch = Path(tempfile.mkdtemp(prefix="kithbound-packs-"))
    work = scratch / "project"
    try:
        log(f">> Scratch copy of the project in {scratch}")
        shutil.copytree(PROJECT, work, ignore=shutil.ignore_patterns(
            ".godot", "previews", "__pycache__", "*.pck", "Kithbound*", "android", "MoltenVK*"))
        log(">> Importing assets (scratch copy)")
        godot.run(["--path", work, "--import"], cwd=work)

        packs, world_packs, seen, specs, pins = {}, {}, {}, {}, []
        if not args.monolithic:
            specs = world_specs(scratch)
            log(">> Auditing which art each world loads")
            seen = audit(godot, work, specs)
            pins = list(config.get("pin_base", [])) + companion_form_globs(work)
            packs, world_packs = plan(seen, config, pins)

        excluded = [p.replace("res://", "", 1) for entry in packs.values() for p in entry["files"]]
        write_presets(work, excluded)

        log(">> Exporting the base (Web preset, packed art excluded)")
        for stale in out_dir.glob("index*"):
            if stale.is_file():
                stale.unlink()
        godot.run(["--path", work, "--export-release", WEB_PRESET, out_dir / "index.html"], cwd=work)

        out_packs = out_dir / "packs"
        if out_packs.exists():
            shutil.rmtree(out_packs)
        out_packs.mkdir()

        manifest = {"format": 1, "packs": {}, "worlds": world_packs}
        if packs:
            log(">> Writing packs")
        for pack_id, entry in sorted(packs.items()):
            manifest["packs"][pack_id] = build_pack(godot, work, scratch, pack_id, sorted(entry["files"]), out_packs)
            manifest["packs"][pack_id]["worlds"] = entry["worlds"]
            m = manifest["packs"][pack_id]
            log(f"  {pack_id:<24} {m['files']:>4} files {m['bytes'] / 1024:>9.1f} KiB  for {', '.join(entry['worlds'])}")
        (out_packs / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

        base = out_dir / "index.pck"
        log(f">> Base pck: {base.stat().st_size / 1024:.1f} KiB   (packs total "
            f"{sum(p['bytes'] for p in manifest['packs'].values()) / 1024:.1f} KiB)")

        if packs and not args.skip_verify:
            log(">> Verifying: every world from the exported base + its packs")
            if not verify(godot, out_dir, specs, seen, world_packs, manifest, scratch, pins):
                fail("a packed world loaded different art than the source project (see above). "
                     "The export in the output directory is NOT safe to deploy.")
        log(">> Done")
    finally:
        if args.keep_work:
            log(f"(scratch kept at {scratch})")
        else:
            shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()
