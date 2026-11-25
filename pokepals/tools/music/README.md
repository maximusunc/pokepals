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
right), `spread` (random pan per note), `reverb` (how much goes to the room), `delay` (every note this
many grid steps late: an echo, as in Hollowsong, or a reflection, as in Stillglass).

A `#` starts a comment only at the start of a line or after a space, so `C#5` and `F#` are notes.

## Instruments (`kind`)

| kind | sound |
|---|---|
| `pad` | a warm, slowly swelling sustained chord |
| `bass` | a round, soft low note |
| `kalimba` | a muted thumb-piano with a rounded, unplucked onset |
| `musicbox` | a soft, long-ringing celesta tine |
| `chime` | a faint, glassy, faraway chime |
| `flute` | a soft wooden flute, with breath and a slow vibrato on long notes |
| `reed` | a mellow reed, like a small shawm or a far-off accordion |
| `strings` | a slow string-section swell |
| `glass` | a glass harmonica: a pure tone that blooms slowly and shimmers |
| `marimba` | a soft-mallet wooden bar, round and bubbly |
| `toypiano` | a toy piano struck gently |
| `koto` | a plucked silk string (koto, oud) with a soft-fingered onset |
| `harp` | a harp or a softly played nylon-string guitar |
| `bowl` | a singing bowl or far temple bell: long and humming |
| `drone` | a low held tone that breathes in and out |
| `drum` | a soft frame drum played by hand |

Every instrument has a rounded onset (no pluck snap, no click), so the music stays in the background.

To give a world its own sound, add an instrument in `synth.py`. Each one is a short function that
returns one note.

## The worlds' tracks

Every world has its own score, named after its seed file (`home.score` is every player's home). Each
one says at the top what it's for. They loop after 80 to 120 seconds.

| World | Key, tempo | Instruments |
|---|---|---|
| The Vale | F major, 72 | pad, kalimba, music box, chimes |
| Home | C major, 66 | pad, harp, music box |
| Riverbank | G major, 76 | pad, harp, flute, chimes |
| Bazaar | D dorian, 84 | drone, hand drum, oud, reed |
| The Ruin | A minor, 60 | drone, singing bowl, glass, chimes |
| The Maze | G major (lydian lean), 80 | pad, harp, music box |
| Nocthollow | Eb lydian, 56 | drone, pad, glass, chimes |
| Bobbledown | Bb major, 92 | two marimbas, bubble chimes |
| Clickton | C major, 100 | toy pianos, walking bass |
| Drifthallow | D lydian, 60 | sparse celesta, pad, chimes |
| Dozewood | Ab major, 3/4, 54 | strings, harp, music-box lullaby |
| Steamhollow | D minor pentatonic, 58 | koto, flute, singing bowl |
| Hollowsong | E dorian, 66 | drone, flute and its echo, low guitar |
| Underroot | C# minor, 50 | two drones, dark pad, water drips |
| Lanternfold | D minor, 72 | harp, reed |
| Stillglass | E lydian, 54 | glass and its reflection, pad |
| Ebbmere | A major, 64 | a pad that breathes like the tide, harp, flute |
| Loftreach | G lydian, 80 | flute, harp, wind chimes |
| Thimblewick | F major, 3/4, 108 | oom-pah-pah, music-box waltz |
| Farmeadow | D major, 72 | flute, guitar |
| Ohmstead | A minor, 100 | a tine sequencer and its echo, round bass, pad, glass |

## Hooking a track to a world

Put a `music` block in the world's seed spec (`server/priv/world_seeds/<world>.json`). Most seeds are
written by a generator (`tools/gen_<world>_world.py`, `tools/gen_bazaar.py`, `tools/generate_maze.py`),
so add it there too. A home's comes from the `base` of `server/priv/home/home.json`.

```json
"music": { "track": "res://assets/music/vale.ogg", "volume_db": -22 }
```

`volume_db` is the listening level in the game. `gen_music.py` brings every file to the same
loudness, **-16 LUFS** (perceived loudness, measured with ffmpeg's `ebur128`), so `volume_db` means the
same thing in every world: **-22** plays a track at about **-38 LUFS**, quiet background. For scale,
console games aim their *whole* sound (dialogue, effects and music together) at about -24 LUFS, and
handhelds at about -18. Start new worlds at -22 and nudge from there.

The `Music` autoload (`scripts/presentation/music_player.gd`) crossfades between worlds, and a world
with no `music` block fades to quiet. The gear menu's **Sound** sheet has a volume slider. Its middle
(the default) is the level the world asks for, the right end is 12 dB louder and the left end is off.
The choice is saved in `user://settings.json`.

For a world other than the Vale, check after a pack build that its track went into that world's pack
(`tools/packs`), not the base.
