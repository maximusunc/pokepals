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


# ------------------------------------------------------------ more instruments, for the other worlds
# Every one keeps a rounded onset (no pluck snap, no click), so each world's music stays background.

def _phase(f, t, vib_depth=0.0, vib_rate=5.0, vib_delay=0.35, rng=None):
    """Running phase of a tone at f Hz with an optional gentle vibrato that eases in after vib_delay."""
    if vib_depth <= 0:
        return 2 * np.pi * f * t
    ramp = np.clip((t - vib_delay) / 0.6, 0, 1)
    off = rng.uniform(0, 6.28) if rng is not None else 0.0
    inst = f * (1.0 + vib_depth * ramp * np.sin(2 * np.pi * vib_rate * t + off))
    return 2 * np.pi * np.cumsum(inst) / SR


def _breath(n, f, rng, amount):
    """A little band of air around the note (flutes): noise, shaped round f in the frequency domain."""
    spec = np.fft.rfft(rng.standard_normal(n))
    fr = np.fft.rfftfreq(n, 1 / SR)
    spec *= np.exp(-((fr - f * 1.5) / (f * 0.9)) ** 2)
    noise = np.fft.irfft(spec, n)
    return amount * noise / (np.max(np.abs(noise)) + 1e-9)


def flute(midi, dur, vel, rng):
    """A soft wooden flute: nearly pure, a breath of air, a slow vibrato that comes in on long notes."""
    tail = 0.5
    t = _t(dur + tail)
    f = hz(midi)
    ph = _phase(f, t, 0.0045, 4.8, 0.35, rng)
    out = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    out += _breath(len(t), f, rng, 0.06)
    env = _env_adsr(len(t), 0.12, 0.3, 0.82, tail, dur)
    return 0.3 * vel * out * env


def reed(midi, dur, vel, rng):
    """A mellow reed (a small shawm or a far accordion): mostly odd harmonics, rounded onset."""
    tail = 0.45
    t = _t(dur + tail)
    f = hz(midi)
    ph = _phase(f, t, 0.003, 5.5, 0.3, rng)
    out = np.sin(ph) + 0.1 * np.sin(2 * ph) + 0.28 * np.sin(3 * ph) + 0.1 * np.sin(5 * ph) + 0.04 * np.sin(7 * ph)
    env = _env_adsr(len(t), 0.09, 0.3, 0.8, tail, dur)
    return 0.26 * vel * out * env


def strings(midi, dur, vel, rng):
    """A slow string-section swell: warmer and more alive than the pad (each voice wavers a little)."""
    tail = 3.0
    t = _t(dur + tail)
    f = hz(midi)
    out = np.zeros_like(t)
    for detune in (-0.0012, 0.0, 0.0012):
        ph = _phase(f * (1 + detune), t, 0.0035, 4.6 + rng.uniform(-0.4, 0.4), 0.2, rng)
        for k in range(1, 8):
            if f * k > 5000:
                break
            out += np.sin(k * ph + rng.uniform(0, 6.28)) / k ** 1.6
    env = _env_adsr(len(t), 2.0, 1.0, 0.85, tail, dur)
    return 0.13 * vel * out * env


def glass(midi, dur, vel, rng):
    """A glass harmonica: a pure tone that blooms slowly, with a slow shimmer from two near-unisons."""
    tail = 2.8
    t = _t(dur + tail)
    f = hz(midi)
    out = np.sin(2 * np.pi * f * t) + 0.7 * np.sin(2 * np.pi * (f + 0.9) * t + 1.0)
    out += 0.12 * np.sin(2 * np.pi * 2 * f * t)
    env = _env_adsr(len(t), 0.35, 0.6, 0.75, tail, dur)
    return 0.2 * vel * out * env


def marimba(midi, dur, vel, rng):
    """A soft-mallet wooden bar (bubbly, round): the bar's 4:1 overtone barely there."""
    f = hz(midi)
    decay = 0.9 * (440.0 / f) ** 0.3
    return 0.34 * _modal(f, [(1.0, 1.0, decay), (3.93, 0.12, decay * 0.15), (9.2, 0.02, 0.03)],
                         decay * 4, vel, 0.0, rng, attack=0.018)


