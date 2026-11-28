# Dozewood — Replayability (proposal, every item OPEN)

**Status:** a proposal for the owner's review. Nothing here is built or decided (CLAUDE.md: confirm in words
before building). Every item below is ⬜ Open. It extends the built Dozewood in
`home-world-and-secrets-design.md` ("Dozewood") and follows the replay loop in `usable-items-design.md`
(earn in replayable worlds, spend everywhere, never gate the core).

## Why Dozewood

Dozewood's secret is already a *companion-led* one (nap, dream, walk there together), and it already left
the right hooks lying around:

- Naps and dreams still work after the find, "as a quiet toy" (decision 10), but they pay nothing and show the
  same picture each time, so there is no reason to do them twice.
- Five landmark pictures are already baked (`dz_dream_*.png`); only the Crooked Arch is ever used. The design
  note says a later variation is "data only".
- Four nap spots, three of them in other regions, and a drowsy-by-design pace that suits a place you
  *return to* rather than finish.

The pitch: **the forest dreams something different every night, and the best dreams need company.**

## The three layers

### 1. The Nightly Dream (the reason to come back tomorrow)

Each UTC day the wood picks which landmark the companions are dreaming of, per nap spot. Same day, same
dream for everyone (like Ebbmere's tide and Ohmstead's "today's board": a pure function of the date, so
nothing is simulated or broadcast).

- The four nap spots dream **four different landmarks** on a given day, chosen from the five pictures
  (so one landmark is "resting" each day). Dream at the nearest hollow and you learn where today's
  landmark is; the Crooked Arch is one of them most days, so the secret still reads the same.
- Walk there with your companion and a small **dream-lantern** rises, as now. Taking it pays a little:
  a few coins and one **dream-mote** (a new material, see "What it pays").
- One claim per landmark per day. Five landmarks, so at most five small payouts a day, and the
  first one of the day is the easy one.
- Finding the day's landmarks is a small walk-and-recognise loop, not a chore: a player who just wants to
  doze gets the dream and the bubble and nothing is owed.
- **Never a failure:** an unclaimed dream just fades at midnight UTC. No streaks, no missed-day penalty.

