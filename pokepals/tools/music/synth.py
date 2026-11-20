"""Tiny additive / modal synthesiser for the game's background music (numpy only).

Every instrument is built from decaying sine partials, so there are no samples, no aliasing and
nothing to license. Each voice function returns a mono numpy array for one note; render.py places
the notes, pans them, adds the room (a convolution reverb) and loops the result seamlessly.
"""

import numpy as np

SR = 44100


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def _t(seconds):
    return np.arange(int(seconds * SR)) / SR


def _env_adsr(n, a, d, s, r, hold):
    """Attack/decay/sustain for `hold` seconds, then release; n samples total."""
    t = np.arange(n) / SR
    env = np.empty(n)
    att = t < a
    env[att] = (t[att] / a) ** 2 if a > 0 else 1.0
    dec = (t >= a) & (t < a + d)
    env[dec] = 1.0 - (1.0 - s) * ((t[dec] - a) / d)
    sus = (t >= a + d) & (t < hold)
    env[sus] = s
    rel = t >= max(hold, a + d)
    level = s if hold >= a + d else 1.0
    env[rel] = level * np.exp(-(t[rel] - max(hold, a + d)) / (r / 4.0))
    return env


def pad(midi, dur, vel, rng):
    """A warm sustained chord tone: three slightly detuned voices with a soft harmonic rolloff, a slow
    swell in and out, and a gentle drift in brightness."""
    tail = 2.6
    t = _t(dur + tail)
    f = hz(midi)
    out = np.zeros_like(t)
    for detune in (-0.07, 0.0, 0.07):          # cents-ish spread as a ratio offset in Hz
        ff = f * (1.0 + detune / 100.0 * 1.6)
        ph = rng.uniform(0, 2 * np.pi)
        for k in range(1, 9):
            if ff * k > 6000:
                break
            amp = 1.0 / k ** 1.8
            out += amp * np.sin(2 * np.pi * ff * k * t + ph * k)
    # brightness breathing: a little extra 2nd/3rd harmonic that swells slowly
    wob = 0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * t + rng.uniform(0, 6.28))
    out += 0.12 * wob * np.sin(2 * np.pi * 2 * f * t) + 0.05 * wob * np.sin(2 * np.pi * 3 * f * t)
    env = _env_adsr(len(t), 1.4, 0.8, 0.8, tail, dur)
    return 0.16 * vel * out * env


def bass(midi, dur, vel, rng):
    """Round, soft low notes: a sine with a touch of 2nd harmonic, a gentle onset."""
    tail = 1.2
    t = _t(dur + tail)
    f = hz(midi)
    out = np.sin(2 * np.pi * f * t) + 0.22 * np.sin(2 * np.pi * 2 * f * t) + 0.05 * np.sin(2 * np.pi * 3 * f * t)
    env = _env_adsr(len(t), 0.06, 0.9, 0.55, tail, max(dur - 0.1, 0.2))
    return 0.5 * vel * out * env


def _modal(f, partials, length, vel, click=0.0, rng=None, attack=0.004):
    """Sum of decaying sines: partials = [(ratio, amp, decay_seconds), ...]. `attack` is the onset
    ramp in seconds: a few ms is a pluck, a few tens of ms rounds it off into a soft touch."""
    t = _t(length)
    out = np.zeros_like(t)
    for ratio, amp, decay in partials:
        if f * ratio > 16000:
            continue
        out += amp * np.exp(-t / decay) * np.sin(2 * np.pi * f * ratio * t)
    # an eased onset so nothing ticks (and, when long enough, nothing plucks)
    n = min(len(t), int(attack * SR))
    out[:n] *= np.sin(np.linspace(0, np.pi / 2, n)) ** 2
    if click > 0 and rng is not None:
        k = int(0.006 * SR)
        noise = rng.standard_normal(k) * np.exp(-np.arange(k) / (0.0015 * SR))
        out[:k] += click * noise
    return vel * out


def kalimba(midi, dur, vel, rng):
    """A muted thumb-piano: a warm fundamental with a rounded (not plucked) onset and only a faint
    trace of the tine's inharmonic overtones, so it ripples under the music instead of ticking."""
    f = hz(midi)
    decay = 1.8 * (440.0 / f) ** 0.25
    return 0.34 * _modal(f, [(1.0, 1.0, decay), (2.0, 0.06, decay * 0.3),
                             (5.4, 0.03, 0.06)], decay * 4, vel, 0.0, rng, attack=0.03)


def musicbox(midi, dur, vel, rng):
    """A soft celesta tine: bell-like and long-ringing, but with a rounded onset and its bright upper
    partials turned well down, so the tune floats rather than chimes."""
    f = hz(midi)
    decay = 2.6 * (523.0 / f) ** 0.4
    return 0.26 * _modal(f, [(1.0, 1.0, decay), (2.0, 0.18, decay * 0.45), (3.0, 0.03, decay * 0.2),
                             (4.07, 0.03, 0.2)], decay * 3.5, vel, 0.0, rng, attack=0.02)


def chime(midi, dur, vel, rng):
    """A distant glassy chime for high sparkles: very soft, inharmonic, long."""
    f = hz(midi)
    return 0.12 * _modal(f, [(1.0, 1.0, 3.5), (2.76, 0.3, 1.2), (5.4, 0.12, 0.5), (8.93, 0.05, 0.2)],
                         6.0, vel, 0.0, rng)


VOICES = {"pad": pad, "bass": bass, "kalimba": kalimba, "musicbox": musicbox, "chime": chime}


# ---------------------------------------------------------------------------------------------- room

def _lowpass_fft(x, cutoff):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    spec *= 1.0 / (1.0 + (freqs / cutoff) ** 2)
    return np.fft.irfft(spec, len(x))


def impulse_response(rt60=2.6, predelay=0.025, seed=3):
    """A stereo synthetic room: decorrelated noise that decays, with highs dying faster than lows
    (so it sounds like a soft, open space rather than a metal tank)."""
    rng = np.random.default_rng(seed)
    n = int((rt60 * 1.2 + predelay) * SR)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2):
        noise = rng.standard_normal(n)
        lo = _lowpass_fft(noise, 900.0)
        hi = noise - lo
        decay = lambda rt: np.exp(-6.91 * np.maximum(t - predelay, 0) / rt)
        ir = lo * decay(rt60) + 0.5 * hi * decay(rt60 * 0.45)
        ir[t < predelay] = 0
        # soften the onset of the tail
        ramp = np.clip((t - predelay) / 0.04, 0, 1)
        chans.append(ir * ramp)
    ir = np.stack(chans)
    return ir / np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))


def convolve(x, ir):
    """FFT convolution, x and ir both (2, n)."""
    n = x.shape[1] + ir.shape[1] - 1
    size = 1 << (n - 1).bit_length()
    out = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)
    return out[:, :n]
