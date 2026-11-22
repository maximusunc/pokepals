#!/usr/bin/env python3
"""Render the background-music scores in tools/music/scores/ to looping .ogg files in assets/music/.

    python3 tools/gen_music.py            # every score
    python3 tools/gen_music.py vale       # just one
    python3 tools/gen_music.py vale --wav # also keep a .wav next to the .ogg (for auditioning)

Needs numpy and ffmpeg (with libvorbis). Like the pixel art, the .ogg files are committed; edit a
score and re-run. See tools/music/README.md for the score format.
"""

import json
import re
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

# Every track file is brought to the same LOUDNESS, not just the same peak, so worlds match and a spec's
# volume_db means the same thing everywhere. LUFS is perceived loudness over the whole track (ITU-R
# BS.1770, measured here by ffmpeg's ebur128 filter). -16 LUFS is a healthy file level, the mobile
# reference; the game turns it well down (volume_db), since music is background, not the whole mix.
TARGET_LUFS = -16.0
PEAK_CEILING = 0.89  # -1 dBFS


def measure_lufs(wav):
    """Integrated loudness of a .wav, in LUFS (ffmpeg's ebur128 summary)."""
    res = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(wav), "-af", "ebur128",
                          "-f", "null", "-"], capture_output=True, text=True, check=True)
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", res.stderr)
    return float(m[-1])


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
            gain = 10 ** ((TARGET_LUFS - measure_lufs(wav)) / 20)
            if np.max(np.abs(out)) * gain > PEAK_CEILING:
                raise SystemExit(f"{name}: reaching {TARGET_LUFS} LUFS would clip; soften its loudest moments")
            out = out * gain
            write_wav(wav, out)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "libvorbis",
                            "-q:a", QUALITY, "-map_metadata", "-1", "-fflags", "+bitexact",
                            "-flags:a", "+bitexact", str(ogg)], check=True)
            if keep_wav:
                write_wav(OUT / f"{name}.wav", out)
        info = stats(sc, out)
        info["lufs"] = round(measure_lufs(ogg), 1)
        info["ogg_kb"] = round(ogg.stat().st_size / 1024)
        print(json.dumps({name: info}, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
