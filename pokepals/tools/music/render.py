"""Render a parsed Score to a seamlessly looping stereo track."""

import numpy as np

from score import Score
from synth import SR, VOICES, convolve, impulse_response

TAIL_SECONDS = 10.0  # longest ring-out (pad release + reverb) folded back onto the loop's start


def _revoice(events):
    """Voice-lead the pad: place each chord's tones nearest the previous chord's, so the harmony
    glides instead of jumping between root positions."""
    prev_center = None
    for e in events:
        notes = e["midi"]
        if len(notes) < 2:
            continue
        center = prev_center if prev_center is not None else float(np.mean(notes))
        center = 0.7 * center + 0.3 * 64.0  # gently pulled back toward the middle (E4)
        placed = []
        for m in notes:
            pc = m % 12
            cands = [pc + 12 * o for o in range(3, 7)]
            placed.append(min(cands, key=lambda c: abs(c - center)))
        placed = sorted(set(placed))
        e["midi"] = placed
        prev_center = float(np.mean(placed))


def render(text):
    sc = Score(text)
    rng = np.random.default_rng(sc.seed)
    events = sc.events()
    loop_len = sc.length_bars() * sc.steps_per_bar * sc.step_seconds
    n_loop = int(round(loop_len * SR))
    n = n_loop + int(TAIL_SECONDS * SR)

    pads = sorted((e for e in events if sc.voices[e["voice"]]["kind"] == "pad"), key=lambda e: e["start"])
    _revoice(pads)

    dry = np.zeros((2, n))
    send = np.zeros((2, n))
    for e in sorted(events, key=lambda e: e["start"]):
        v = sc.voices[e["voice"]]
        kind = v["kind"]
        fn = VOICES[kind]
        vel = v.get("gain", 0.5) * (1.0 if e["accent"] else 0.82) * rng.uniform(0.88, 1.0)
        if e["beat"] == 0 and e["accent"]:
            vel *= 1.06
        start = e["start"] + (0.0 if kind == "pad" else rng.normal(0.0, 0.007))
        pan = float(np.clip(v.get("pan", 0.0) + v.get("spread", 0.0) * rng.uniform(-1, 1), -1, 1))
        gl, gr = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        sig = sum(fn(m, e["dur"], vel / np.sqrt(len(e["midi"])), rng) for m in e["midi"])
        i0 = max(0, int(start * SR))
        i1 = min(n, i0 + len(sig))
        sig = sig[: i1 - i0]
        dry[0, i0:i1] += gl * sig
        dry[1, i0:i1] += gr * sig
        wet = v.get("reverb", 0.35)
        send[0, i0:i1] += wet * gl * sig
        send[1, i0:i1] += wet * gr * sig

    room = convolve(send, impulse_response())[:, :n]
    mix = dry + 0.9 * room

    # Fold everything past the loop's end back onto its start: what rings out at the end of the track
    # is exactly what should still be ringing as it begins again, so the loop has no seam.
    out = mix[:, :n_loop].copy()
    tail = mix[:, n_loop:]
    for k in range(0, tail.shape[1], n_loop):
        chunk = tail[:, k:k + n_loop]
        out[:, : chunk.shape[1]] += chunk

    out -= out.mean(axis=1, keepdims=True)
    peak = np.max(np.abs(out))
    out *= 0.89 / peak  # -1 dBFS peak for now; gen_music.py then sets its loudness (TARGET_LUFS)
    return sc, out


def stats(sc, out):
    rms = lambda x: 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
    seam = np.max(np.abs(out[:, 0] - out[:, -1]))
    step = np.max(np.abs(np.diff(out, axis=1)))
    blocks = [rms(out[:, i:i + 10 * SR]) for i in range(0, out.shape[1], 10 * SR)]
    return {
        "title": sc.title,
        "seconds": round(out.shape[1] / SR, 2),
        "bars": sc.length_bars(),
        "rms_db": round(rms(out), 1),
        "rms_db_per_10s": [round(b, 1) for b in blocks],
        "loop_seam_jump": round(float(seam), 4),
        "largest_sample_step": round(float(step), 4),
    }
