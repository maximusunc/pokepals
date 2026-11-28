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

## Open questions for the owner

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

Streaks, daily-login bonuses, leaderboards, or anything that punishes a skipped day. Dozewood stays slow.