**Companion as self (cheap, expressive):** the dreamer in the bubble is drawn wearing whatever animal your
companion currently wears (the `PalSprite` core already draws the companion's form), so a fox dreams
of a fox. Bond decides how clearly it dreams: a fresh companion dreams a hazy picture (more soft-edged,
a smaller bubble), a deeply bonded one a crisp one. Data in `reveal`.

### 2. Shared Dreams (the reason to come back with someone)

If two (or more) players' companions are asleep in the **same nap spot** together, they dream **one shared
dream**: a longer, richer picture, and a sixth landmark that never appears solo, the **Moon-Hollow**, a hidden
glade reached by following the shared dream. Togetherness is the long game (CLAUDE.md pillar).

- Asleep-and-near-each-other is a pure function the client can already derive from presence (position plus
  still), the way Lingerlong's `SeatLogic` seats friends with no new message. The one small gap: friends see a
  *lying-down* companion today only as a still one, so a tiny `resting` flag on the identity packet may be
  needed. Flagged as the one wire change (open question 3).
- The shared dream pays both players, more than a solo one, but still small, and only once per pair per
  day, so it rewards hanging out, not farming.
- Solo players are never locked out: the five solo landmarks are always there. The Moon-Hollow is a
  *bonus place*, a reason to ask a friend, not a gate.

### 3. Deep Night (the reason to stay a while)

A **hammock** (several already stand in the wood) lets you lie down. Resting in one for a few seconds
slides *your own* sky, on your own screen only, on to a deep-blue night: lamps brighter, motes thicker, and
the **night garden** comes out: moon-flowers that only open after dark.

- Each day (same UTC seed) **four of twelve** night flowers are open, scattered round the wood. Pressing one
  (examine) adds it to your **Dream-book**, a per-player collection like the journal. Twelve flowers, four
  a day, so completing the book takes many visits without ever being a chore.
- Your companion curls up beside the hammock, using the existing `set_resting`.
- Collection is its own reward (a journal page and a keepsake at the twelfth); a flower also pays one
  dream-mote. Waking (or walking off) returns your sky to dusk.
- Opt-in: you never need the night for the secret. It is a second, slower way of being in the same place.

## What it pays (and how it plugs into the item loop)

- **Dream-mote** (new material, id TBD): one from a dream-lantern or a night flower, two from a shared dream.
  Small coins alongside.
- Uses, so it is not a dead currency (per `usable-items-design.md` U-2): the tinker could craft a
  **night-light** (a small glow carried with you, a cousin of the lantern) from motes plus a firefly, and motes
  trade between players. Whether motes feed that, or something else, is an open question.
- **Guard-rail:** nothing here is required to visit, to find the secret, or to be with your companion.

## How it would be built (so the cost is visible)

Same patterns as shipped worlds; no new engine ideas.

| Piece | Pattern it copies | Note |
|---|---|---|
| `DreamAlmanac` (pure, `scripts/world`) + `Server.DreamAlmanac` twin | `TideClock` / `Server.Tide`, same test vectors | Day number -> which landmark each spot dreams, which four flowers are open |
| Daily claim `dream_claim` in the channel | `circuit` / `hunt_complete` payout, ledgered through `Economy` | Server checks "this world, standing at it" and one claim per landmark per UTC day (a small `dream_claims` table) |
| Spot dream picture from the almanac | `DozeDirector` already shows a picture per spot | Data change in the spec: `reveal.landmarks[]` instead of one |
| Night garden + Dream-book | `Server.Harvest` pickups; journal page | Flowers as props shown by the day's seed; book is a per-player list |
| Hammock rest, local night sky | `SeatLogic` + `PlazaGround`'s per-viewer sky turn | Personal and display-only |
| Shared dream | presence positions; maybe one `resting` flag | The one wire-format question |

**Performance (CLAUDE.md discipline 3):** the day's picks are computed once on join and on the UTC rollover,
never per frame; night-flower props are a short static list; the night sky is a single colour/uniform
change. No new per-frame cost in the web build.

## Second pass: less drowsy (owner feedback: "maybe too cozy")

The owner asked for **opt-in challenge**, **surprise and mystery**, and **more to actually do**. The
layers above stay as the calm base. This pass adds a deeper, stranger side you can choose to go down.
The pillar still holds ("cozy by default, challenge by choice"): the only "fail" is *waking up*, which
costs nothing, and the surface of Dozewood stays as sleepy as ever. All of it is ⬜ Open.

### 4. Depths: follow the dream down (opt-in challenge, something to do)

Every dream-lantern now has three depths. The surface is what layer 1 already is; the others are chosen.

- **Surface:** walk to the landmark, take the lantern (as above).
- **Deep:** instead of taking the lantern, **Follow it down.** The screen softens and you and your
  companion step into a small **dream room**: a pocket scene for that landmark, set off in an unreachable corner
  of the world (the way Lingerlong's evening terrace is, entered through the doorway with the companion
  leading). It holds one puzzle where **your companion's form matters** (the directed-and-delegated system, used
  for real: you tap to direct it, or say **Go look** and let it work out the rest).
- **Lucid:** the same room, deeper: a three-step chain, and the dream *thins* as you go (the room slowly
  fades at the edges over a minute or so).
- **Waking is never a loss.** If the dream thins out, or a Call ends it, you simply wake at the landmark.
  Nothing is lost; the lantern is still there; ask again. No timers that punish, no health, no fail screen.

One idea per landmark, for the owner to react to (all open, none designed in detail):

