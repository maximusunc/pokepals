# Background music

Each world can have one looping track. Like the pixel art, the music is **written by hand as text
and rendered by a script**. The synth is numpy only, with no samples, so there is nothing to
license. The rendered `.ogg` files are committed.

```
python3 tools/gen_music.py            # render every score in scores/ to assets/music/<name>.ogg
python3 tools/gen_music.py vale       # just one
python3 tools/gen_music.py vale --wav # also write assets/music/vale.wav to audition (don't commit it)
```

Needs `numpy` and `ffmpeg` with libvorbis. A two-minute track renders in about 20 s. The script
prints some numbers: the length, the loudness per 10 s, and the size of the jump at the loop point.

## Files

- `scores/<world>.score`: the music, one text file per world.
- `score.py`: reads a score into note events.
- `synth.py`: the instruments (decaying sine partials) and the room reverb.
- `render.py`: places the notes, pans them, adds the room and folds the ring-out back onto the start
  so the loop has no seam.

## The score format

```
title The Vale
tempo 72          # beats per minute
beats 4           # beats per bar
steps 2           # grid steps per beat (2 = eighth notes, so 8 tokens a bar)
seed  7           # the small random timing and loudness wobble, so a render is repeatable

voice pad   kind=pad       octave=4  gain=0.50  pan=0.0   reverb=0.55
voice harp  kind=kalimba   octave=4  gain=0.38  pan=-0.25 reverb=0.35

[a1]                                   # a section; it is as long as its chords line
chords | Fmaj7 | Am7 | Bbmaj7 | Csus4 C |   # two chords in a bar split it in half
pad    | * - - - - - - - |             # ONE bar is repeated for every bar of the section
harp   | 1 . 3 . 2 . 4 3 |
bell   | A4 - - C5 - - F5 - | E5 - - - C5 - A4 - | ...

play intro a1 a2 b c a1 a2             # the order; the end loops back to the start
```

Tokens, one per grid step:

| token | meaning |
|---|---|
| `A4`, `C#5`, `Bb3` | a note |
| `1` `2` `3` `4` ... | a tone of the bar's chord, counting up from its root in the voice's octave (`5` on a four-note chord is the root an octave up). Add `'` for an octave up, `,` for an octave down. |
| `*` | the whole chord (pads). Each chord is voiced close to the one before it. |
| `-` | hold the previous note |
| `.` | rest |

Chords: a root (`C`, `F#`, `Bb`) plus one of: nothing (major), `m`, `6`, `m6`, `7`, `maj7`, `m7`,
`maj9`, `m9`, `add9`, `sus2`, `sus4`, `7sus4`.

Voice options: `kind` (below), `octave` (used by chord tones and `*`), `gain`, `pan` (-1 left to 1
right), `spread` (random pan per note), `reverb` (how much goes to the room).

## Instruments (`kind`)

| kind | sound |
|---|---|
| `pad` | a warm, slowly swelling sustained chord |
| `bass` | a round, soft low note |
| `kalimba` | a thumb-piano pluck |
| `musicbox` | a bright, ringing music-box or celesta tine |
| `chime` | a faint, glassy, faraway chime |

To give a world its own sound, add an instrument in `synth.py`. Each one is a short function that
returns one note.

## Hooking a track to a world

Put a `music` block in the world's seed spec (`server/priv/world_seeds/<world>.json`):

```json
"music": { "track": "res://assets/music/vale.ogg", "volume_db": -12 }
```

`volume_db` is the listening level in the game. Every file peaks at -1 dBFS, so this is the knob for
balancing worlds against each other. The `Music` autoload (`scripts/presentation/music_player.gd`)
crossfades between worlds. A world with no `music` block fades to quiet. The gear menu's **Music**
item turns it off or on, and the choice is saved in `user://settings.json`.

For a world other than the Vale, check after a pack build that its track went into that world's pack
(`tools/packs`), not the base.
