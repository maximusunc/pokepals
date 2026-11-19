#!/usr/bin/env python3
"""Render the background-music scores in tools/music/scores/ to looping .ogg files in assets/music/.

    python3 tools/gen_music.py            # every score
    python3 tools/gen_music.py vale       # just one
    python3 tools/gen_music.py vale --wav # also keep a .wav next to the .ogg (for auditioning)

Needs numpy and ffmpeg (with libvorbis). Like the pixel art, the .ogg files are committed; edit a
score and re-run. See tools/music/README.md for the score format.
"""

import json
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "music"))

import numpy as np  # noqa: E402

from render import render, stats  # noqa: E402
from synth import SR  # noqa: E402

SCORES = ROOT / "tools" / "music" / "scores"
OUT = ROOT / "assets" / "music"
QUALITY = "3"  # Vorbis quality (~112 kbps stereo): soft synth music hides compression well


def write_wav(path, out):
    pcm = (np.clip(out.T, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main(argv):
    keep_wav = "--wav" in argv
    names = [a for a in argv if not a.startswith("--")] or sorted(p.stem for p in SCORES.glob("*.score"))
    OUT.mkdir(parents=True, exist_ok=True)
    for name in names:
        sc, out = render((SCORES / f"{name}.score").read_text())
        ogg = OUT / f"{name}.ogg"
        with tempfile.TemporaryDirectory() as tmp:
            wav = Path(tmp) / f"{name}.wav"
            write_wav(wav, out)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "libvorbis",
                            "-q:a", QUALITY, "-map_metadata", "-1", "-fflags", "+bitexact",
                            "-flags:a", "+bitexact", str(ogg)], check=True)
            if keep_wav:
                write_wav(OUT / f"{name}.wav", out)
        info = stats(sc, out)
        info["ogg_kb"] = round(ogg.stat().st_size / 1024)
        print(json.dumps({name: info}, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