| Landmark | Deep dream | What it asks of you |
|---|---|---|
| Pond with three stones | Stepping stones that sink when stood on twice | Remember a route; a **rabbit** can hop the gaps you can't |
| Lantern log | A row of lamps that hum a short phrase | Echo the phrase back by tapping the lamps (a gentle pattern game, with the world's music score) |
| Ring of toadstools | A ring that turns when something stands in it | You and your companion on opposite caps at once (two bodies, like Glintwold's facets) |
| Sleeping boulder | A boulder dreaming over a hidden door | A **bird** sees over it, a **fox** digs under it: pick the form |
| Crooked Arch | An arch whose path folds back on itself | Send your companion through first (**Go look**) and follow its light |

**Pay for depth:** Deep gives two motes; Lucid gives a rare keepsake for that landmark (a **dream-glass**, on
display at home, with a journal line). Small numbers, no ranking. A player who never goes below the surface
loses nothing.

**Honesty about the server:** as with most worlds here, the server can only check "this world, standing at the
lantern" and a per-day claim; whether you solved the puzzle runs on your screen. So payouts stay small and
capped per day, and a cheat gains a few motes at most. If a co-op depth is wanted (below), its state would go
server-side, the way the Ohmstead boards do.

### 5. Odd Nights (surprise and mystery)

About one night in six (chosen by the same UTC date seed, so everyone shares it) is an **Odd Night**. It is
never announced. You notice it, or a friend says "did you see that?". That is the point.

- **The Sleepwalker:** a vast, slow, gentle creature crosses the wood, drifting along a route set by the shared clock
  (the way Ohmstead's runners are, so everyone sees it in the same place with nothing sent). Follow it to where it stops;
  something has been left there.
- **Upside-down night:** the lamps hang from the ground, the sky pools below, and every dream picture is inverted.
  Landmarks are the same places, wrong-way-up.
- **The Wrong Dream:** your companion dreams of a place that is not there. Walk to where it points and nothing is
  there, until the next Odd Night, when something is.
- **A dream that stays:** finish a **shared** dream (layer 2) and the forest keeps a trace for about ten minutes for
  *everyone in the world*: a drifting whale of lanterns, a path of glowing steps. A reason to look up.
- **A quiet thread:** each Odd Night adds one line to the Dream-book about whose dream the wood is. Twelve lines
  in all, no deadline, and the answer lands softly (the owner decides what it is).

**Tone guard:** strange, never frightening. No jump scares, no chasing, nothing that hurts. The wood is dreaming, it
is not haunted. (Also matters if this ever has a young audience, per CLAUDE.md.)

### 6. A shared deep dream (optional, the "stakes between players" idea)

Not chosen by the owner this round, parked here: a Lucid dream that needs **two people's companions at once**
(the toadstool ring is the natural one), with shared server-side state. It is the biggest piece, so it waits.

### Build order, revised

1. Nightly Dream (layer 1): small, and makes the existing quiet toy pay.
2. **One Deep dream** as a pilot (the Crooked Arch or the boulder: the most form-driven), to find out whether a
   dream room *feels* right before making five.
3. Odd Nights, one event at a time, starting with the Sleepwalker (pure function of the clock, cheap, memorable).
4. Deep Night / Dream-book (layer 3), then Shared Dreams (layer 2), then the rest of the Deep dreams.

## Open questions for the owner

0. **Second-pass questions:** Is "the only fail is waking" far enough from cozy, or do you want real
   (still opt-in) difficulty, such as scored Lucid runs? Is the Sleepwalker the right first surprise? Is a quiet
   mystery thread (12 lines) welcome, or should Odd Nights stay purely in the moment? Which landmark should pilot a
   Deep dream?

1. **Which layers?** All three, or start with the Nightly Dream alone (smallest, and it makes the existing quiet
   toy pay)? Recommended order: 1, then 3, then 2 (the shared dream is the biggest and wants friends to
   playtest with).
2. **Payouts.** Is "a few coins and a dream-mote" the right scale, and should the mote exist at all or
   should dreams just pay coins for now?
3. **The `resting` flag** on the identity packet for shared dreams: acceptable as the one wire change?
4. **Moon-Hollow:** a real new walk-in place within Dozewood's 3200x2400, or only a picture shown in the shared
   dream bubble (a much cheaper version)?
5. **The Crooked Arch:** keep it as today's landmark most days (so the secret stays learnable), or fully
   rotate it with the others?
6. **Dream-book as its own thing** or as a section of the existing journal?
7. **Do hazy and crisp dreams (bond) stay,** or is a dream always crisp for everyone?
8. **Is the night-light craft** in scope, or park the mote's use?

## Not proposed

Streaks, daily-login bonuses, leaderboards, or anything that punishes a skipped day. The surface of Dozewood
stays slow; the strangeness and the challenge are things you go down into, not things that happen to you.