def toypiano(midi, dur, vel, rng):
    """A toy piano struck gently: tines of metal, slightly out of true, warm rather than tinny."""
    f = hz(midi)
    decay = 1.2 * (523.0 / f) ** 0.35
    return 0.26 * _modal(f, [(1.0, 1.0, decay), (2.0, 0.22, decay * 0.4), (3.02, 0.06, decay * 0.25),
                             (4.21, 0.04, 0.12)], decay * 3.5, vel, 0.0, rng, attack=0.016)


def koto(midi, dur, vel, rng):
    """A plucked silk string (koto, oud): harmonic partials that die high-first, a soft-fingered onset."""
    f = hz(midi)
    decay = 1.7 * (330.0 / f) ** 0.3
    return 0.3 * _modal(f, [(1.0, 1.0, decay), (2.0, 0.32, decay * 0.5), (3.0, 0.14, decay * 0.3),
                            (4.0, 0.06, decay * 0.2), (5.0, 0.03, decay * 0.1)], decay * 4, vel, 0.0, rng,
                        attack=0.02)


def harp(midi, dur, vel, rng):
    """A harp, or a nylon-string guitar played softly: round and ringing."""
    f = hz(midi)
    decay = 2.2 * (330.0 / f) ** 0.3
    return 0.3 * _modal(f, [(1.0, 1.0, decay), (2.0, 0.22, decay * 0.5), (3.0, 0.06, decay * 0.3)],
                        decay * 4, vel, 0.0, rng, attack=0.022)


def bowl(midi, dur, vel, rng):
    """A singing bowl / temple bell, far off: long, inharmonic, with a slow beating hum."""
    f = hz(midi)
    out = _modal(f, [(1.0, 1.0, 6.0), (2.71, 0.45, 4.0), (5.15, 0.15, 2.2), (8.4, 0.04, 1.0)], 12.0, vel,
                 0.0, rng, attack=0.06)
    t = _t(12.0)
    out *= 1.0 + 0.25 * np.sin(2 * np.pi * 0.7 * t)
    return 0.16 * out


def drone(midi, dur, vel, rng):
    """A low held tone that breathes in and out: the floor under a world's music."""
    tail = 3.5
    t = _t(dur + tail)
    f = hz(midi)
    swell = 0.85 + 0.15 * np.sin(2 * np.pi * 0.07 * t + rng.uniform(0, 6.28))
    out = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t + 0.5)
           + 0.08 * np.sin(2 * np.pi * 3 * f * t)) * swell
    env = _env_adsr(len(t), 3.0, 1.0, 0.9, tail, dur)
    return 0.32 * vel * out * env


