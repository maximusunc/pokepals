"""Parse a hand-written .score file into a flat list of note events.

A score is plain text, written on a step grid (like the pixel maps are a pixel grid). See README.md
for the full format; in short:

    tempo 72            beats per minute
    beats 4             beats per bar
    steps 2             grid steps per beat (2 = eighth notes)
    seed  7             humanising seed (timing + velocity), so a render is reproducible

    voice pad   kind=pad      octave=4  gain=0.55 pan=0.0
    voice bass  kind=bass     octave=2  gain=0.6
    voice harp  kind=kalimba  octave=4  gain=0.5  pan=-0.3
    voice echo  kind=flute    octave=4  gain=0.2  delay=4      (delay: every note 4 grid steps late)

    [A]                                   a section; its length is its number of chord bars
    chords | Fmaj7 | Am7 | Bbmaj7 | Csus4 C |
    pad    | * - - - - - - - |            ONE bar is repeated for every bar of the section
    harp   | 1 . 3 . 2 . 4 3 |
    bell   | A4 - - C5 - - F5 - | E5 - - - C5 - A4 - | ...

    play A A B C A        the order sections are played in (the track loops back to the start)

Tokens on a part line, one per grid step:
    A4 C#5 Bb3     an absolute note
    1 2 3 4 ...    a chord tone of the bar's chord, counted up from the root in the voice's octave
                   (5 is the root an octave up, and so on); a trailing ' raises it an octave, , lowers
    *              the whole chord (pads)
    -              hold the note before
    .              rest
"""

import re

NOTE_RE = re.compile(r"^([A-Ga-g])([#b]?)(-?\d)$")
PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# Chord qualities as semitones above the root.
QUALITIES = {
    "": (0, 4, 7),
    "m": (0, 3, 7),
    "6": (0, 4, 7, 9),
    "m6": (0, 3, 7, 9),
    "7": (0, 4, 7, 10),
    "maj7": (0, 4, 7, 11),
    "m7": (0, 3, 7, 10),
    "maj9": (0, 4, 7, 11, 14),
    "m9": (0, 3, 7, 10, 14),
    "add9": (0, 4, 7, 14),
    "sus2": (0, 2, 7),
    "sus4": (0, 5, 7),
    "7sus4": (0, 5, 7, 10),
}


def note_to_midi(tok):
    m = NOTE_RE.match(tok)
    if not m:
        raise ValueError(f"not a note: {tok!r}")
    name, acc, octave = m.groups()
    pc = PC[name.upper()] + (1 if acc == "#" else -1 if acc == "b" else 0)
    return 12 * (int(octave) + 1) + pc


def parse_chord(tok):
    """'Bbmaj7' -> (root pitch class, intervals)."""
    m = re.match(r"^([A-G])([#b]?)(.*)$", tok)
    if not m or m.group(3) not in QUALITIES:
        raise ValueError(f"unknown chord: {tok!r}")
    pc = (PC[m.group(1)] + (1 if m.group(2) == "#" else -1 if m.group(2) == "b" else 0)) % 12
    return pc, QUALITIES[m.group(3)]


def chord_tone(chord, index, octave):
    """The index-th chord tone (1 = root) starting from the root in `octave`; wraps up octaves."""
    pc, ivs = chord
    i = index - 1
    return 12 * (octave + 1) + pc + ivs[i % len(ivs)] + 12 * (i // len(ivs))


def _bars(line):
    """'| a b | c d |' -> [['a','b'], ['c','d']]"""
    return [b.split() for b in line.strip().strip("|").split("|") if b.strip()]


class Score:
    def __init__(self, text):
        self.tempo = 72.0
        self.beats = 4
        self.steps = 2
        self.seed = 1
        self.voices = {}
        self.sections = {}
        self.order = []
        self.title = ""
        self._parse(text)

    @property
    def step_seconds(self):
        return 60.0 / self.tempo / self.steps

    @property
    def steps_per_bar(self):
        return self.beats * self.steps

    def _parse(self, text):
        section = None
        for raw in text.splitlines():
            # A comment is a '#' at the start of a line or after a space (so C#5 and F# are notes).
            line = re.sub(r"(^|\s)#.*$", "", raw).rstrip()
            if not line.strip():
                continue
            head, _, rest = line.strip().partition(" ")
            if head == "play":  # may come anywhere (usually last)
                self.order = rest.split()
            elif line.startswith("["):
                section = line.strip()[1:-1]
                self.sections[section] = {}
            elif section is None:
                if head == "voice":
                    name, *opts = rest.split()
                    cfg = {"name": name}
                    for o in opts:
                        k, v = o.split("=")
                        cfg[k] = v if k == "kind" else float(v)
                    self.voices[name] = cfg
                elif head == "title":
                    self.title = rest.strip()
                elif head in ("tempo",):
                    self.tempo = float(rest)
                elif head in ("beats", "steps", "seed"):
                    setattr(self, head, int(rest))
                else:
                    raise ValueError(f"unknown header line: {line!r}")
            else:
                self.sections[section][head] = _bars(rest)
        for s in self.order:
            if s not in self.sections:
                raise ValueError(f"play names unknown section {s!r}")

    def length_bars(self):
        return sum(len(self.sections[s]["chords"]) for s in self.order)

    def events(self):
        """[{voice, start (s), dur (s), midi: [..], vel}] for one pass of the whole track."""
        spb = self.steps_per_bar
        out = []
        bar0 = 0
        for name in self.order:
            sec = self.sections[name]
            chords = sec["chords"]
            n_bars = len(chords)
            for part, bars in sec.items():
                if part == "chords":
                    continue
                if part not in self.voices:
                    raise ValueError(f"[{name}] unknown voice {part!r}")
                voice = self.voices[part]
                octave = int(voice.get("octave", 4))
                if len(bars) == 1:
                    bars = bars * n_bars
                if len(bars) != n_bars:
                    raise ValueError(f"[{name}] {part}: {len(bars)} bars, chords have {n_bars}")
                held = None  # the open event a '-' extends
                for b, toks in enumerate(bars):
                    if len(toks) != spb:
                        raise ValueError(f"[{name}] {part} bar {b + 1}: {len(toks)} steps, want {spb}")
                    bar_chords = [parse_chord(c) for c in chords[b]]
                    for s, tok in enumerate(toks):
                        step = (bar0 + b) * spb + s
                        if tok == "-":
                            if held is not None:
                                held["steps"] += 1
                            continue
                        held = None
                        if tok == ".":
                            continue
                        chord = bar_chords[min(s * len(bar_chords) // spb, len(bar_chords) - 1)]
                        if tok == "*":
                            midi = [chord_tone(chord, i + 1, octave) for i in range(len(chord[1]))]
                        elif tok[0].isdigit():
                            shift = 12 * (tok.count("'") - tok.count(","))
                            midi = [chord_tone(chord, int(tok.strip("',")), octave) + shift]
                        else:
                            midi = [note_to_midi(tok)]
                        held = {"voice": part, "step": step, "steps": 1, "midi": midi,
                                "accent": s % self.steps == 0, "beat": s // self.steps}
                        out.append(held)
            bar0 += n_bars
        st = self.step_seconds
        for e in out:
            # A voice's `delay` (in grid steps) shifts all its notes later: an echo, a reflection. Notes
            # pushed past the end come round at the start (render folds the overhang onto the loop).
            e["step"] += self.voices[e["voice"]].get("delay", 0.0)
            e["start"] = e.pop("step") * st
            e["dur"] = e.pop("steps") * st
        return out
