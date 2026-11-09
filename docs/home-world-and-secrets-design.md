# Home Worlds & World Secrets — Working Design (Action Backlog)

A living record of the **home world + world secrets** direction: the answer to "what am I
*doing* here?" Every world hides one secret; finding it adds a discovery to your own **home
world**, a personal place that shows where you've been. Friends can come and see it. As with
`docs/companion-direction-design.md`, every item is a decision the project owner makes. Nothing is
pre-approved, and nothing gets built until it's confirmed in words.

**Status legend:** ✅ Resolved (decided; ready to build or built) · 🔶 In progress · ⬜ Open /
not yet decided · 🅿️ Parked (deliberately deferred).

**Working rule (from CLAUDE.md):** never assume a decision or act before actual confirmation. If
a question doesn't reach the owner, stop and wait. No best-guessing.

---

## Why this exists (the problem it solves)

The interaction layer feels good: walking, the companion, form verbs, the Ruin, Nocthollow. But play
had no **arc**. A cozy loop needs *a reason to go out → something to bring back → a place where it
adds up visibly*. The verbs gave us the middle; this direction supplies both ends:

- **Reason to go out:** every world beyond the Vale holds one secret.
- **Where it accumulates:** your home world, which changes as you find them.
- **Why others matter:** visiting a friend's home shows you places you haven't been, and their
  discoveries hint at where to go next.

Guardrails it inherits from CLAUDE.md: cozy, online-only, **no fail states**, a place not a task.
Discoveries are the "form-unlock-style" progression CLAUDE.md allows. There is no punishing
progression.

---

## Framing decisions (settled — these anchor everything after)

- ✅ **H1 — One secret per world.** Each destination world holds exactly **one** secret. Clean,
  legible, and it maps one-to-one to one discovery in your record (your journal, see H6). No
  side-collectibles.
- ✅ **H2 — The home is a display only.** Discoveries appear in the home world when earned; the
  player **does not arrange or place** them. It is a reflection of your journey, not a decorating
  game. (Since H6/H7: what the home shows is shaped by your finds' qualities and chosen by your
  companion; still never by the player.)
- ✅ **H3 — Visits by friendship only.** You can visit a home only if its owner has accepted you as a
  **friend** (friend request) or invited you (a one-off invite, FR-3). No open/public browsing of
  homes.
- ✅ **H4 — The Gateway links to friends' homes.** The Gateway's world picker gains friends' homes as
  destinations, alongside the catalog worlds. (Your own home is presumably reachable from there too,
  see HW-5.)
- ✅ **H5 — Secrets go into existing worlds, but not the Vale.** The Vale stays the hub and the home
  of the **companion** beats (the finding, the form-verb objects); it gets **no** world secret.
  Today's destination worlds each get one: **the Ruin, Nocthollow, the Riverbank, the Maze, the
  Bazaar**. New worlds author theirs from day one.
- ✅ **H6 — The home reflects you; the journal records everything. (Decided 2026-10-31, replacing
  "one home chunk per world".)** The game should grow to an unbounded number of worlds, including
  ones players build, so the home can't hold a piece of every world and worlds must never be filed
  into a fixed set of types. So the two jobs split:
  - **The record is infinite and unboxed.** Every secret you've found is kept, with no categories:
    your **journal** (or atlas), browsable by you and your friends. A world built tomorrow fits the
    same as ours.
  - **The home is bounded and reflects who you've become by wandering**, the way the companion's
    look reflects its grown identity rather than listing everything it's done. It does this in two
    ways (both decided): **qualities** shape the home's character, and **your companion chooses the
    keepsakes** it displays (H7).
  - *Considered and set aside:* finite world types, each with a home area (filled by a "main" world,
    detailed by others). It solved size, but boxed worlds into types, which an unbounded,
    player-built catalog can't have.