def drum(midi, dur, vel, rng):
    """A soft frame drum, hand not stick: a low round thump that sinks a little in pitch."""
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    f = hz(midi)
    inst = f * (1.0 + 0.4 * np.exp(-t / 0.03))
    out = np.sin(2 * np.pi * np.cumsum(inst) / SR) * np.exp(-t / 0.22)
    a = int(0.008 * SR)
    out[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    return 0.45 * vel * out


def _square(f, t, top=2400.0):
    """A band-limited square wave: odd harmonics only, rolled off above `top` Hz, so it is hollow and
    electronic without the harsh edge of a raw one (and nothing aliases)."""
    out = np.zeros_like(t)
    n = 1
    while f * n < 9000:
        out += (1.0 / n) / (1.0 + (f * n / top) ** 2) * np.sin(2 * np.pi * f * n * t)
        n += 2
    return out


def pulse(midi, dur, vel, rng):
    """An arcade sequencer's note (Ohmstead): a hollow square wave, short and plucked, doubled a hair
    out of tune for width, with the edge taken off."""
    tail = 0.3
    t = _t(dur + tail)
    f = hz(midi)
    out = _square(f, t) + 0.5 * _square(f * 1.004, t)
    env = _env_adsr(len(t), 0.006, 0.15, 0.26, tail, max(dur - 0.03, 0.05))
    return 0.20 * vel * out * env


def synthbass(midi, dur, vel, rng):
    """A synth bass: a saw whose top closes as the note rings, like a filter sweeping shut."""
    tail = 0.45
    t = _t(dur + tail)
    f = hz(midi)
    out = np.zeros_like(t)
    for n in range(1, 11):
        out += (1.0 / n) * np.exp(-t * (n - 1) * 2.4) * np.sin(2 * np.pi * f * n * t)
    env = _env_adsr(len(t), 0.012, 0.3, 0.6, tail, max(dur - 0.05, 0.1))
    return 0.40 * vel * out * env


def synthlead(midi, dur, vel, rng):
    """A soft synth lead: a rounded saw with a slow vibrato on held notes, eased in so it sings."""
    tail = 0.6
    t = _t(dur + tail)
    f = hz(midi)
    ph = _phase(f, t, 0.004, 5.2, 0.3, rng)
    out = np.zeros_like(t)
    for n in range(1, 8):
        if f * n > 7000:
            break
        out += (1.0 / n ** 1.4) * np.sin(n * ph)
    env = _env_adsr(len(t), 0.05, 0.3, 0.7, tail, max(dur - 0.05, 0.1))
    return 0.22 * vel * out * env


def epiano(midi, dur, vel, rng):
    """An electric piano's tine, far off and warm (Lingerlong): a round fundamental, a 2nd harmonic that
    fades first, a faint bell partial that is gone almost at once, and a slow tremolo, like an old
    instrument heard from across a sunny square."""
    f = hz(midi)
    decay = 2.8 * (330.0 / f) ** 0.35
    length = decay * 3.5
    out = _modal(f, [(1.0, 1.0, decay), (2.0, 0.28, decay * 0.35), (3.0, 0.05, decay * 0.2),
                     (7.1, 0.035, 0.07)], length, vel, 0.0, rng, attack=0.014)
    t = _t(length)
    out *= 1.0 + 0.12 * np.sin(2 * np.pi * 4.2 * t + rng.uniform(0, 6.28))
    return 0.26 * out


def haze(midi, dur, vel, rng):
    """A hazy hum of a pad (Lingerlong): five soft, dark voices each drifting in pitch at its own slow
    rate, so the chord shimmers and wavers like warm air over marble. It swells in slowly and leans
    toward a hum: the upper harmonics are rolled well off."""
    tail = 3.2
    t = _t(dur + tail)
    f = hz(midi)
    out = np.zeros_like(t)
    for i, cents in enumerate((-9.0, -4.0, 0.0, 4.5, 9.5)):
        rate = 0.09 + 0.05 * i + rng.uniform(0, 0.03)
        drift = 1.0 + (cents + 2.5 * np.sin(2 * np.pi * rate * t + rng.uniform(0, 6.28))) / 1731.0
        ph = 2 * np.pi * np.cumsum(f * drift) / SR + rng.uniform(0, 6.28)
        for k in range(1, 6):
            if f * k > 3000:
                break
            out += (1.0 / k ** 2.4) * np.sin(k * ph)
    env = _env_adsr(len(t), 2.4, 1.2, 0.85, tail, dur)
    return 0.085 * vel * out * env


def prism(midi, dur, vel, rng):
    """A crystal bar struck softly, like light catching an edge (Glintwold): a bright, pure tine with a
    near-unison twin, so it shimmers slowly as it rings, and a high glassy overtone that dies first."""
    f = hz(midi)
    decay = 2.4 * (523.0 / f) ** 0.35
    return 0.2 * _modal(f, [(1.0, 1.0, decay), (1.0035, 0.55, decay * 0.9), (3.0, 0.07, decay * 0.3),
                            (5.97, 0.03, 0.25)], decay * 3.5, vel, 0.0, rng, attack=0.012)


VOICES = {"pad": pad, "bass": bass, "kalimba": kalimba, "musicbox": musicbox, "chime": chime,
          "flute": flute, "reed": reed, "strings": strings, "glass": glass, "marimba": marimba,
          "toypiano": toypiano, "koto": koto, "harp": harp, "bowl": bowl, "drone": drone, "drum": drum,
          "pulse": pulse, "synthbass": synthbass, "synthlead": synthlead,
          "epiano": epiano, "haze": haze, "prism": prism}


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