- ✅ **H7 — Qualities shape the home; the companion picks the keepsakes.**
  - **Qualities:** each secret carries a few open-ended qualities, written by the world's maker
    (*glowing, watery, green, old, warm, wild, crafted, quiet…*). They describe the **find**, not the
    world, several can apply, and they **blend** rather than sort. Your home's character drifts
    toward the blend of what you've found: many glowing finds and the glade glimmers at dusk, many
    watery ones and a stream starts to wind through it. Mechanically this mirrors how the
    companion's identity already drifts.
  - **Keepsakes:** each secret yields a keepsake. The home has a **bounded** number of places for
    them, and the **companion** decides which finds live there, from its personality and the bond (a
    curious companion keeps the strangest things, a cozy one the warmest). The home literally becomes
    the two of you.
  - **Player-built worlds** author their secret, its keepsake (from a kit of parts, so it fits the
    home's art) and its qualities. They never pick a box.
- ✅ **H8 — Invitation, not lock.** No world is ever gated behind another. Any order or suggestion
  lives in what the home shows and in gentle nudges (the Gateway surfacing worlds, the companion
  perking up at them), never in where you're allowed to go. Being able to follow a friend anywhere
  always beats progression.

---

## Item backlog (all open; each awaits a decision)

Each item notes *reuse* (existing code) and *new* (to build) as information for the decision,
not as a plan to act on.

### Discoveries (the data spine)
- ✅ **S-1 — The discovery record. (Built.)** A `discoveries` table, one row per (player,
  discovery) with where it was found, behind `Server.Discoveries` (`list` / `record` → `:new` |
  `:already`). Pushed to the client on every world join as `discoveries` (before the spec), and kept
  on `Net` across hops.
- ✅ **S-2 — How a secret is authored. (Built.)** A `secret` block in the world's spec: `id`,
  `position`, `radius` (how near counts for the server's check), the `prop` it shows as, its `lore`,
  and the finding's `found_line` / `home_line`. What it becomes at home is authored separately in the
  home template (`server/priv/home/home.json` → `discoveries.<id>`), so a world and its home
  counterpart stay data-only. Client side, `SecretDirector` lays the prop out (unless already found)
  and turns an examine into a claim.
- ✅ **S-3 — Who confirms a secret is solved: the server.** Decided: same discipline as the maze's
  coin reward. The client reports "found it", and the server records the discovery **only in a world
  whose spec carries that secret** (and only once). Discoveries are visible to friends, so they stay
  honest. *Built:* `claim_secret` checks the spec's `secret.id` **and** that the player's last
  reported position (the ~20 Hz `state` stream the World process already keeps) is within the
  secret's `radius`. Answers `secret_found {id, new}` or `secret_refused`.
- ✅ **S-4 — Solving together. (Decided 2026-10-31.)**
  - **Who gets it: revealed for everyone present.** When a player solves a world's puzzle, the secret
    is revealed for everyone in the world at that moment, and **each person takes their own** by
    examining it, so everyone gets their own finding moment. (The maze already works this way: each
    player has their own seed at the heart.) Anyone arriving later can still find it themselves.
  - **"With whom" (the journal, HS-5): only friends near you.** The people recorded are those on your
    friends list who are within roughly a screen of you when you take it. Strangers never appear in
    your journal. Until friends exist (FR-1), nobody is recorded.
  - **"Found together" with your companion (HS-3): beside you when taken.** The companion is within a
    short distance of you at the moment you take it.
  - **The moment names them.** The fade-to-black card adds a soft line, e.g. "Found with Sam." It
    names the same people as the journal's "with whom" (friends near you); with nobody to name, the
    moment is unchanged.
  - *Implications for building:* at claim time the server judges and stores the `together` flag
    (companion distance, from the `c` the client already streams) and the nearby friends (from the
    world's transforms, once a friends list exists). A puzzle that "reveals" a secret needs a shared,
    per-world revealed state (like the Ruin's wards) separate from each player's own find.
- ✅ **S-5 — The moment of finding: small and warm.** Decided: no popups or fanfare. The companion
  perks up and noses the find, a gentle line plays (for the seed: "A curled seed from the oldest
  hedge… it wants to be planted somewhere of your own"), and a soft note says something changed at
  home.
  - **Revised after playtest (2026-10-31): "a little underwhelming" as a hint line.** It's now a
    whole-screen **moment**: the companion perks up, the world fades to black, the found line rises
    in white at the centre, "Something has changed at home." joins it softly a beat later, they hold,
    and the world fades back with the seed gone (it's taken while the screen is dark). About 8 s in
    all. Built as a reusable `play_moment(line, aside)` on the world controller (timings are the
    `MOMENT_*` constants), so later secrets get the same beat for free.

### The secrets themselves (one per world; authored one at a time)
Each needs its own design pass. Per P-2 in the direction doc, aim for 2–3 routes of differing
elegance, not lock-and-key. Vary the *kind* of secret so it never reads as a checklist: a puzzle, a
small game, patience, a time of day, a form only the companion can take, or just noticing.
Each world's secret is a different *kind* (decided 2026-10-31): the Maze is reaching a place, the
Ruin is solving it, Nocthollow is stillness, the Riverbank is a skill moment, and the Bazaar is
wandering. Bobbledown (W-6) is gathering: a song you complete by visiting every corner.

- ✅ **W-1 — The Ruin: the last Warden's lantern. (Built.)** Before the great door
  stands the dark lantern the last Warden kept lit, alone, until they were gone. Once the door is
  open, whether with a friend or alone with the wedge, examining it lets **you relight it
  yourself**, a small act of finishing what the last Warden couldn't, and you take it.
  - **Keepsake:** a small lit Warden's lantern. **Qualities:** old, warm.
  - *Note on S-4:* the door's open state is already shared, server-authoritative ward state, so the
    lantern becomes lightable for everyone present when it opens, and each person lights their own.
    No separate "revealed" state is needed.
- ✅ **W-2 — Nocthollow: stillness by the Mere. (Built.)** Stay still on the Mere's
  shore (the bench is the obvious spot) with your companion settled beside you for about 20
  seconds. The lily-lights drift into a slow ring and a mere-pearl rises to the shore. The bench's
  existing lore ("sit long enough and the lights drift into slow…") is already the hint.
  - **Keepsake:** a mere-light in a jar. **Qualities:** glowing, watery, quiet.
  - **Decided:** 20 seconds; moving **pauses** it and lets it drift back a little (half a second per
    second moved), so a small fidget isn't punished.
- ✅ **W-3 — The Riverbank: the elder salamander. (Built.)** Find **all ten**
  salamanders in a single hunt and an old golden elder salamander shows itself. Deliberately a real
  skill moment, as the hunt is today (15 flips, decoys among the stones). The hunt reshuffles every
  visit, so a miss only ever means "next time"; nothing is lost, so it stays clear of punishing
  fail states.
  - **Keepsake:** an elder's shed scale. **Qualities:** watery, wild.
- ✅ **W-4 — The Maze. (The first secret. Built.)** Decided: an **item waits at the centre of the maze**;
  reach the heart, take the item, and it's added to your home.
  - ✅ **The item: a hedge seed.** A curled seed from the oldest hedge. At home it grows into a small
    living **hedge spiral**, your own little maze, which hints at where it came from.
  - ✅ **Taken by examining it.** The seed rests visibly at the heart, beside the portal. You examine
    it like any object and it's yours: a small, deliberate act.
  - ✅ **Gone for you afterwards.** Once taken, your heart holds only the portal (and the coins).
    Anyone who hasn't found it still sees their own seed. Per-player, so it never runs out.
  - ✅ **Coins stay.** The existing 10-coin payout for reaching the heart is unchanged (every visit);
    the seed is a one-time discovery on top.
  *Reuse:* the maze already has a server-checked `reach_center` goal (`MazeDirector` detects
  arrival; `world_channel.ex` pays a flat 10 coins, honoured only in a world whose spec carries that
  goal), so the "you really got there" check exists. The heart also holds the portal home.
- ✅ **W-5 — The Bazaar: a packed market, and a treasure found by wandering. (Built.)**
  - **The market first.** The Bazaar is filled in as a **packed market**: stalls lining every path
    through every knot, many more NPCs (stallholders, each examinable for a line or two of lore),
    and walking traffic between them. *Watch:* performance on phones, given the extra sprites and
    walkers.
  - **Reworked into a compact souk (2026-10-31).** The sprawling market felt too big. Decided:
    **one winding covered lane plus a little square**, **always evening**, busy but walkable (about
    30 walkers, a stallholder at nearly every stall). It keeps the colour merchant's shop, the
    wet-boots man and the river-drop's alley; the old river lore is gone.
  - **No puzzle.** A small shiny treasure is tucked somewhere a little abandoned, found only by
    wandering: at the end of a **short empty alley off the west lane**, a single **glass
    river-drop** that still holds a ripple of light.
  - **Keepsake:** the glass river-drop. **Qualities:** crafted, glowing.

- ✅ **W-6 — Bobbledown: the Burbler's lullaby. (Built, 2026-11-03.)** The round world was
  breathed, not built, by the Old Burbler asleep under the Fizzwell. Its lullaby is seven notes, one
  in each of seven **chime-bubbles**, one per region (Popping Green, Gumdrop Hills, the Puffwood,
  Jellybottom, Lollipop Grove, the Bubblefield and the Pillow Dunes), each resting by that region's
  landmark (a great puff, a sign or a stone), well in from the edge of the world. Ring all seven in one visit and
  the Burbler's **first breath**, a bubble that has never popped, rises to the Fizzwell's south shore.
  - **How it's told:** the High Hush's sign and stone tell the story and name the seven. Each new
    chime reads the next line of the lullaby, so progress is felt and never counted (S-5). A rung
    chime stays lit for you, and a repeat says you've sung that part already.
  - **Mechanics:** a new reveal type, `touch_all` (`reveal.props`, `lines`, `again_line`,
    `reveal_line`). The chimes are ordinary flare props, so friends see each one ring. The server
    remembers which flare props you touched this visit and only honours the claim once every chime
    is among them (`Server.SecretReveal`). Leaving resets the song, like the hunt, and nothing is lost.
  - **Keepsake:** the first breath, in a little cream cup. **Qualities:** old, watery.

### The home world
- ✅ **HW-1 — A per-player world. (Built, owner-only for now.)** `Server.HomeWorld` builds an
  in-memory `WorldDefinition` per owner from the template + their discoveries; the channel joins it
  on `"world:home:" <> owner_user_id` (world id `"home:<owner>"`), and from there it's an ordinary
  world (spec + etag caching, its own `Server.World` process, Presence). Only the owner may join
  until FR-1..FR-5. Because the spec is regenerated, its etag changes the moment a secret is found,
  so the client re-fetches the grown home with no extra plumbing. (Homes aren't cached on disk
  client-side: small, and `:` isn't a legal filename everywhere.)
- ✅ **HW-2 — The empty home: a small glade that grows.** Decided: a snug clearing that is cozy
  even with nothing in it. Each discovery doesn't just appear, it **widens the home** (new ground, a
  new corner), so more discoveries make a bigger, richer place and a friend's home literally looks
  traveled. **Superseded in part by H6:** growth will no longer be "a chunk per discovery" (see
  HS-4); the empty glade itself stands. *Built:* the base glade (800×660) has a pond, a bench, a lantern, a mushroom ring, a log,
  a HOME signpost ("…keeping space for things you haven't found yet") and a portal back to the Vale's
  Gateway. Each discovery's authored `area` widens the bounds, and the border treeline is re-baked
  around the new size.
- 🅿️ **HW-3 — Where each discovery appears. (Superseded by H6/H7: discoveries become keepsakes the
  companion places, plus qualities; see HS-1..HS-6.)** Since the home is display-only (H2), each discovery
  has an authored place in the home. A discovery should *change the place* (a glowing pool opens, a
  carved pillar stands), not sit on a shelf. Each one quietly hints at where it came from.
  *First one built:* the hedge seed grows the glade **east** into a walkable hedge spiral, with the
  sprout (examinable) at its heart and a path leading to its entrance. The rest are authored as each
  world's secret is designed.
- 🔶 **HW-4 — The companion at home.** Does the companion relate to the discoveries (favourite spots,
  lingering by things it found with you)? Ties to companion-as-self. *Mostly answered by HS-3:* it
  naps beside its favourite keepsake and nudges keepsakes you examine.
- ✅ **HW-5 — Getting home: the Gateway, on its own tab. (Built.)** Decided: the Gateway's world picker gets a
  **separate tab** holding **your home** (and, later, friends' homes, per H4/FR-4), apart from the
  catalog worlds. No Vale portal. Leaving home returns you to the Gateway like any catalog world.

### Home scaling: qualities, keepsakes, journal (from H6/H7; all open)
- ✅ **HS-1 — The quality vocabulary. (Decided 2026-10-31.)** A **small core set** we define,
  about eight to start: *glowing, watery, green, old, warm, wild, crafted, quiet*. Makers pick from
  it; they can't invent their own, so every quality is guaranteed to look good at home. We can grow
  the set over time. Each find carries **1 to 3** qualities: enough to blend (a glowing, watery
  find), few enough that each means something.
- ✅ **HS-2 — How qualities show at home. (Decided 2026-10-31.)**
  - **What they change: all four channels.** *Light and colour* (palette, glow at dusk, warmth),
    *living things* (plants, flowers, small ambient creatures), *features* (bigger elements past a
    threshold, e.g. enough watery finds and a stream winds through the glade), and *sound* (an
    ambient soundscape; the game has almost no audio yet, so this channel is mostly future work).
  - **How they respond: proportions, gently.** The home leans toward your *mix* of qualities: a
    balanced wanderer gets a bit of everything, a night-lover's home glows. Features appear only once
    a quality is a clear part of you. Every effect is capped, so no mix can make the home garish, and
    the empty glade still stands on its own (HW-2).
  - *Open detail for authoring time:* what each of the eight qualities does in each channel, and the
    thresholds for features.
- ✅ **HS-3 — Keepsakes and the companion's choice. (Decided 2026-10-31.)**
  - **How many:** the number of keepsake spots **grows with the bond**, from 3 to about 7. The home
    reflects the two of you, so it widens as you grow closer, not as you rack up finds. Always
    bounded.
  - **How it chooses: personality + shared moments.** Each keepsake carries a small temperament
    (curiosity / energy / clinginess, the same keys and 0..1 scale as the companion's identity
    traits and the daemon form's `species_profiles`). The companion favours keepsakes whose
    temperament is nearest its **grown identity**, the same nearest-match it already uses to pick
    its signature form. Finds made **together** (the companion right beside you when it was found)
    count extra. A curious companion keeps the strange things; a snug one keeps the warm ones.
  - **Changes slowly, with a visible swap.** Choices are stable. When a new find beats a current
    favourite, the companion makes the swap itself: on your next visit home it's carrying the old
    keepsake off to the journal and settling the new one. Rare and noticeable, never churning.
  - **It reads as its own choice through behaviour, not UI.** At home it drifts to and naps beside
    its favourite keepsake and nudges a keepsake when you examine it, and each keepsake's examine
    line is written from its point of view ("it won't let anyone else near this one"). This also
    answers most of HW-4.
  - *Implications for building (not yet planned):* a find needs to remember whether the companion
    was with you (a `together` flag on the discovery, judged at claim time); each secret authors its
    keepsake's temperament; and the chosen set must be **stored** server-side, not recomputed, so
    choices stay stable and a swap is an event the home can play.
- ✅ **HS-4 — The glade grows with the keepsake spots. (Decided 2026-10-31.)** The glade widens a
  little each time the bond adds a keepsake spot (3 to about 7), so size, spots and bond move
  together. Bounded, and growth follows the relationship, not the number of worlds visited.
- ✅ **HS-5 — The journal. (Decided 2026-10-31.)**
  - **Where:** a **book on a stand in your home** that you, or a visiting friend, can examine and
    leaf through, and also **from the gear menu** anywhere.
  - **An entry shows:** the keepsake (a small picture) and its found line; **the world it came
    from**, with a way to travel there (an invitation, per H8); and **when, and with whom** (the
    date, and the friends who were there). No companion's note.
  - *Implication:* "with whom" means a find must remember who else was in the world when it was
    claimed (alongside S-4 and the HS-3 `together` flag).
- ✅ **HS-6 — The hedge spiral becomes the seed's keepsake. (Decided 2026-10-31.)** The spiral
  shrinks into a keepsake, a small potted spiral hedge, that the companion may or may not choose to
  display like any other. The per-discovery "chunk" (the eastern growth, the walkable spiral)
  retires when the keepsake system is built.

### Friends & visiting (all decided 2026-10-31)
- ✅ **FR-0 — Player names.** Players have no names today: everyone is relayed to others as
  "Friend" (`PresenceDirector._local_identity`). Decided: **generated cozy names now**, two
  friendly words (e.g. "Mossy Lantern", "Quiet Fern") the player can re-roll until they like one.
  No free text, so nothing needs moderating yet. **Free-text names come later**, only once
  moderation is in place (the CLAUDE.md child-safety note).
- ✅ **FR-1 — A friends list.** Sending, accepting and removing friends, stored server-side and keyed
  by `user_id`. It needs no accounts: like the companion and the wardrobe, it hangs off the identity
  token, so (as with everything else today) losing the device's token loses it too. Real accounts
  stay out of scope.
- ✅ **FR-2 — How a friend request starts: both ways.** **Tap a player nearby** in a shared world to
  see their name and a "Befriend" option (they get a gentle request to accept), **or** enter their
  short **friend code**, shared outside the game.
- ✅ **FR-3 — Visits: friends anytime, plus one-off invites.** Being friends is the permission:
  friends can visit your home anytime. You can also **tap a nearby non-friend and choose "Invite
  home"**. If they accept, they travel to your home with you right away, and the invite is good for
  **that one visit only**.
- ✅ **FR-4 — Friends' homes in the Gateway.** The Homes tab lists your home and each friend's. A
  friend's card shows **their name** ("Mossy Lantern's home"), **whether they're home** right now, and
  **whether they're currently playing** (online anywhere).
- ✅ **FR-5 — Visiting etiquette and safety.**
  - **Visits work while you're offline.** Your home is a place, so it's always there for friends.
  - **Your companion stays home while you're away.** Visiting friends find it napping by its
    favourite keepsake, and it greets them a little shyly. It's a stand-in drawn from your
    companion's look; your real companion is still only yours.
  - **Safety controls from the start:** **remove a friend** (quietly, they're not told); **send a
    visitor home** (back to the Gateway) while they're there; **block someone** (no more friend
    requests or invites from them, and they can't see you in the Homes tab); and **close my home**,
    a switch that pauses all visits, friends included.
  - Visiting must never be possible without consent: a friendship or a just-accepted one-off invite.

---

## Sequencing (decided)

✅ **Solo loop first.** Build **S-1 + S-2 + one secret + a bare home (HW-1/HW-2) showing that one
discovery**, then friends/visiting after. The find → see-it-at-home loop gets felt before the
social layer exists. First pair being designed: **HW-2 (the empty home) + W-4 (the Maze's heart).**

## First slice — built (2026-10-30)

Built: S-1, S-2, S-3, S-5, W-4, HW-1 (owner only), HW-2, HW-3 (hedge seed only), HW-5.

- **Server:** migration `create_discoveries`, `Server.Discovery` / `Server.Discoveries`,
  `Server.HomeWorld` + `priv/home/home.json`, and in `world_channel.ex` the home join, the
  `discoveries` push and `claim_secret`. `Worlds.directory` now ignores a non-UUID `exclude`, so
  browsing from a home can't crash. The maze seed (and its test fixture) gained the `secret` block.
- **Client:** `SecretDirector` (`scripts/presentation/mechanics`), `Net` discoveries + `claim_secret`,
  `WorldArt` `hedge_seed` / `hedge_sprout` props + `take_interactable`, `CompanionView.delight_at`,
  `WorldRouter.home_id`, and the Gateway picker's **Worlds | Homes** tabs.

**Verification:**
- **Client:** the headless suite has the same 10 failures as a clean `main` checkout, all
  pre-existing; the documented baseline of 9 has drifted by one `PathShape` test. A throwaway
  runtime harness drove the real world scene and passed every check: the seed lays out at the
  maze's heart, it's the nearest thing to examine when you stand by it, examining reads its lore,
  and a server `secret_found` takes it and plays the warm line. A taken seed stops prompting, a
  revisit leaves it out, the Homes tab shows your home, and the empty and grown homes both build.
  Screenshots were checked by eye. That pass moved the home's way-out portal out of the border
  treeline.
- **Server: its tests have not been run.** This sandbox's network policy blocks `repo.hex.pm` and
  `builds.hex.pm`, so deps and the matching Elixir/OTP couldn't be installed. Every changed file
  parses, and `HomeWorld.build_core` and `Discoveries.claimable?` were run directly in plain Elixir
  and behave as the tests expect. The DB- and channel-backed tests (`discoveries_test`,
  `home_world_test`, `home_and_secret_channel_test`) still need a `mix test` on a machine with
  deps.
- **Deploy note:** the new migration must run, and the maze's seed reaches the live game only when
  the server's seeds re-run (they do, idempotently, on container boot).

## Second slice — built (2026-10-31): friends, visiting, keepsakes, qualities, the journal

Built: FR-0..FR-5, HS-1..HS-6, S-4 (except the shared "revealed for everyone" state, see below), the
fade-to-black moment naming friends.

- **Server:** migration `create_friends_and_homes` (names + friend codes on `accounts`; `friendships`,
  `friend_requests`, `blocks`, `homes`; `together` / `with_ids` / `card` on `discoveries`).
  - `Server.Profiles`: generated names and codes.
  - `Server.Friends`: requests, accepting, quiet removal, blocks, and live events on each player's
    own `user:<id>` PubSub topic.
  - `Server.Homes` + `Server.HomePasses`: home state, who may visit, invite offers and one-visit passes.
  - `Server.Social`: the friends snapshot, an `online` Presence topic, evictions.
  - `Server.HomeWorld`, rebuilt around keepsakes + qualities; `priv/home/home.json`, regenerated.
  - In `world_channel.ex`, the server now stamps the player's name on the identity relay, and the
    channel handles the new events: `reroll_name`, `friend_*`, `block`, `invite_home` /
    `invite_answer`, `send_home`, `set_home_closed`, `set_keepsakes`, `journal`, `friends`.
  - `claim_secret` records `together` / `with` and a card.
  - The maze's secret gained `qualities` and its `keepsake`. Finds made before cards existed fall back
    to the template's `legacy_cards`, so an existing hedge seed becomes the potted hedge.
- **Client:**
  - `KeepsakeChoice` (pure, `scripts/world`, 9 tests).
  - `SocialDirector` + `HomeDirector` (`scripts/presentation/mechanics`).
  - `CozySheet` / `ChoiceCard` / `FriendsPanel` / `JournalPanel` (`scripts/presentation`).
  - Tapping another player opens their card; Friends and Journal are in the gear menu; the Gateway's
    Homes tab lists friends' homes.
  - `potted_hedge` and `journal_stand` props.
  - The `Net` messages for all of the above.
- **How it plays (owner):** on arriving home, the companion looks over your finds, settles new ones
  into empty spots, swaps one at most when a find is clearly better loved (you see it carry the old one
  off), then settles by its favourite. The choice and the bond's spots go to the server. The glade
  widens on the next visit when the bond has opened a spot.
- **How it plays (visitor):** a friend's home while they're away has their companion napping by its
  favourite keepsake. It peeks up at you, and steps aside the moment the owner arrives.
- **Not built (no consumer yet):** S-4's shared, per-world "revealed" state for puzzle secrets. The
  maze already gives each player their own seed; this lands with the first puzzle-gated secret. The
  **sound** channel of qualities (HS-2) is also still future: the game has almost no audio.
- **Verified:**
  - Server: `mix test`, 156 tests. The only failures are 4 pre-existing economy/trade tests: Postgres
    `SUM` returns a `Decimal`, which `ledger_balance` subtracts with `-`. They're unrelated to this
    work.
  - Getting there in this sandbox: hex is blocked, so the deps came from GitHub tags through a
    local-only `mix.local.exs`, with Elixir 1.16 on OTP 25, not the pinned 1.17/27.
  - Client: the Godot unit suite shows the same 10 failures as a clean `main`.
  - Runtime harness over the real world scene, all checks passing: a player card on tap, the Friends
    panel, the journal, a modal invite, the moment naming a friend, the Homes tab with friends, the
    owner's companion placing a keepsake, and a friend's resident that greets you and steps aside for
    its owner.
  - A layout check confirmed nothing sits in the border treeline at 3 or 7 spots, which moved one
    quality item.
- **Fixed along the way:** a missing home pass read as valid, because monotonic time can be negative.

## Third slice: built (2026-10-31): the four remaining secrets, and the packed Bazaar

Built: W-1, W-2, W-3 and W-5.

- **One secret mechanism, four kinds of reveal.** A secret's `reveal` block says how it becomes
  findable:
  - `always` (the default): the prop is simply there. The Maze, the Bazaar.
  - `ward_open`: the prop is there, but examining it only reads its `locked_lore` until a Ruin ward is
    open. After that, examining it lights it (`lit_line`) and claims it.
  - `stillness`: nothing shows until you've stayed still in a place with your companion settled
    beside you. `StillnessGate` (pure, `scripts/world`, 4 tests) times it, `MereLights` draws the
    lights gathering, and then the prop rises.
  - `hunt_perfect`: the prop appears when `HuntDirector` emits `hunt_won`, which needs every
    salamander found in one hunt.
- **Server:** `Server.SecretReveal` (pure, tested) checks what the server can know before honouring a
  claim: the ward really is open (`World.wards`), or this visit's `hunt_complete` reported a perfect
  hunt (kept in the socket assigns). Stillness happens on the player's screen, so the server only
  checks "this world, standing at it" for it.
- **Client:**
  - `SecretDirector` stages each kind.
  - `RuinController.is_ward_open` and the `HuntDirector.hunt_won` signal are the new hooks.
  - `WorldArt` draws the new props: `warden_lantern` (dark until lit), `mere_pearl`,
    `elder_salamander` and `river_drop`.
  - It also draws their keepsakes (`kept_lantern`, `mere_jar`, `elder_scale`, `river_drop`) and the
    `stallholder` figure.
- **The packed Bazaar** (`tools/gen_bazaar.py`): 133 stallholders minding the 166 stalls, each with a
  line from its knot's pool, and 26 walkers.
  - **Walkers** are ambient pals with a `person` appearance. The server sim walks them about, and the
    client draws each as a remote `PlayerView` dressed from the cosmetics catalog. They stay visible
    during the first-meeting search, which only hides animals.
  - **The forgotten alley** is the emptiest corner of the Glassblowers' Run, chosen by the generator
    (264 px from anything), dressed with a long-closed stall and crates, with the river-drop at its
    end.
  - The new content uses its own random stream, so **every existing stall stayed exactly where it
    was**.
- **Generators keep the secrets.** `tools/generate_maze.py` and `tools/gen_nocthollow_world.py` now
  emit their worlds' secrets, so a regenerate never drops them; the Maze's seed was at risk before.
  The Ruin and Riverbank specs are hand-authored.
- **Verified:**
  - Server: `mix test` passes in full.
  - Client: the Godot unit suite passes, and all nine smoke tests pass.
  - The server sim walks all 26 Bazaar walkers on the real seed.
  - A runtime harness over the real scene, with screenshots checked by eye:
    - **The Ruin:** the lantern stays dark and unclaimable while the door is shut, then lights and
      claims once it opens.
    - **Nocthollow:** nothing shows until you're still, the lights gather in view at the shore, then
      the pearl rises with its line.
    - **The Riverbank:** a perfect hunt brings out the elder.
    - **The Bazaar:** it has its crowd and stallholders, and the river-drop is in the alley.
    - **Home:** all five keepsakes are drawn.
  - *Not checked:* frame rate on a phone with the Bazaar's crowd (26 walkers, 133 stallholders).
- **The souk rework** (supersedes the sprawling layout above): `tools/gen_bazaar.py` now builds one
  lane from a handful of walkable rects. The entry lane turns north into a little square with a
  fountain, the colour merchant's shop and the wet-boots man. A west lane leads on to a great arch,
  and a short alley holds the river-drop.
  - **Walls:** a new spec key `walls` carries outline segments (sandstone, with lit arches on the
    lane-facing runs). They collide like hedges on both sides: the client's `Solids` and the server
    sim's `AmbientPals`, which now handles segment obstacles, so walkers stay in the lane. `roofs`
    are the terracotta rooftops over everything that isn't lane.
  - **Overhead:** `garlands` hang string lights, bunting and brass lanterns across the lane
    (`Garlands`, drawn above everyone).
  - **Always evening:** `art.daycycle.hold` pins the day cycle at dusk.
  - **Dressing:** spice stalls, rugs, warm fireflies; no meadow bushes, butterflies or clouds.
  - **Numbers:** 52 stalls, 48 stallholders, 30 walkers, 36 garlands, inside about 1800×1300 px.
  - **Verified:** `mix test`, the Godot suite and all smokes pass. A flood fill from the spawn reaches
    the secret, the arch, the shop and the wet-boots man. The server sim kept all 30 walkers inside
    the lane over 90,000 sampled positions. Screenshots were checked by eye. *Not checked:* phone
    frame rate.

## Drifthallow (pilot) — built 2026-11, every choice below OPEN for the owner's review

Drifthallow is the **pilot of the template for the next nine worlds**: a snowfield at blue hour, built
end to end (art, layout generator, secret, server, tests) so later worlds can copy the shape. The pitch
was agreed (snow, blue hour, prints that fill back in, a hare's den with a frost-flower, found by a fox
following invisible tracks). **Everything finer was decided by the builder and is listed here for
review.** Nothing below changes the pitch; if any of it is wrong, say so and it is data or a small edit.

**What it is.** `server/priv/world_seeds/drifthallow.json` (and the test fixture) from
`tools/gen_drifthallow_world.py`; art from `pokepals/tools/gen_drifthallow.py` over
`tools/pixelart/drifthallow.py`; catalog id `99999999-…`, slug `drifthallow`, listed and featured, with
the standard small portal home beside the arrival spot.

**The secret: reveal type `tracks`.** Spec shape (`secret.reveal`): `species` (fox), `start` (the scent
spot, a `hare_hollow` prop you can examine), `trail` (waypoints, the last is the den), then every number
(radii, waits, print spacing). Flow: the companion wearing the right animal near `start`, with you near
too, puts its nose down (`sniff`), then **leads** (a new command-band `GuideAction`), glancing back, along
the trail, laying bright paw-prints; if you fall further than `wait_distance` behind it **waits**, facing
you, until you are back within `resume_distance` (never a fail state). At the den the frost-flower rises
(`SecretDirector` → the usual claim). In any other shape it just plays in the snow nearby (a cue, no
trail, no prints), and the hollow's lore line points at "a fox's nose".
Code: pure `TrailGuide` (`scripts/world`, tested), presentation `TracksDirector`
(`scripts/presentation/mechanics`), `GuideAction` in `companion_actions.gd`, `guide` block in
`data/companion.json`.

**Judgment calls (all open):**
1. **How the player gets a fox.** F-1 already offers it: the companion radial lists a "Fox" entry. No new
   mechanism. Drift can also land on a fox by itself.
2. **Reused "Lead" how.** `LeadAction` is autonomous and single-target (to one liked prop), so it could
   not follow a trail. Instead a controller-driven `GuideAction` (like the Ruin's `settle`) takes a point
   plus `hold`, re-issued by the referee each frame, with Lead's glance-back. It lapses by itself 0.8 s
   after the referee stops refreshing it, and a whistle or pet cancels it, so it can never strand the
   companion. Routing round trees is the existing `NavAgent`.
3. **Keeping the fox a fox.** While guiding, the form's autonomous drift is postponed
   (`CompanionForm.postpone_drift`, 30 s each frame). If the shape is lost anyway (an instructed change),
   the lead lapses and **progress is kept**; a fox near where it stopped resumes from there.
4. **Server check stays minimal and honest** (like `stillness`): "this world, standing at the den". It
   cannot tell a walked trail from a walked-to den. Making it stronger (server-held trail progress)
   would need the client to report waypoints; left out as not cheap.
5. **Personal and display-only.** The tracks, prints and lead are local; a friend sees your fox walk but
   not the bright prints, and their own companion does not trigger yours. (Everyone's ordinary snow
   footprints do show, since those follow each puppet.)
6. **Footprints.** `GlowTrail` got a `snow` style (a soft dent with a pale lip that shallows and fades
   over `life` 28 s) and `max_prints`; the same node holds the fox's `scent` prints (90 s life, far
   longer, so you can follow the line). Config is `atmosphere.footprints`.
7. **Numbers** (all in the spec's `reveal`): scent radius 150, player radius 260, sniff 1.4 s, wait at
   190 px behind, resume at 110, let go at 720, print every 20 px, skip a waypoint it cannot make headway
   toward for 14 s; guide pace 82 px/s (the player is 118). The trail is 14 waypoints, about 1900 px,
   about 25 s of walking.
8. **Layout.** 3200×2400, eight regions (Hush Landing, South Drifts, Pine Hollow, Glasswater, Whitebole
   Wood, Rimestone Rise, North Fields, Hare's Reach), ~440 trees, ~220 props. The scent spot is at the
   edge of Whitebole Wood (about 1000 px from the arrival); the den is in Hare's Reach. No paths: the
   world is untouched, so yours are the only trails. The generator keeps a 60 px corridor round the whole
   trail clear of trees and props, and asserts it never crosses a pond.
9. **Look.** Blue-hour palette, own snow terrain + litter atlas (`dh_terrain`, `dh_details`), snow pines,
   frosted birches and oaks, ice ponds, snow shaken from branches (`ambient_life.leaves`), icy sparkles.
   Visitors are NOT re-lit (no `actor_look`): they stay as they are. No native creatures (optional; the
   hare is never seen).
10. **Keepsake and qualities.** `kept_frost_flower`: the flower in a little dish of snow, drawn by
    `WorldArt` (procedural, like the other secrets, since homes use the shared art). Qualities
    `quiet`, `old`, `watery`; temperament curious, middling energy.
11. **Lore and lines** (hollow, den, cairns, the hints at sniff, set-off, wait, lost, play, reveal and
    found) are the builder's wording.
12. **The scent spot does not use F-2 affordances** (`fox → verb`), so C-3's colour highlight does not
    mark it. An affordance spends the object on first use, which would drop the highlight; a possible
    follow-up if the spot should glow for a fox.

**Verified:** Godot suite (new `TestTrailGuide`, `TestCompanionGuide`) and every smoke except
`smoke_clickton` pass; `smoke_clickton`'s one failure ("a body at a building's wall is pushed out of it")
exists on the untouched baseline. A scratch run drove the REAL companion body: a fox led the whole
trail, waited when the player stood still and resumed, in about 29 to 38 s. Elixir: the standalone
`secret_reveal_test.exs` passes; `mix test` could not run (hex.pm is blocked in the build sandbox), so the
new channel test is unrun. *Not checked:* the world-pack build, phone frame rate, a real two-player
session, and the feel (that is the playtest).

**Playtest fixes (2026-11-08), from the owner's first play:**
- *The scent spot was hard to find.* Now the companion **notices** it, in any shape, as you come near:
  it stops and points toward the spot for 2.5 s, then cools down, with range and frequency scaling with
  bond like the Riverbank's salamander points (260 px / every 16 s fresh, 640 px / every 6 s bonded; all
  `notice_*` in `reveal`), plus a one-time `notice` hint line. Pure: `TrailGuide.notice`.
- *Switching to the fox at the spot did nothing; it just followed.* The trail only began if the companion
  itself happened to be within `scent_radius` (150 px) of the spot, which a following companion often
  isn't. A real-loop harness reproduced it. Now only YOU have to be near (`player_radius`): a fox that
  isn't on the spot goes into a new **APPROACH** phase, trots over by itself (to `sniff_reach`, 48 px, or
  as near as it can get inside `scent_radius`), then sniffs and sets off. The old smoke test missed this
  because it stood the companion on the spot by hand.

**Template checklist for the next world** (what this pilot touched): generator + art tool; seed JSON in
`server/priv/world_seeds` and the same file in `pokepals/tests/world_fixtures`; one entry in
`Server.Seeds`; the fixture name in `TestWorldPortals.FIXTURES`; a smoke test; a world-specific
`WorldArt` arm only if the secret or keepsake has no sprite; a short note in CLAUDE.md.

## Dozewood — built 2026-11, every choice below OPEN for the owner's review

Dozewood is a drowsy forest held at a long lilac dusk (3200x2400): mossy hollows, hammocks, hanging lamps of
slow pale light, round trees and willows trailing vines; everything moves at half speed (slow wind, motes,
day cycle). The pitch was agreed (a sleepy forest; a secret that is a place your companion dreams of: it
only dozes where it feels safe, dreams of a landmark, and you walk there together). **Everything finer was
decided by the builder and is listed here for review.** Catalog id `bbbbbbbb-...`, slug `dozewood`, listed
and featured, with the standard small portal home beside the arrival spot. Layout and lore:
`tools/gen_dozewood_world.py`; art: `pokepals/tools/gen_dozewood.py` over `tools/pixelart/dozewood.py`.

**The secret: reveal type `dream`.** Code: pure `DreamGate` (`scripts/world`, 16 tests), presentation
`DozeDirector` (`scripts/presentation/mechanics`) + `DreamBubble`, plus small hooks on `CompanionView`
(`set_resting`, `mood_snapshot`, a `reacted` signal). Spec shape (`secret.reveal`): `spots` (nap spots),
`landmark_position`, `picture`, every number, `lines`.

**Judgment calls (all open):**
1. **What "safe" means (all must hold, all data in `reveal`).** The companion is inside a nap spot (120 px)
   with you within 150 px of it and within 100 px of the companion; you have petted it and it *welcomed* the
   pet within the last 40 s (its own "love" reaction while petting, so a shy, rebuffed pet does not count);
   you are still (under 12 px/s); its mood is calm (arousal at most 0.40, valence at least -0.05).
2. **Bond shapes speed.** A drowse meter fills in 16 s for a fresh companion down to 5 s for a fully bonded
   one. Bond also already decides whether a pet is welcomed (25% to 100%), so a fresh companion needs a few
   tries: a gamble, as petting a stranger already is.
3. **Never a failure.** Missing conditions drain the meter slowly (0.12/s); a drowsy companion that is
   let alone gets back up. At 0.30 it stops and lies down, at 0.55 it yawns, at 1.0 it sleeps; 2.5 s later the
   dream begins.
4. **The pose.** Lying down is `CompanionView.set_resting`: the body is held still (the brain keeps thinking,
   it just isn't obeyed), squashed low, slowly breathing, a touch dimmed. No new sprite. (HomeDirector's
   nap is only a visibility swap, so there was no sleeping pose to reuse.) Personal and display-only: friends
   see it lie still, but not the pose or bubble.
5. **Waking.** Walking more than 170 px away or a Call wakes it (a pet no longer does: see the playtest fix below) (detected from the brain's behaviour
   "pet"/"come", 1.3 s grace after it falls asleep). It then needs a fresh welcomed pet and a 6 s rest before
   it can doze again. A Call while only drowsy lets the drowse go.
6. **The dreamed landmark is fixed and authored: the Crooked Arch**, not varied per visit. Reason: the
   server checks "this world, standing at the secret's position", so the position has to be fixed anyway,
   and a fixed picture is something to learn and recognise. Four other distinctive landmarks (a pond with
   three stones, a lantern log, a ring of toadstools, a sleeping boulder) and three great trees make the
   picture something to *recognise*, not just a direction. Pictures for all five are baked
   (`dz_dream_*.png`), so a later variation is data only.
7. **Finding it.** The prop does not show until the companion has dreamed (this visit), then you and it,
   awake, are within 150 px / 190 px of the arch. Then a paper **dream-lantern** rises; examining it claims
   through the usual flow. The dream is remembered for the visit even if you wake it.
8. **The dream picture** is a baked 56x56 round vignette (the landmark's own sprite on a moss hill under a
   lavender sky, hazed and soft-edged), shown in a thought bubble above the companion with drifting z's.
9. **Server check stays minimal and honest** (like `stillness`, `tracks`): "this world, standing at the
   lantern". It cannot tell a dreamed arrival from a walked-in one (the nap and dream are on your screen).
10. **Afterglow.** Once found, naps and dreams still work as a quiet toy; only the prop is gone.
11. **Four nap spots**, 120 px of moss each: one near the landing (a first hollow to learn on), one in each of
    three other regions, each with its own lore line, and a hint (once) when you stand in one with your
    companion and have not petted it, or it is too wound up.
12. **Ambient yawn** (optional): stand still anywhere for 45 s and your companion yawns (hint plus a z),
    then not again for 150 s. Data in `reveal`.
13. **Look.** Dusky moss palette, own terrain + litter atlas (`dz_terrain`, `dz_details`), round/oak/willow
    trees, a still dark pond, breathing lamp lights (`prop_lights`), always-on slow motes, a slow day cycle,
    no butterflies. Visitors are not re-lit. No native creatures (optional).
14. **Keepsake and qualities.** `kept_dream_lantern` (the lantern on a cushion of moss), drawn by `WorldArt`
    like the other secrets. Qualities `quiet`, `warm`, `glowing`.
15. **Numbers and lines** (radii, times, every hint and lore line) are the builder's wording.

**Verified:** Godot unit suite (new `TestDreamGate`) and `smoke_dozewood`; a scratch run through the REAL
loop (paused scene un-paused each frame, the companion moving by itself): at a nap spot, a real Pet then
sitting still got it to settle, sleep and dream; a Pet woke it; walking away woke it; teleporting the player to
the arch had the companion follow by itself and the lantern rose. Screenshots under Xvfb checked by eye.
Elixir: the standalone `secret_reveal_test.exs` passes; `mix test` could not run (hex.pm blocked), so the
new channel test is unrun. *Not checked:* the world-pack build, phone frame rate, two players, and the feel.

**Playtest fix (2026-11-08), from the owner's first play:** a fully bonded companion was petted by a
hollow, enjoyed it, "just stood there", and never showed a dream. A real-loop harness found why: it
did fall asleep about 5 s after the pet, but the dream waits a further `dream_delay` (2.5 s), and a
player who keeps petting while waiting woke it each time (a pet counted as a poke), which also reset the
"recent pet" and started the 6 s wake cooldown. Now **only a Call (or walking away) wakes it**; a pet
while it sleeps gets a sleepy line (`pet_asleep`) and it sleeps on.

## Steamhollow — built 2026-11, every choice below OPEN for the owner's review

Steamhollow follows the Drifthallow template: **a bathhouse village lost in fog** (boardwalks, hot springs,
paper lanterns, thick drifting mist), hiding **a little bronze bell, ringing too faintly for you to hear**,
which only your companion can hear. The pitch was agreed (the fog as the defining feature, the bell, the
companion's body language as the only compass, "calm and settled" as the condition, a new reveal type).
**Everything finer was decided by the builder and is listed here for review.** Nothing below changes the
pitch; if any of it is wrong, say so and it is data or a small edit.

**What it is.** `server/priv/world_seeds/steamhollow.json` (and the test fixture) from
`tools/gen_steamhollow_world.py`; art from `pokepals/tools/gen_steamhollow.py` over
`tools/pixelart/steamhollow.py`; catalog id `aaaaaaaa-…`, slug `steamhollow`, listed and featured, with the
standard small portal home beside the arrival spot.

**The secret: reveal type `listen`.** Spec shape (`secret.reveal`): every number of the hearing (see below), a
`pocket_radius`, and four hint `lines` (hear, lost, near, close). The bell is in the world from the start (a
prop of type `bronze_bell`, drawn procedurally by `WorldArt`, with a `kept_bronze_bell` keepsake); examining it
is the ordinary claim. Code: pure `ListenGuide` (`scripts/world`, tested), presentation `ListenDirector`
(`scripts/presentation/mechanics`), `CompanionView.listen_toward`, `listen` block in `data/companion.json`.

**Judgment calls (all open):**
1. **"Settled", concretely.** The player's speed is at most 30 px/s (still or slow), the companion is within
   95 px of you and itself under 26 px/s, and the bell is within hearing. Hold it for a moment and hearing builds
   from nothing to a clear tell; stop being settled and the sound drains over 2.2 s. It is never a fail state:
   stand still and it comes back.
2. **Bond.** Hearing range 420 px (fresh) to 900 px (bonded); seconds to settle 2.4 down to 1.0; the tell is
   capped at 0.7 fresh, 1.0 bonded; the aim starts off by up to 0.62 rad (35 deg) fresh, 0.22 bonded, wobbling
   slowly side to side, and narrows to the truth as the sound clears (a small residual never goes while far
   from the bell, less with bond).
3. **Near the bell.** Inside 240 px the tell is stronger, the aim true and settling takes 45% of the time. Inside
   130 px the bell shows in the mist (fully inside 62 px) as a small warm pocket where the fog thins.
4. **The companion is asked to stand easy.** In the real loop, a companion left to itself wanders after about
   four seconds, so it never stayed settled (a scratch harness driving the real companion showed it). So when
   you stop and it is beside you in range, the director issues the existing command-band `guide` order with
   `hold` (as the Drifthallow trail's sniff does): it stands where it is, lapses 0.8 s after we stop asking, and
   a whistle or pet cancels it. It never moves the companion, and never when you are walking. Without this the
   secret would be nearly unfindable; it reads as the companion calming down because you did.
5. **Body language, per rig.** The gaze (a facing for the animal forms, whose flat sheets have no ears) turns to
   the aim point; the body perks up and holds it; the animal forms also rock a few hundredths of a radian (a
   head-cock, `tilt` on `PalSprite`); the ear-having rigs (procedural, sprite) prick their ears forward and still
   their bounce and tail. No "!" glyph, no sound arcs, nothing pointing: by design only the body shows it.
6. **Server check stays minimal and honest** (like `stillness`, `tracks`): "this world, standing at the bell".
   It cannot tell a heard bell from a stumbled-on one.
7. **Personal and display-only.** The listening is local; a friend beside you sees your companion turn but
   nothing is networked, and their companion does not trigger yours.
8. **The fog.** `MistVeil`: one shader pass over the view, under the vignette: 40 px of clear view
   (brought in from 64 after the first playtest), full density by 150 px (was 215), 93% at its thickest (far silhouettes still hint), mottled by two octaves of
   noise anchored to the world and drifting at 7,3 px/s, the edge billowing; it fades in over 2.5 s on arrival.
   Lanterns, lit doorways, your companion, friends present and the bell (when near) each thin it into a pocket (at
   most 12 at once, the nearest win), tinted warm round lamps. Cost: one cheap fragment pass, a 12-iteration
   loop and ~55 lamps scanned per frame; *phone frame rate not measured*. All of it is `atmosphere.fog`;
   `enabled: false` turns it off.
9. **Steam.** `SteamPuffs`: soft puffs rising off every spring (one column per 22 px of radius, at least two)
   and every `sh_steam_vent`, drawn above the scenery and under the mist, culled to the screen.
10. **Layout.** 3200x2400, eight regions (Lantern Landing, Kettle Row, Soak Terraces, Cedar Walk, Drying Green,
    Old Springs, Maple Bank, Stillwater Nook), ~470 trees, ~200 props, 11 boardwalk plates, 6 bathhouses, 18
    springs. The bell is in the Stillwater Nook, about 2100 px from the arrival, by a small cold spring, about
    540 px off the end of the Cedar Walk boardwalk (so a fresh companion has to be brought into the thicket, a
    bonded one hears from the boardwalk's end). The generator flood-fills the walkable ground from the spawn and
    asserts the bell, every region and every lore prop is reachable.
11. **How the player learns to listen.** Diegetically, with no marker: the arrival hint says a bell is ringing
    too softly for you; two notice boards (Kettle Row's "bellkeeper's board", and one at the Cedar Walk's end)
    say to stand still together and let the companion listen, and that it hears nothing if you hurry.
12. **Look.** Lamplit dusk held (`daycycle.hold`), damp green-grey ground, warm paper lanterns, maples red and
    gold, cedars teal; milky turquoise water. Visitors are NOT re-lit. A few always-on warm fireflies, falling
    maple leaves, no butterflies and no cloud shadows (the mist is the weather). Its own terrain/detail atlas and
    `sh_` props, trees, tiles; no shared art edited.
13. **Bathhouses.** `BathhouseView` extends `BuildingView` (so it is y-sorted, walk-behind and fades when you
    are hidden), swapping the brick windows, door and chimney for glowing paper screens, a noren curtain, a
    swaying paper lantern and a steaming stack; chosen by a spec's `"view": "bathhouse"` (a 2-line hook in
    `Scenery.add_buildings`). Footprints collide through the existing `Solids.rect_solids`.
14. **Keepsake and qualities.** `kept_bronze_bell`: the bell on a small round of wood. Qualities `quiet`, `old`,
    `crafted`; temperament curious-ish, low energy, a touch clingy.
15. **Native creatures:** skipped (optional). **Soaking:** the springs are walls like any pond; benches, stools,
    buckets and towel racks by the water carry the "soak" feel, and no new mechanic was added.
16. **Lore and lines** (the notices, the props, the four hints, the found line) are the builder's wording.

**Verified:** Godot suite (new `TestListenGuide`) and every smoke except `smoke_clickton` pass (its one known
baseline failure); the new `smoke_steamhollow` checks the re-skin, the bathhouses, the mist and steam, the bell
and the companion's gaze. A scratch run drove the REAL loop: the player stood 300 px from the bell and the
companion, left to itself, settled in about 1 s and held its gaze within a few degrees of the bell; a second
scripted walk-the-way-it-faces run (teleporting 150 px along the gaze after each listen) closed from 400 px to the
bell in about six stop-and-listen cycles (one cycle was knocked off course by collision). Screenshots under Xvfb
(opengl3) were checked by eye: the mist reads cozy, lanterns glow through it, the bell shows as a small bronze
glint. Elixir: the standalone `secret_reveal_test.exs` passes; `mix test` could not run (hex.pm blocked).
*Not checked:* phone frame rate, the world-pack build, a real two-player session, and the feel (that is the
playtest).

**Playtest fixes (2026-11-08), from the owner's first play:**
- *The fog should come in closer.* Clear view 64 → 40 px, full density 215 → 150 px (`atmosphere.fog`).
  Lanterns and lit doors still thin it into their own pockets.
- *Lanterns lit too much.* They should only hint that something is there, so you go and look: the
  lantern fog pockets shrank from 120 px to 36 (paper) and 90 to 28 (stone), a small warm glint each.
  Lit bathhouse doors went the same way: 150 px to 40.
- *Still jittery (frame rate), and lanterns and doors "popped" in as you approached.* A headless check at a
  fixed 60 fps showed the camera and companion move as smoothly here as in other worlds, and Steamhollow
  issues fewer draw calls than most; what it alone adds is the fog's full-screen shader, which weighs most
  on phones and the web. So the fog now renders SMALL (one texel per 4 world px, `atmosphere.fog.texel`)
  into a SubViewport and is stretched over the view with smooth filtering, its grid pinned to the world
  (no shimmer) and its size only ever growing (no per-frame reallocation). The popping was the shader's
  12-pocket cap: up to 20 lanterns and doors can be in view, plus your companion and friends, so the
  furthest lit only once they made the nearest 12. Static lights are now baked ONCE into a low-res light
  mask over the world (one lookup, any number, always there); only moving pockets (companion, friends, the
  bell) run in the loop, now 8.
- *The fog jittered and lagged behind the player.* The veil was screen-space: each frame it converted the
  player's position through the camera's transform, which could be a frame stale while the camera eased,
  so the clear patch trailed and jittered. Now the veil's layer follows the viewport (drawn with the
  camera's transform, like the world) and every position is in world px, updated late in the frame
  (`process_priority`), so the clear patch is placed in the same space as the player sprite. Checked in a
  windowed run: the patch's centre equals the player's position on every sampled frame while walking.

## Hollowsong — built 2026-11, every choice below OPEN for the owner's review

Hollowsong follows the Drifthallow template: **an echo canyon** (banded red cliffs, wind-carved arches, a dry riverbed
at sunset, every sound coming back as a visible ripple), hiding **a cave that answers wrong**. The pitch was agreed
(wolf-form howl on command; the canyon howls back with ripples computed from the wall geometry; one echo returns from
somewhere it shouldn't, readable by timing/colour/shape plus a first-time hint; move and howl again to triangulate; two
players find it faster, so howls are relayed; other forms cannot howl and get a cue; bond decided in data; walk up and a
crack opens; a new reveal type). **Everything finer was decided by the builder and is listed here for review.** Nothing
below changes the pitch; if any of it is wrong, say so and it is data or a small edit. Catalog id `dddddddd-...`, slug
`hollowsong`, listed and featured, with the standard small portal home beside the arrival spot.

**What it is.** `server/priv/world_seeds/hollowsong.json` (and the test fixture) from `tools/gen_hollowsong_world.py`; art
from `pokepals/tools/gen_hollowsong.py` over `tools/pixelart/hollowsong.py`.

**The secret: reveal type `echo`.** Spec shape (`secret.reveal`): `walls` (the echoing wall segments, `[x1,y1,x2,y2]`),
`cave {origin, mouth}`, every number of the howl and of the cave, and `lines` (the hints). Code: pure `EchoField` (geometry)
and `EchoGuide` (cooldown, hint events, notice, reveal) in `scripts/world` (21 tests, `test_echo.gd`); presentation
`HowlDirector` (`mechanics/`), `EchoRipples` and `CliffView`; server `Server.Howl` + two lines in `world_channel.ex`.

**Judgment calls (all open):**
1. **How the howl is asked for.** A **Howl** entry on the companion radial's inner arc, offered in every form of any world
   with an echo secret (not hidden unless wolf), because a hidden entry is undiscoverable. In wolf form it howls; in any
   other form the companion looks at the nearest wall and a hint says a wolf's voice would carry here (the cue). The arrival
   line and two notice boards (the landing's, the Choir's) also say "wolf, then Howl". Getting the wolf is F-1's existing
   Wolf radial entry; the companion's drift can also land on it. The wolf is held only for its bond-scaled hold, so a player
   re-picks it; it is never forced.
2. **What a howl does.** The companion stands still and lifts its head (the guide `hold` plus `listen_toward` skyward) for
   1.5 s, small gold arcs rise off it, a thin call ring leaves it. The ears are the player's own position, the voice the
   companion's. Cooldown 4.0 s fresh down to 2.4 s bonded; hearing a friend's howl never costs you your own cooldown.
3. **How the walls answer.** Mirror-image method: reflect the voice across each wall's line, a straight line from the image
   to your ears must cross the wall's extent, and neither leg may pass through another wall. The returning wavefront is a
   circle centred on the image, cut to the wall's ends (gold, thin, a soft body and two trailing rings), starting as the
   wall's own outline and spreading back to you, arriving at path/speed. Speed 600 px/s; strength falls with path length.
   The 28 nearest walls are considered per howl (bounds the cost).
4. **The walls are the cliffs' footprints.** Every colliding cliff (and arch leg) contributes its four edges, so the sound
   and the collision share one geometry (164 segments). One-sided in effect: you only hear a wall you could actually see.
5. **How the wrong answer reads** (all three of the pitch's cues, plus more): it is **late** (out-and-back to the cave plus a
   0.35 s "hollow" beat), **violet** where walls are gold, **thick, dark-edged and double** (a solid ring and a dashed one
   behind it) where walls are thin, it blooms softly where it is born, and on arriving it leaves a **dotted bearing line
   with a chevron** toward where it seemed to come from, lingering 16 s so a second howl can cross it. The "wrong" hint is
   said when it arrives, once. Silence (a howl nothing answers) has its own once-only line.
6. **Triangulation.** The apparent origin is the cave seen with a bearing error (seeded per howl, so it differs every time),
   at most 0.36 rad (about 21 degrees) at full range for a fresh companion, 0.09 bonded, shrinking toward 20% of that up
   close. One howl is a rough bearing; two from two places cross near the cave (a unit test does exactly that).
7. **Bond** (all data): walls' reach 1500 -> 2300 px of path; the cave hears from 1250 -> 1900 px; the wrong answer is
   0.72 -> 1.0 as clear; its bearing error 0.36 -> 0.09 rad; cooldown 4.0 -> 2.4 s; the companion notices the cave from
   300 -> 640 px and points more often (16 -> 6 s between points).
8. **Better together.** The client sends only the event; the server stamps where from its own last-known position of the
   player (no spoofing), relays `howled` to everyone else, only in a world whose secret is `echo`, at most once per 1.2 s per
   player. A friend's howl draws the same ripples fainter, including the wrong one and its bearing line, using a neutral
   bond (0.5) since bond is not relayed. Nothing is kept server-side.
9. **Generous triggers (playtest lessons).** The reveal needs only **you**, in any form, within 210 px of the cave mouth. The
   companion **notices** the cave as you come near (in any shape) and points at it for 2.5 s (the Riverbank/Drifthallow
   pattern, `EchoGuide.update`). Nothing a player naturally does (pet, call, change form, wander) resets anything: the reveal
   is monotonic and the howl has no state to break. The cave's fissure is a faint hairline from the start so it can be
   found by eye too.
10. **The cave and the stone.** The cave is a crack in the back wall of a slot in the north-east rim ("the Hush", a
    200 px wide, 320 px deep corridor between two deep cliffs). Walking within 210 px opens it (it widens over 2 s, glows
    violet, motes drift out) and the **answering stone** (a smooth red bowl with a violet light) is there on its threshold
    (placed 22 px below the cliff's foot so the cliff does not paint over it). Examining it is the ordinary claim. The
    server check stays minimal and honest ("this world, standing at the stone"); it cannot tell a found cave from a
    walked-in one. Once found, the cave stays open and howling stays a quiet toy.
11. **Cliffs.** `CliffView` extends `BuildingView`: rock-grain tile tinted in seeded strata bands, a lit/shaded edge, scree
    at the foot, fissures, a sandy top, stepped `tiers`; each fades while you stand behind it. The north rim is tall (nothing
    walkable lies behind it), the south rim low so it never hides the floor. Arches are a cliff with an `arch` opening and
    `solid_rects` for its legs (a one-line change in `Solids.build`), so you can walk under them.
12. **Layout.** 3600x2600, eight regions (Sundown Landing, Red Stair, Dry Run, Whisper Walls, the Choir, Hoodoo Flats, the
    Hush, Cottonwood Bend), 38 cliffs, 3 arches, 7 seeps, 3 great cottonwoods, ~290 trees, ~170 props. The dry riverbed is
    the existing `vein` band (a flat, sunken, cracked strip). The generator flood-fills the walkable ground from the spawn and
    asserts the stone, the slot, every region and every arch's far side is reachable. The slot, the approach and the stone are
    kept clear of trees and props.
13. **Look.** Gold sunset held (`daycycle.hold`), sun-baked ground in five moods with its own terrain/litter atlas
    (`hs_terrain`, `hs_details`), junipers, sage, cottonwoods and dry willows, slow gold leaves and dust motes, a few drifting
    cloud shadows. Visitors are NOT re-lit. No native creatures (optional, skipped).
14. **Keepsake and qualities.** `kept_echo_stone` (the bowl on a slab of sandstone), drawn by `WorldArt` like the other
    secrets. Qualities `old`, `glowing`, `wild`; temperament curious, middling energy, a touch clingy.
15. **Lore and lines** (the boards, props, the eight hints and the found line) are the builder's wording.
16. **Performance.** Ripples are drawn only where the circle can cross the screen and only the segments in view (draw calls
    follow the view, not the number of howls or friends); the occlusion test is bounded to the 28 nearest walls and runs once
    per howl; static cliffs are drawn once (only the cave's cliff animates, and only after it opens). Nothing allocates per
    frame. *Phone frame rate not measured.*

**Verified:** Godot unit suite (new `TestEcho`) and `smoke_hollowsong`; a scratch run through the REAL loop (scene un-paused
each frame, companion met with a bond, the wolf chosen through `_on_radial_action("form:wolf")`, the howl through
`_on_radial_action("howl")`, the player walked into the slot with `Input.action_press("ui_up")`): gold arcs, the violet answer
and its bearing line were seen in Xvfb screenshots, the cave opened as the player reached it and the stone rose; a second run
confirmed a found secret reopens with the cave open, the stone gone and howling still on offer. Elixir: the standalone
`secret_reveal_test.exs` and `howl_test.exs` pass; `mix test` could not run (hex.pm blocked), so the new channel tests are
unrun. *Not checked:* the world-pack build, phone frame rate, a real two-player session, and the feel (that is the playtest).

## Underroot — built 2026-11, every choice below OPEN for the owner's review

Underroot follows the Drifthallow template: **caves beneath the great tree**, root tunnels, glow-moss and slow
dripping water, so dark you see only a small circle round yourself, hiding **the root-heart, a seed glowing deep
in the tangle**, found by **delegating** to your companion ("Go look") and **following** it. The pitch was agreed
(hushed, safe-dark; the companion's glowing eyes and own light; Go look enabled here; if you push ahead it gently
stops leading and you are turned around; bond shapes it; a new reveal type; reuse GuideAction + NavAgent; the
darkness built like the final MistVeil). **Everything finer was decided by the builder and is listed here for
review.** Nothing below changes the pitch; if any of it is wrong, say so and it is data or a small edit.

**What it is.** `server/priv/world_seeds/underroot.json` (and the test fixture) from `tools/gen_underroot_world.py`;
art from `pokepals/tools/gen_underroot.py` over `tools/pixelart/underroot.py`; catalog id `cccccccc-...`, slug
`underroot`, listed and featured, with the standard small portal home beside the arrival spot.

**The secret: reveal type `follow`.** Spec shape (`secret.reveal`): every number (below) and `lines`. The heart is
hidden until you and your companion have both arrived (`arrive_player` 130 px, `arrive_companion` 170 px), then it
rises (`SecretDirector` -> the usual claim). Code: pure `FollowGuide` (`scripts/world`, 19 tests), presentation
`FollowDirector` (`scripts/presentation/mechanics`), `CompanionView.plan_route` / `pending_command`,
`CompanionBrain.pending_command`, an optional `speed` in the `guide` command meta, `SecretDirector` (the `follow`
arm, `can_go_look`, `go_look`), and the radial's "Go look" entry in `world_controller.gd`.

**Judgment calls (all open):**
1. **How the lead works.** No new movement. On the ask, the companion body plans a route from where it stands to the
   heart through the world's own NavGrid (`plan_route`, one A* search, up to 40,000 expansions, smoothed into
   straight legs), and `FollowGuide` walks those waypoints by re-issuing the Drifthallow `guide` order each frame
   (the NavAgent still does the local steering). Asking again plans afresh from wherever it now stands, so a
   wrong turn is never a dead end.
2. **The "pushing ahead" rule (concrete, kind, data-tuned).** You are pushing ahead when you stand ON its route (within
   `ahead_lateral` 75 px of the legs still ahead of it) and further along it than `ahead_margin` (70 px at zero
   bond, 110 at full). Then it HOLDS: it stands, facing you, with its light down. Fall in behind it and it carries on.
   Keep pushing on for `ahead_patience` (7 s at zero bond, 14 at full) and it lets the lead go: it comes to walk
   beside you as an ordinary companion, and a hint says to ask again and let it go first. Being alongside it across a
   wall, or behind it, is never "ahead". It never punishes: no fail state, nothing is lost, asking again restarts it
   (if you are still ahead of the new route it holds straight away until you fall in behind).
3. **Waiting.** If you fall more than `wait` behind (150 px at zero bond, 190 at full) it stops, facing you, until you are
   within 90 px. Beyond 900 px it lets the lead go. Both numbers are kept inside the reach of its light so you can
   see it while you follow.
4. **Bond.** All are low..high pairs blended by bond: **reach** (route px one ask can lead: 1000 at zero bond, 7000,
   a whole route, at full; when it runs out it loses the scent, stops, and waits for you to ask again), **pace**
   (74 to 100 px/s; you walk at 118, so a bonded companion is easier to keep up with but you can still overtake
   it), **wait**, **ahead margin and patience** (above), and **notice** range (300 to 620 px) and cooldown (18 s to
   8 s). Bond rises quickly while you walk together (about 0.01 a second in a scratch run), so reach mostly bites in
   the first minute; a newcomer may need to ask once or twice more, an old friend never.
5. **Noticing (lesson from Drifthallow).** As you come near the heart, in any state, the companion stops and points
   toward it for 2.5 s (`point_at`, like the Riverbank), then cools down. It senses as the crow flies, through walls,
   so pointing is a feeling and not a map: it can be a true direction with a wall in the way. This is also how a
   player who is not asking can notice something is there.
6. **Generous arrival.** The condition is the player-facing one: you and your companion both within range of the
   heart. You need not have been led there; if you find your own way, the companion tagging along completes it.
   The server check stays minimal and honest, like `stillness` and `tracks`: "this world, standing at the heart". It cannot
   tell a led arrival from a walked-in one.
7. **Natural actions (lesson from Dozewood).** The brain's command slot holds one order, so our per-frame guide order
   would overwrite the player's. Now: a **Call** ends the lead gracefully (it comes to you, a hint says to ask again);
   a **Pet** is enjoyed: we leave the companion alone for `pet_pause` (3 s) and then the lead carries on where it
   was (checked in a scratch run through the real loop). Walking around, tapping props and examining do nothing to
   it. The form's own drift is held off while it leads (as Drifthallow's fox).
8. **Readable states (lesson 3).** The companion's light is the signal. It swells to a 132 px pocket while it leads
   (the `extra` pockets given to MistVeil), holds a softer steady pocket while it waits for you, and is down to its
   ordinary pocket (76 px) while it holds back. Each state also has a hint the first time (ask, wait, balk), and the
   cues that need an action (it lost the scent, it let go, it was called) say so every time.
9. **The darkness is MistVeil, configured, with no new shader and no change to it.** `atmosphere.fog`: near-black
   `color`, `density` 0.97, a barely moving swirl, `clear_radius` 52 and `fade_radius` 175 (a small soft circle round
   you), `light_clear` 0.93, the companion's pocket 76 px and friends' 60. Static glow-moss, glowcaps and seedlings are in
   `lit.prop_types` and baked once into the low-res light mask, so none pop in as you approach (positions measured from
   the sprites: moss glows at y +3, caps at y -3, seedling tip at y -4). The veil's render-small, world-space,
   late-in-frame design is exactly Steamhollow's. A new optional hedge `highlight` colour keeps the shared hedge
   tile's green top-edge off the root walls.
10. **The companion's "glowing eyes".** Read as its own light (the pocket), not as two drawn eyes: the animals' forms
    differ and the pocket reads on all of them. If you want drawn eye-glints, it is a small overlay that needs per-form
    eye positions.
11. **Layout.** 2800x2100, a 21 x 15 grid of 120 px cells (tunnels 90 px clear, walls 30 px thick), nine chambers (the
    Rootfall where you arrive, the Tangle in the middle, the Drip Hall, the Hush Pools, the Glowcap Garden, the Lantern
    Room, the Old Stair, Cairn Row, and the Heartwood in the far north-west), and ~130 wall runs. The maze seed is
    searched until the way from the Rootfall to the Heartwood is 50 to 62 cells (this one: 57 cells, about 5400 px of
    route, about a minute and a quarter at full pace) and there are at least 28 dead ends. The generator asserts the
    spec places nothing solid in a tunnel's middle.
12. **How the player learns it.** Diegetically: the intro line, and a scratched stone by the arrival that says to let your
    companion go first and follow its light and to tap it and ask it to Go look.
13. **Look.** Dark earth, root-tangle walls, hanging-root pillars (the willow shape in root colours), mossy mounds and pale
    fungus in the chambers, a still black pool, glow-moss and glowcaps as the light sources, glow-worms (`ambient_life`
    fireflies, always on). Visitors are not re-lit. No native creatures (optional; glow-worms are the only life).
14. **Keepsake and qualities.** `kept_root_heart` (the seed wrapped in small roots on a clay saucer), drawn by `WorldArt`
    like the other secrets. Qualities `quiet`, `glowing`, `old`; temperament curious-ish, low energy, clingy.
15. **Lore and lines** (the stone, fixtures, the nine hints and the found line) are the builder's wording.

**Verified:** Godot unit suite (new `TestFollowGuide`) and every smoke except `smoke_clickton` (its one known
baseline failure); the new `smoke_underroot` checks the re-skin, the dark, the hidden heart, a planned route through
the tunnels, the lead and the arrival. Scratch runs through the REAL loop (the paused scene un-paused each frame, the
companion met, Go look triggered through the radial handler, the player driven with `ui_*` actions following the
companion's breadcrumbs): a bonded companion led the whole route in about 64 s and the heart rose; a fresh one lost
the scent partway, was asked again, replanned from where it stood and arrived in about 76 s; a player who ran ahead
made it hold, then let go after its patience (it never moved a step ahead); a Call ended the lead and a Pet was
enjoyed and the lead resumed. Screenshots under Xvfb (opengl3) checked by eye. Elixir: the standalone
`secret_reveal_test.exs` passes; `mix test` could not run (hex.pm blocked), so the new channel test is unrun. *Not
checked:* phone frame rate, the world-pack build, a real two-player session, and the feel (that is the playtest).

## Lanternfold — built 2026-11, every choice below OPEN for the owner's review

Lanternfold follows the Drifthallow template: **a shadow-puppet world**, flat layered paper-cut silhouettes against a warm
amber sky, all lit by one great lantern, hiding **a mural with one figure missing (a bird in flight)** whose gap only your
companion's SHADOW can fill. The pitch was agreed (a cliff-face screen the lantern throws shadows on; you choose the
companion's form and stand it in the light; the wolf's shadow is too big, the rabbit's the wrong shape, only the bird's,
from the right place, fills the gap; the mural reacts as it nears; a door in the cliff opens; players cast shadows too;
a new reveal type). **Everything finer was decided by the builder and is listed here for review.** Nothing below changes
the pitch; if any of it is wrong, say so and it is data or a small edit. Catalog id `eeeeeeee-...`, slug `lanternfold`,
listed and featured, with the standard small portal home beside the arrival spot.

**What it is.** `server/priv/world_seeds/lanternfold.json` (and the test fixture) from `tools/gen_lanternfold_world.py`;
art from `pokepals/tools/gen_lanternfold.py` over `tools/pixelart/lanternfold.py`.

**The secret: reveal type `shadow`.** Spec shape (`secret.reveal`): `face` (the screen's face: x0, x1, base_y, height),
`lantern` (its ground point), `spot` (the ground point the missing bird's shadow would be thrown from), `species`
(bird), `hover`, every tolerance and time, and `lines` (the hints). Code: pure `ShadowCast` (the projection), `ShadowMask`
(does one silhouette have another's shape) and `MuralGuide` (the state: fit, hold, settle, notice, events) in
`scripts/world` (52 checks, `test_shadow_mural.gd`); presentation `ShadowDirector` (`mechanics/`), `ShadowScreenView` (a
`BuildingView`, spec `"view": "shadow_screen"`), `ShadowPuppet` and `assets/silhouette.gdshader`; `SecretDirector` (the
`shadow` arm and an empty-ground tap hook); two small read-only accessors, `CompanionView.form_sheet_info()` and
`PlayerView.avatar_layers()`; `WorldArt` arms for the paper bird and its keepsake; server: `secret_reveal.ex` honours it.

**Judgment calls (all open):**
1. **The projection (pure, one rule).** The lantern stands on the ground south of the screen. A thing between them throws a
   shadow of scale `s = D / d` (D: lantern to the screen's foot, d: lantern to the thing), at `x = lantern.x + (thing.x -
   lantern.x) * s` along the face, with its feet at `v = z * s` up the face (z: how high it is held). So it grows as it nears
   the lantern, slides with it, and is life-size at the screen. Right beside the lantern (under 20 px) it blocks the light and
   casts nothing, and a shadow past 4.5x is not cast. Everything walks on the ground (z = 0), so its shadow stands on the
   face's foot. This is what a real lamp on a stage floor does; no fudge factors.
2. **Why only the bird fits: it is in the air.** The mural's missing bird is mid-flight, so its gap is up the face. Only a
   bird form's shadow is held aloft (`hover`, 14 px, so `v = 28` at the spot): a shadow-only conceit (the bird itself does not
   leave the ground) that makes the form matter twice over, by shape and by height. A bird's shadow plays its sheet's fly row
   (wings beating); every other animal's shows its right-hand profile, walking when it walks and idling when it stands.
3. **Shadows are profiles.** A shadow puppet is always seen from the side, so whichever way the caster faces on the ground
   the shadow shows the right-hand profile row (mirrored for left), read straight off the same sheet the caster draws, so a
   wolf's shadow IS a wolf and yours is you in whatever you wear (`ShadowPuppet`). The silhouette shader keeps only the shape
   and clips it to the face by world position, so a too-big shadow ends at the screen's edge.
4. **Everyone present casts one** (you, your companion, and every friend's pair), not just you. It is the fun of the place, it
   costs one small node each (a handful of draws), and it needs no networking: remote puppets are already in the scene.
5. **How you place the companion: tap the lit ground.** A tap on EMPTY ground (the world controller found nothing to examine
   or command within its 100 px pick radius, then asks `SecretDirector.on_ground_tap`) inside the lantern's cone and south of
   the screen sends your companion to stand there, using the existing Drifthallow `guide` order re-issued each frame (the
   NavAgent routes it round things), and it stays until released. This is the "tap = an order" path, extended to ground
   only where a world asks for it; every other world is untouched. Because the pick radius would swallow a stage tap near an
   examinable prop, the great lantern and the footlights are not examinable and the generator keeps the stage clear of
   props and trees (it asserts it). The lore lives on a painted notice beside the stage.
6. **The settle.** A pixel-hunt is not cosy, so a bird told to stand within 36 px of the right spot is put ON it ("it shuffles
   to the right place"); other animals are not helped, so the form still matters. It re-applies when the form changes while
   posed: tap near the spot first and choose Bird after, and it settles then.
7. **What "fills the gap" means (`MuralGuide.fit_of`).** `fit = place x shape`. *Place*: where the companion's shadow lands
   (x) and how big it is (s) against the gap's, forgiving in the middle and nothing at 26 screen px / 30 percent of scale.
   *Shape*: the overlap of its silhouette with the bird's (`ShadowMask.iou` on masks read off the real sheets, lined up
   centre to centre), mapped through `smoothstep(0.30, 0.95)`. It FILLS only when the form IS a bird (`species`), the fit is
   at least 0.8, and it is standing still (under 12 px/s), held for 2.2 s fresh down to 1.2 s bonded; a lost fit drains the
   hold at 1.5x rather than resetting it. With the real sheets a wolf scores 0.14 on the spot, a fox 0.20, a rabbit 0.26, a cat
   0.33 (the bird 1.0), so the gap only shimmers faintly for a wrong animal. Once filled it stays filled.
8. **Readable feedback (lesson 3).** The missing bird is a bird-shaped patch of lamplight in the flock (a "ghost"), with an
   amber halo that grows with the fit and swells while you hold it; filling ink-spreads the bird into the flock, a burst of
   light, and the door opens. Hints, once each: you step into the light and how to place the companion (`arrive`), what a
   shadow does (`shadow`), the companion noticing the gap (`notice`), the gap glowing (`close`), "its shadow stands on the
   ground; the missing bird is in the air" for a right-place wrong-shape (`wrong`), holding (`holding`); `called` and
   `let_go` every time, since they are cues to act.
9. **Generous triggers (lesson 1).** As you come near the spot (360 px fresh, 700 bonded) the companion stops and points
   at the gap on the wall for 2.5 s, then rests 16 s fresh, 6 s bonded (`MuralGuide.update`, the Riverbank/Drifthallow
   shape), and only until you are making progress. Bond also shortens the hold.
10. **Natural actions (lesson 2).** The standing re-issues its order each frame, so it checks `pending_command()`: a **Call**
    ends it (the companion comes to you; a hint says to tap again), a **Pet** is enjoyed (we leave it alone for 3 s, then the
    standing resumes; checked in a scratch run), a **form change** keeps the place, and its autonomous form drift is held off
    (`postpone_form_drift`, 30 s each frame) while it stands, as Drifthallow's fox. Walking more than 760 px away lets it go
    (a hint says so) and it follows you again; after the gap is filled it is released after 3 s.
11. **The camera.** The view is only 360 px tall and the mural stands about 190 px north of where you watch the companion, so
    while you are on the stage `ShadowDirector` eases `Camera2D.offset` 60 px up (nothing else uses it) and lets it back when
    you leave. Without it the bird's shadow is cut off by the top of the view.
12. **Layout.** 3200x2400, nine regions (Paper Landing where you arrive, Long Shadow, Moon Hill, Marionette Lane, Cutout
    Village, Reed Pools, Far Wood, Near Wood, the Footlights), the screen at the north end: a 380 x 112 face (a 380 x 30
    solid footprint), the lantern 150 px south of its foot, the spot 75 px south of the foot (2x scale), a door at the foot of
    the face 120 px right of centre. Footlights (small paper lanterns) stand along both edges of the lantern's cone so the lit
    stage reads as a stage, and a road of lit posts leads from the landing north-east to it. The generator asserts the gap
    bird fits the face with room for a flock on both sides, the spot is on the lit stage, nothing stands on the stage but the
    lantern and footlights, and nothing stands in the door's clearing or a pond.
13. **Look.** Warm paper ground in five moods with its own fibre-grain terrain and litter atlas (`lf_terrain`, `lf_details`),
    trees as flat umber silhouettes in three DEPTHS (far in the north is a pale apricot, mid a sienna, near in the south
    almost black), houses and a tower as flat cut shapes with a lit window, an ink pool holding amber glints, paper scraps
    for falling leaves; the great lantern is the only thing that glows (and a few posts and windows). The mural is drawn in
    `ShadowScreenView`: a pale lit face, a crescent moon, scalloped paper clouds, a village on cut hills, gold stars, and the
    flock drawn from the bird's own sheet so they are the very shape the bird form's shadow has.
14. **Visitors are NOT re-lit** (no `actor_look`). A silhouette look would make you unrecognisable against the dark trees, and
    your shadow on the screen already says "you are a cut-out here". Native creatures are skipped.
15. **Keepsake and qualities.** The secret is a little cut-paper bird on a stick behind the door (`paper_bird`, drawn by
    `WorldArt` like the other secrets); its keepsake `kept_paper_bird` stands in a dish of sand. Qualities `warm`, `old`,
    `glowing`; temperament curious, middling energy.
16. **The server check stays minimal and honest** ("this world, standing at the bird", like `stillness`, `tracks` and
    `follow`): it cannot tell a filled mural from a walked-in one.
17. **Found already.** On a later visit the mural is simply complete and the door open, and the shadows stay a quiet toy; only
    the bird is gone. Nothing about the mural is networked; a friend sees your companion stand there and their own screen.
18. **Performance.** The face, hills and mural are drawn once; the flock redraws only 4 times a second; shadows are one small
    node per caster that is in the light (none otherwise) using a one-sample shader with a rectangle test (no screen reads, no
    render targets, nothing allocated per frame); the fit's mask overlap is a cached lookup per species. *Phone frame rate not
    measured.*
19. **Lore and lines** (the notices, props, the nine hints and the found line) are the builder's wording.

**Verified:** Godot unit suite (new `TestShadowMural`) and every smoke except `smoke_clickton` (its one known baseline
failure); the new `smoke_lanternfold` checks the re-skin, the screen and lantern, the shadow's projection, that only the bird's
real silhouette matches the gap, that a tap places the companion (and a tap in the dark does not), the fill and the door. A
scratch run through the REAL loop (the paused scene un-paused each frame, companion met with a bond, forms through
`_on_radial_action("form:...")`, placement through `_on_world_tap`, Pet and Call through the real handlers) saw: a wolf walk
to the spot with a big wolf shadow standing on the face's foot and the "wrong" hint; the bird's shadow hanging in the gap,
filling, the door opening and the paper bird on its threshold; the companion staying put through a Pet and released by a Call;
the player's own (huge) shadow. Screenshots under Xvfb (opengl3) checked by eye. Elixir: the standalone `secret_reveal_test.exs`
passes; `mix test` could not run (hex.pm blocked), so the new channel test is unrun. *Not checked:* phone frame rate, the
world-pack build, a real two-player session (friends' shadows), and the feel (that is the playtest).

## Stillglass — built 2026-11, every choice below OPEN for the owner's review

Stillglass follows the Drifthallow template: **a mirror lake**, a perfectly flat silver lake, pale reeds and a sky that
matches the water, whose reflections are slightly wrong (tall silver pines and a pale great oak stand in the water with
nothing on the shore to cast them). It hides **a stone that only exists in the reflection**, found by standing your
companion at the water's edge, watching its reflection turn into a different animal and walk off along the shore, and
following it on the bank, step for step, to where the real stone surfaces. The pitch was agreed (reflection layer with
ordinary and "wrong" reflections; the companion's reflection its own creature; waits for you; the companion guides;
interruptions keep progress; a new reveal type; the player's own reflection is ordinary). **Everything finer was decided
by the builder and is listed here for review.** Nothing below changes the pitch; if any of it is wrong, say so and it is
data or a small edit.

**What it is.** `server/priv/world_seeds/stillglass.json` (and the test fixture) from `tools/gen_stillglass_world.py`; art
from `pokepals/tools/gen_stillglass.py` over `tools/pixelart/stillglass.py`; catalog id `ffffffff-ffff-ffff-ffff-ffffffffffff`,
slug `stillglass`, listed and featured, with the standard small portal home beside the arrival spot.

**The secret: reveal type `reflection`.** Spec shape (`secret.reveal`): `species_pool`, `start` (where the walk resumes, a point
ON the waterline), `trail` (waterline waypoints along the north bank, the last is where the stone surfaces), then every
number and `lines`. Flow: you linger near the start of the bank, your companion goes to stand at the edge, settles,
its reflection (the lake's picture of it) dissolves and an **animal it is not wearing** forms in its place, turns and walks
the shore a little ahead of you; your companion keeps its eyes on it and walks beside it; it waits when you fall behind;
at the end it stops, rings spread on the water, and a beat later the stone rises on the bank (`SecretDirector` -> the usual
claim). Code: pure `ReflectionWalker`, `MirrorGeometry` and `WaterMask` (`scripts/world`, tested), presentation
`ReflectionLayer`, `ReflectionPuppet` and `ReflectionDirector` (`scripts/presentation`, `mechanics/`), `assets/reflect.gdshader`.

**The reflection layer (`atmosphere.reflections`).** The camera looks from above and a little in front, so the image of
something on the north bank hangs straight down the screen from its feet: the waterline is the axis. So:
- **Actors** (you, your companion, friends and their companions) are each a `ReflectionPuppet`: a node flipped upside down
  (`scale.y = -1`) that runs the actor's OWN drawing code (`AvatarCompositor` / `PalSprite`) with the actor's pose, so it is
  never a copy of the art; read through two small appended read-only accessors, `PlayerView.reflection_pose()` and
  `CompanionView.reflection_pose()`. Only actors within `reach` (110 px) of the waterline show, fading with distance.
- **Trees** within `tree_reach` (150 px) of the water are baked once into `Chunk` nodes of 512 px, each drawn as two flipped
  quads (trunk, canopy) with a vertex-colour gradient fading toward the crown. A chunk is only visible while the camera can
  see it, so draw cost follows the view, and nothing redraws per frame.
- **Phantoms** (13 of them) are the same kind of quad for trees with no tree on the shore: `phantoms: [x, base_y, sprite]`,
  baked as pale blue-silver pines, a willow, a birch and a great oak (`sg_ghost_*`), a touch more opaque than the real
  images and rippling more slowly on their own beat, so the lake is wrong in a way you feel before you can name it.
- **Phone-cheap by construction (the MistVeil lesson):** no SubViewport, no render target, no screen read. One shader
  (`reflect.gdshader`) does the whole look: it clips to the water by sampling a small bitmap (`WaterMask`, 2 world px per
  texel, only over the lake's bounding box, R8, ~0.6 MB), silvers and cools the image, ripples it a whole texel at a time and
  fades it with depth below the waterline. The bitmap is scanline-filled once at load from the very rings `WorldArt`
  draws (`WorldArt.pond_rings()`, a small appended read-only accessor), so the clip lines up with the visible water.
  The CPU reads the same bitmap to find the waterline below an actor (`MirrorGeometry.waterline_below`, stepping, then
  bisecting).

**Judgment calls (all open):**
1. **Reflections hang DOWN from the north bank only.** That is what the camera physically sees, and it makes the lake's
   north shore the place where everything happens. Something on the south bank has no image (it would fall on land). The
   world's one walk runs along the north bank for that reason.
2. **Which animal.** The reflection is always **a different animal to the one the companion is wearing**, chosen from the
   spec's `species_pool` (cat, fox, rabbit, bird, wolf) by a seed taken from the secret's id, so a given shape always meets
   the same other animal (`MirrorGeometry.pick_species`, tested); coat variant seeded too. If the companion drifts into
   the reflection's shape mid-walk, the reflection becomes another one. The form drift is held off while it is under way
   (`postpone_form_drift`, as Drifthallow and Underroot).
3. **The hand-over.** Your companion's own mirror simply stops while the lake is showing someone else walking off (it
   dims during the turn, absent while it walks); that missing reflection is part of the eeriness. The odd reflection forms
   at the start of the path as the companion's image dissolves (a flicker through the other animals, rings on the water),
   then walks. When it is interrupted, your companion's mirror comes back.
4. **Triggers are generous (Drifthallow's lesson).** Only YOU have to be near and lingering: within 280 px of where the walk
   resumes and moving under 34 px/s for 1.2 s. If the companion is not already at the edge (190 px of the spot) it goes to
   stand there by itself (`approach`, a `guide` order, to a point 26 px up the bank), the way Drifthallow's fox trots to the
   scent. It must then stand still (under 14 px/s) for 1 s; the water stirs (rings, its gaze turns down to its own image)
   as it settles. A player just walking past is never hijacked (the linger test).
5. **The companion guides.** During the turn it stands and watches; while the reflection walks it keeps beside it (a `guide`
   order to a point 26 px up the bank from the reflection, hurrying at 1.6x pace when it falls more than 90 px behind),
   and its gaze is turned toward the reflection throughout (`CompanionView.listen_toward`, a pose that never stops the
   body). The reflection walks at 68 px/s (you walk at 118) and waits, standing, when you are over 200 px from it, resuming
   within 120 px: step for step. It never gets ahead of you out of reach, and it is never a fail state.
6. **Interruptions keep progress.** If your companion gets more than 380 px from the reflection, or you wander more than
   760 px, the reflection goes back to mirroring where it stopped; stand your companion at the edge THERE and it picks
   up from that point (a scratch run teleported the companion 520 px away mid-walk: the walk dropped, kept its waypoint,
   resumed and finished). Standing at the start again does nothing once it has moved on.
7. **Natural actions (Dozewood and Underroot lessons).** The brain's order slot holds one order, so ours never overwrites a
   Pet or a Call: a Pet is enjoyed (we leave the companion alone for 3 s) and a Call is answered (4 s); for both, the
   reflection simply stands still (`hold`) and never lets go. Checked in scratch runs through the real loop.
8. **Noticing.** As you come near the start of the bank, in any shape, the companion stops and points down at the water
   (range 280 px at zero bond, 620 at full; every 16 s, every 6 s bonded; held 2.5 s), plus a one-time hint line.
   Pure: `ReflectionWalker.notice`. A scratched stone at the landing and a cairn at the start of the bank say, diegetically,
   what to do (stand your companion at the edge on the north bank, be still, watch the water).
9. **Readable states.** A first-time hint for each of: notice, approach, gather, turn, set off, wait, follow; the cue that
   needs an action (it let go) says so every time. The walking reflection is brighter and less silvered than the plain
   images (`walker_silver_mix` 0.12), leaves a ripple at each step, and has its own shimmer while it changes.
10. **Server check stays minimal and honest** (like `stillness`, `tracks`, `follow`): "this world, standing at the stone". It
    cannot tell a followed reflection from a walked-to bank.
11. **Personal and display-only.** Your lake's reflection that walks is yours; a friend beside you sees their OWN lake
    (their companion's reflection, ordinary), plus your ordinary reflections. Friends' actors are mirrored like yours.
12. **The lake's shoreline is walled with a chain of invisible posts, and pond collision is OFF.** The shared ponds are
    collision circles of the nominal radius, but the drawn bank is a wobbly ring (`WorldArt.organic_radius`, up to ~20% off
    the circle), which would let you stand ~50 px into the lake or stop ~50 px short of it exactly where the reflection
    must stand on the waterline. So the spec sets `collision.pond_blocks: false` and the generator (which ports the same
    ring formula) places 372 solid `sg_shore` props (an `unseen` prop type, so nothing is drawn) along the union's outer
    boundary every 14 px, so you stop at the water you see. (Posts are 8 px radius and the body's feet sit 8 px below its
    centre, so feet stay dry.) This is the cost of a mismatch that already exists in every pond world; fixing it in
    `Solids` for everyone would be a shared change, left out.
13. **Layout.** 3400 x 2600, eight regions (Sedge Landing where you arrive, South Shore, West Marsh, Still Water, East
    Shallows, Grey Orchard, Silverbank, Quiet End), four overlapping ponds (radii 400 to 470) making one lake, 382 trees,
    ~120 props. The shore path is 24 waypoints, about 1930 px, about 28 s of walking, from the west of the north bank to
    the east; the generator keeps a 74 px corridor of the bank clear of trees and props and asserts every waypoint stands
    on a north bank (water just below, dry just above). The stone surfaces 16 px up the bank from the last waypoint.
14. **Look.** Pale silver-green turf and cool grey-green trees (willows, birches, poplars, oaks), a nearly featureless silver
    water tile, pale vignette and day tint, a very slow ping-pong between two silvers for the day cycle. No butterflies,
    no fireflies; a leaf now and then. Visitors are not re-lit. No native creatures (optional; skipped).
15. **Keepsake and qualities.** `kept_mirror_stone` (the stone in a shallow dish of still water with its image beneath, a
    touch too bright), drawn by `WorldArt` like the other secrets; the in-world `mirror_stone` too. Qualities `quiet`,
    `watery`, `old`; temperament curious-ish, low energy, a little clingy.
16. **Lore and lines** (the landing stone, cairns, posts and boulders, the eight hints and the found line) are the builder's
    wording.

**Verified:** Godot unit suite (new `TestMirrorGeometry`, `TestReflectionWalker`) and every smoke (new `smoke_stillglass`)
except `smoke_clickton`'s one known baseline failure. Scratch runs through the REAL loop (the paused scene un-paused each
frame, the companion met, the player driven with `ui_*` actions): a companion that started 100 px away walked to the edge
itself, settled, its reflection turned into another animal and walked the whole shore in about 30 s with the companion
keeping beside it, and the stone rose; the interrupt, pet and call scenarios above all recovered and finished. Screenshots
under Xvfb (opengl3) checked by eye: the silver lake, ordinary reflections of you and the shore trees, the phantoms, the
walking reflection and its ripples, the rings and the rising stone. Elixir: the standalone `secret_reveal_test.exs` passes;
`mix test` could not run (hex.pm blocked). *Not checked:* phone frame rate, the world-pack build, a real two-player
session, and the feel (that is the playtest).

## Ebbmere — built 2026-11, every choice below OPEN for the owner's review

Ebbmere follows the Drifthallow template: **tidal flats**, wide wet sand under a wide sky, tide pools, creeks, shell
ridges and a lighthouse on a rocky point. The sea slowly goes out and comes back on a **shared clock**, and a sand-dollar
rises only at the lowest tide, buried on the far bar, which your companion helps you find and dig. The pitch was agreed
(the tide as a pure function of UTC time with an authored period and low window; sniffing out dig spots; tap-to-dig through
the form, with fox and rabbit digging and bird and cat not; mostly shells and crabs; one spot that gives up the sand-dollar
only in the lowest window, with no fail state; a new reveal type the server can honestly check). **Everything finer was
decided by the builder and is listed here for review.** Nothing below changes the pitch; if any of it is wrong, say so and it
is data or a small edit.

**What it is.** `server/priv/world_seeds/ebbmere.json` (and the test fixture) from `tools/gen_ebbmere_world.py`; art from
`pokepals/tools/gen_ebbmere.py` over `tools/pixelart/ebbmere.py`; catalog id `14141414-…`, slug `ebbmere`, listed and
featured, with the standard small portal home beside the arrival spot.

**The tide clock.** `TideClock` (`scripts/world`, pure, tested) and its Elixir twin `Server.Tide`: integer unix
milliseconds in, one cosine per period out. Phase 0 is high water, 0.5 the lowest; `level = low + (high - low) * (0.5 + 0.5
cos(2π phase))`. **Judgment calls (all open):**
1. **Numbers.** Period 360 s (the pitch's "such as 6 minutes"), epoch 0 (so high water is on every 6-minute mark of the UTC
   hour), level 0.30 to 0.78, `yield_level` 0.345. The **low window** is where the level is at or under `yield_level`:
   about 71 s wide (35.7 s either side of the lowest), a fifth of the cycle, so it is generous without being always.
2. **Skew.** Server and clients agree to the millisecond if their clocks do. Clients use their own clock plus an offset: the
   channel now pushes `clock` (`ms`) on join and `Net.server_unix_ms()` applies it (one-way latency is not corrected, which
   is tens of milliseconds against a 71 s window). The server also allows `grace_s` = 30 s either side of the window on a
   claim, so a slow examine or a skewed device is still honoured.
3. **Held to the same vectors.** `tests/world_fixtures/tide_vectors.json` (generated from a Python reference) is read by the
   GDScript test; the identical `server/test/fixtures/tide_vectors.json` by the Elixir one (phase, cycle, level, low window
   with and without grace, countdown).
4. **Per-tide hashing instead of a server.** Which dig spots are alive in a tide, and what each holds, are
   `DigPlan.hash01(cycle, id)` (FNV-1a, deliberately not `String.hash()`), so every client agrees on both with nothing
   simulated or sent.

**The tide's look and the walkable sand.** The world carries a baked **seabed** (`tide.field`): 16 bits of elevation per
16 px cell (225 x 163 for the 3600 x 2600 world, about 98 KB of base64 in the spec; one byte stair-stepped the gentle flats into squares, so the GPU reads it as a half-float texture). The water covers a place whenever the level
is over its elevation, so one number per place says when it is wet.
5. **One shader, one quad, no render target.** `TideLayer` is a single rectangle (clipped to the rows the water can ever
   reach) with `assets/eb_tide.gdshader`, which samples the seabed texture and the level uniform: open sea, shallows,
   a foam lace at the edge, then a band of darkened, glossy sand just behind the retreating water that holds the sky (the
   "wet sand that reflects the sky"). The only per-frame work is two uniforms and a few small wading ripples; nothing is
   rebuilt. It is a child of `WorldArt` (above ground/props/litter, under the y-sorted Scenery), so props stand under the
   water if the tide covers them. `TideField.wet_extent` keeps the rect off the always-dry dunes.
6. **Wading rule.** **No moving walls.** Elevation under `deep_elev` (0.26) is open sea: always water, never wadeable, walled
   by 336 invisible `eb_shore` props along its edge (the Stillglass lesson: the posts are placed from the very grid the
   shader reads, so the drawn drop-off and the collision agree). Everything else is wadeable however far the tide covers it
   (it is knee-deep at the deepest; the water just looks deeper). The generator keeps the arrival, the tide pole and the
   lighthouse over the highest tide.
7. **Geography.** Sea to the north, a shelf, flats rising about 0.5 over 1500 px to dunes at the south (so the waterline travels
   about 1400 px between low and high tide, at most ~12 px/s, easily outwalked), three creeks and fifteen pools whose floor
   (0.285) is under the lowest water so they carry water through every tide, five shell ridges (low rises), the rocky point.
   Regions: Dune Landing (you arrive), Wrack Line, Cockle Ridge, Pool Terrace, The Creeks, Far Bars, Lantern Point, Greywater.
   `border.ring` is false (a treeline in the sea would be wrong); the south is edged with wind-bent dune pines, thorn
   scrub and tamarisk.
8. **The tide is always readable.** Three ways: the **tide pole** (`TideGauge`, a post in the y-sorted Scenery by the landing:
   a blue float rides it with the water with an arrow for which way it is going, and a gold notch for the lowest-tide level
   that glows while the tide is under it); the **lighthouse lamp** (`LampGlow`), which burns brighter the lower the tide is;
   and the **waterline itself**. First-time hints (spec `tide.hints`) for each state: going out, lowest tide close (24 s
   before the window), lowest tide, coming back, high water; later tides get a short version of "lowest is coming" and
   "lowest tide".
9. **Not done.** Wading does not slow you (a shared-physics change); a friend's feet do not make ripples (only yours and
   your companion's).

**Dig spots and sniffing.** 26 authored spots across the flats plus the far bar's `bar_dollar`.
10. **Alive and exposed.** A spot is *alive* in a tide with probability 0.62 (hashed; the far bar's is always alive until the
    secret is found) and is *exposed* when the level is under its elevation by `expose_margin` (0.012), so a spot shows its
    sign only once the water has drawn back a little. Elevations run 0.37 to 0.74, so more appear as the tide falls: none at
    high water, about 21 at the lowest. Everything resets at the next high water (a new cycle): the sea has smoothed the sand.
11. **Sniffing, and generous triggers.** Pure `DigSense` (tested): when an alive, exposed, un-noticed spot lies within a
    range of YOU (240 px at zero bond to 560 at full), your companion stops and points at the nearest for 2.4 s (cooldown
    9 s to 3.5 s by bond), after which the spot is *noticed* and shows its sign: a dimple with a ring of rising bubbles.
    A spot within 64 px of you or your companion is noticed at once (you would see it yourself). A hint reads once for the
    sniff and once for the sign.
12. **Tap to dig is an order through the form.** The world-tap hook (one line in `_on_world_tap`, ahead of the snap to the
    nearest examinable thing) gives `TideDirector` first refusal of a tap within 54 px of a noticed, exposed spot. A form
    that can dig gets the same `visit` command the Vale's mounds use, with `verb: dig`, and digs for 1.8 s with a spray of
    sand when it arrives. **Which forms dig (open):** fox, rabbit and wolf (`dig.affordances`; a wolf is a canine, the pitch left
    it open); bird and cat cannot, and the classic procedural rig (no animal) digs (`_default`). The **cue** for a shape that
    cannot: the companion still goes over and pats at the spot, a ring flashes there and a hint names the shapes that could.
    A sign pulses in the form's highlight colour (C-3) only while the worn form can dig it.
13. **Natural actions are safe.** The order slot holds one order, so ours never overwrites a Pet or a Call: a Pet or Call
    cancels the dig in flight (as it cancels any visit; nothing is lost, the spot is still buried, tap again), and the
    sniffing stands down for 3 s after a Pet, 4 s after a Call. Changing form mid-order is fine (the verb was resolved
    at the tap). Digging a spot twice says it is already dug.
14. **What a spot holds** (spec `dig.outcomes`, hashed per tide and spot): a shell (cockle, whelk, razor shell, scallop or
    periwinkle; weight 7), a crab that scuttles for the sea (2), or a piece of sea-glass (1). It is a drawn find lying by the
    hole until the tide takes it: shells and sea-glass are **display-only** (not an inventory item, not saved), which is the
    cheap, cozy option; making them collectable (a shell collection, a keepsake, a coin) is a possible follow-up.
15. **Personal and display-only.** The tide and which spots are alive are shared (the same hash); your holes, signs and finds
    are yours. A friend does not see them dug.

**The secret: reveal type `tide`.** The sand-dollar's spot is the far bar, a low sandbar whose top stands at exactly
`yield_level + expose_margin` (the generator forces it and asserts it), so it is uncovered **exactly while the tide is in its
low window, and never otherwise**. A fox, rabbit or wolf sent to dig it brings the sand-dollar up (`TideDirector` ->
`dollar_unearthed` -> `SecretDirector._reveal`), and examining it makes the usual claim. A missed window is just the next tide.
16. **The server CAN check this one.** `Server.SecretReveal` honours a `tide` claim only while `Server.Tide.low_window?` is
    true for the server's own clock, widened by `grace_s` (30 s), plus the usual "standing within 130 px of the spot". It
    cannot tell whether you dug it (the digging is on your screen), only that the claim is made at the lowest tide at
    the bar, which is an honest, if modest, check; it refuses with no clock rather than guessing (tested).
17. **If the window passes before you examine it.** The prop stays where it came up; if the claim is refused a line says the
    tide has turned and the sand-dollar will rise again at the next lowest tide (examine it then). Nothing is lost.
18. **Keepsake and qualities.** `kept_sand_dollar`: the sand-dollar in a shallow dish of sand, drawn by `WorldArt` (a procedural
    arm, since homes use the shared art); the in-world prop is the sprite `eb_sand_dollar`. Qualities `quiet`, `watery`,
    `old`; temperament curious, middling energy.
19. **Lore and lines** (the tide stone at the landing, the rowboat, buoy, groynes, the hints and the dig lines) are the builder's
    wording.

**Look.** Pale sand in five moods with baked ripple marks (own terrain + litter atlas `eb_terrain`, `eb_details`: cockles,
whelks, razor shells, a scallop, starfish, wrack, lugworm coils), wind-bent dune pines, thorn scrub and tamarisk, a pale
sky-warm tint with a very slow rose swing for the day cycle, a barely-there cloud drift. The lighthouse is a landmark
(`lighthouse` art entry: trunk = tower, canopy = gallery, lamp room and roof) you can walk behind. Visitors are not re-lit.
Native creatures (crabs, gulls) were skipped: the crab that scuttles from a dig is a drawn effect, not a pal.

**Verified:** Godot unit suite (new `TestTide`: clock vectors, field, dig plan, sensing) and every smoke (new
`smoke_ebbmere`) except `smoke_clickton`'s one known baseline failure. The smoke drives the REAL scene through the director's
debug clock: the level at high water and at the lowest, the far bar covered ebbing and bare at the lowest, a bird that is
sent over but cannot dig, a fox that digs the sand-dollar up, a rabbit that digs an ordinary spot in a later tide. Elixir:
the standalone `secret_reveal_test.exs` and `tide_test.exs` pass (with the vectors); `mix test` could not run (hex.pm blocked).
*Not checked:* phone frame rate, the world-pack build, a real two-player session and the feel (that is the playtest).

## Loftreach — built 2026-11, every choice below OPEN for the owner's review

Loftreach follows the Drifthallow template: **sky islands**: grassy islets floating in open sky over a sea of cloud, joined by
rope bridges, with windmills, kites and weathervanes, bright and breezy and high. It hides **a nest on an islet you cannot reach
on foot**, found by borrowing your companion's eyes. The pitch was agreed (a bird sent up; the camera rises with it; the clouds
and the islands' shapes form a picture pointing at the islet; the hidden bridge appears once it has been seen from above; walk it
and examine the nest; Go up offered in every shape with a cue; bond shapes it; the companion notices the islet; a new reveal
type; the camera always returns). **Everything finer was decided by the builder and is listed here for review.** Nothing below
changes the pitch; if any of it is wrong, say so and it is data or a small edit. Catalog id `12121212-...`, slug `loftreach`,
listed and featured, with the standard small portal home beside the arrival spot.

**What it is.** `server/priv/world_seeds/loftreach.json` (and the test fixture) from `tools/gen_loftreach_world.py`; art from
`pokepals/tools/gen_loftreach.py` over `tools/pixelart/loftreach.py`.

**The secret: reveal type `skyview`.** Spec shape (`secret.reveal`): `species` (bird), `bridge` (the hidden bridge's id), `vantage`
(where the bird hangs), `targets` (what must be in view: the nest and the bridge's head), `head`, then every number and `lines`.
Flow: shift to a bird, tap **Go up**; the bird (a `SkyBird` puppet drawing the companion's own animal sheet) lifts off, the
real body is hidden and held where it stands, the camera zooms out and follows to the vantage, the high clouds fade in as an
arrow, and when the bird has looked at the nest AND the bridge's head for `see_secs` the rope bridge unspools from its head
toward the Rookery. It stays up a few more seconds to let you watch, then glides home. The nest is the secret's prop, there from
the start in plain sight; examining it is the usual claim. Code: pure `SkyView` (flight, bond scaling, seen, noticing; 11 tests)
and `SkyRealm` (island fences, bridges, ground test; 15 checks) in `scripts/world`, `SkyDirector` in `mechanics/`.

**Judgment calls (all open):**
1. **The sky is the world's ground, not a ground layer plus obstacles.** The spec's `sky` block (island outlines, bridges, the
   windmill, kites, the picture's puffs) is the only description; `SkyRealm` derives the collision fence and the walkable ground
   from it, and `SkyLayer` draws it, so the three cannot disagree. `WorldArt` paints no ground of its own when a `sky` block
   exists (`ground.render: "none"`; one line in `_draw`), and no border ring of trees.
2. **Island edges are segment solids, not posts.** Each outline edge is one capsule (radius 5), and where an open bridge joins an
   island the edge is cut by exactly the bridge's strip (a slab test, any angle); the bridge gets a rail down each side. Bodies
   inside are pushed back in the way hedges push them. 469 solids for the world. No change to `Solids.resolve`; one appended
   call in `Solids.build`.
3. **The hidden bridge is not a gate prop; it is shut by geometry.** A hidden bridge has no gap, no rails and no ground until its
   id is in `sky.revealed`. Revealing appends the id and rebuilds the solids and the companion's grid
   (`WorldController.reveal_sky_bridge`, like the Ruin's `rebuild_solids_dropping`). A found secret starts the visit revealed.
   The bridge stays down for the visit (a fresh visit before the find shuts it again, so the bird has to look again; it is quick).
4. **Routing never goes through the sky.** `NavGrid.build` gained one optional argument, a ground test; cells whose centre is not on
   an island or an open bridge are unwalkable. Without it the grid would have treated open sky as walkable and a companion pressed
   against an island's edge could be planned a route from the sky side. The ground test is `SkyRealm.ground_test`. A scratch
   run confirmed a companion crosses a bridge by itself, and a player-driven bot crossed every bridge, including the new one,
   with the companion following.
5. **The picture.** The high clouds (`sky.picture.puffs`, 32 puffs) draw a great arrow from over Vane Hill, across Pennant Crag's
   edge where the bridge begins, to the Rookery, with barbs at its head and a fletching at its tail. It is drawn by `SkyAir` above
   everything and is invisible below `picture_from` 0.35 of the climb, fully there by 0.8, so it can only be read from up high; it
   is also 1500 px long, which no ground-level view (640 x 360) holds. The islands are egg-shaped, all leaning toward the Rookery,
   and the weathervanes (three on Vane Hill, one on High Perch) all point up and to the right whatever the wind, and the standing
   stones carry the same hint in words: the picture is the confirmation, not the only clue.
6. **Why the bridge starts where it does.** The way is a long hidden bridge (408 px, the head on Pennant Crag's north-east edge,
   far mouth on the Rookery) so the islet is not in view from any island at ordinary zoom (the half-view is 320 px). The head
   shows from the start as two posts with frayed rope ends stirring, "two anchors that go nowhere", and the arrow's shaft crosses
   the crag right over them.
7. **Go up.** A radial entry in every shape, in any world with a `skyview` secret (the Hollowsong Howl pattern). In bird form: the
   flight. In any other shape: the companion looks up and a hint says only a bird can climb that high, then to shift to Bird and
   tell it to Go up. The bird form is held for the flight (`postpone_form_drift`); an instructed change of shape mid-flight brings it
   home. A found secret leaves Go up as a quiet toy.
8. **The flight (data in `reveal`).** Rise 1.6 s while it flies to the vantage at 1100 px/s (0.9 to 3.0 s, so far away is still a few
   seconds), hangs `stay` seconds (5 at zero bond, 10 at full), glides home 1.5 s to wherever the companion stands now. Seeing the
   way extends the stay to at least the bridge's 3 s unspooling plus 2.2 s, so the bridge is watched coming down. **Ending:** a tap
   on the world, the first step (keys or the stick), a Call, or an instructed shape change brings it home; the very first 0.7 s is
   ignored so the tap that launched it cannot end it. **Holding:** pressing Go up again while it is up adds 3 s, up to 20 s total.
   Movement is NOT locked (the step ends the flight, nothing is stuck); no input gating, so nothing can leave you unable to walk.
9. **Bond (all data).** Stay 5 to 10 s; how high it climbs and so how much sky the view takes in (camera zoom 0.38 at zero bond,
   1640 px of world across, to 0.30, 2100 px); how far it notices the islet (780 to 1250 px) and how often (every 18 s down to 8 s).
   The view is deliberately wide enough at zero bond to hold the nest and the bridge's head (checked by the generator), so a newcomer
   is never blocked; bond adds context (more of the arrow's tail) and time, not a gate.
10. **"Seen" (pure `SkyView`).** The bird must be at 0.72 of full height, with the nest and the bridge's head both inside the view
    (shrunk by a 30 px margin), for 1.2 s; the clock backs off if it drifts out, never resets hard. The view is the viewport
    divided by the zoom, so a wider phone screen sees more. The server stays minimal and honest: "this world, standing at the
    nest"; it cannot tell a looked-at bridge from a walked-to nest.
11. **Noticing (Riverbank/Drifthallow lesson).** Coming within range of the islet, in any shape, the companion stops and looks
    toward it for 2.5 s (a point), then cools down; a one-time hint says it has seen something. Stops once the way is seen. After
    a flight that showed the way the companion looks at the bridge's head for 3 s and a hint says to follow the arrow to the edge of
    Pennant Crag.
12. **Natural actions never reset anything (Dozewood lesson).** A Pet during the flight is enjoyed (the flight goes on; checked in a
    scratch run), the one-order brain slot is only used for a hold when nothing is pending, and a Call ends it gracefully.
13. **The camera always returns.** `CameraRig.hold_view(center, zoom)` steers it every frame (the cinematic mode the Gateway
    reveal uses) and `end_hold()` hands it back; the director restores on landing, on `finish()` (the secret taken) and in
    `_exit_tree` (the world left mid-flight), and the real body is made visible again in all three. A smoke check drops a flight
    mid-air and checks the camera, zoom and body. The follow resumes from where the camera is, so it glides back to you.
14. **Phone and web cost.** The islands' turf, cliff and tapering underside are baked once into one mesh each; a bridge is chunks of
    six planks; nothing per plank or per edge is drawn per frame; islands and bridges are skipped when the camera cannot see them;
    the cloud sea is 150 batched quads on a parallax, culled to the view; the arrow is 32 sprites drawn only while it is visible.
    At the zoomed-out view the draw count is a handful of meshes, the visible trees (the scenery already culls to the view) and
    the clouds. No SubViewport, no shader, no per-frame allocation of meshes. *Phone frame rate not measured.*
15. **Other forms of "who sees it".** Personal and display-only. A friend sees your companion body stand still (it is only hidden on
    your screen) and does not see your bird; each player's bridge is their own. Friends' companions cross your bridge freely only
    if they too have seen the way.
16. **Layout.** 3400 x 2600, nine islands: Anchor Landing (where you arrive, with the way home), Millstone Lea (the windmill), Kite
    Green, Cloud Orchard (blossom, a great apple tree), Vane Hill, Pennant Crag (the bridge's head), Lantern Pasture, High Perch,
    and the Rookery (the nest). Nine bridges (80 px wide, 145 to 316 px long: wide so a 24 px routing grid always has a connected
    lane) and one hidden (408 px). The generator checks the islands stand at least 110 px apart, no bridge crosses a third island,
    every prop and tree stands on an island and away from its edge, the nest is on the Rookery, and the nest and the bridge's head
    both fit the zero-bond view from the vantage. ~100 trees, 60 props, 7 kites, one windmill. The windmill's sails turn (drawn by
    `SkyAir`, above the actors; the hub is measured from the tower sprite, 72 px above the prop's position).
17. **Look.** Bright sky gradient, sunlit pixel turf (its own seamless tile) with litter and worn paths from each bridge mouth, a
    stratified rock cliff and tapering underside lit from the upper left, island and bridge shadows on the clouds, two parallax depths
    of pixel cloud drifting toward the nest, butterflies and a few petals, a slow day cycle. Visitors are not re-lit. No native
    creatures (optional; skipped).
18. **Keepsake and qualities.** `kept_nest` (the little nest in a wooden dish), drawn by `WorldArt` like the other secrets; the in-world
    `lr_nest` too (an egg with a faint blue light, a feather laid across it that lifts). Qualities `high`, `old`, `warm`; temperament
    curious, a little energetic, not clingy.
19. **Lore and lines** (the signs, standing stones, vanes, the ten hints and the found line) are the builder's wording.

**Verified:** Godot unit suite (new `TestSkyRealm`, `TestSkyView`) and every smoke (new `smoke_loftreach`) except `smoke_clickton`'s
one known baseline failure. Scratch runs through the REAL loop (the paused scene un-paused each frame, the companion met, the bird
chosen and Go up taken through `_on_radial_action`, the player driven with `ui_*` actions): a bot crossed the rope bridge and the
companion followed; a step ended a flight; a flight left alone (with a Pet in the middle) saw the way in about 11 s, landed with the
camera, zoom and body restored, and the bot then walked the new bridge to the Rookery, the companion following, with the nest in
reach. Screenshots under Xvfb (opengl3) checked by eye: the islands and cliffs, the windmill and kites, the companion noticing, the
view from above with the cloud arrow and the bridge unspooling toward the nest. Elixir: the standalone `secret_reveal_test.exs`
passes; `mix test` could not run (hex.pm blocked). *Not checked:* phone frame rate, the world-pack build, a real two-player
session, an actual claim round trip against a server, and the feel (that is the playtest).

## How we work through it

Same as the direction doc: strictly one item at a time. Decide it → record the decision here →
(only then) build if it's a build item → play/verify → commit. No building without explicit
confirmation.
