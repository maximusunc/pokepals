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
- *The fog jittered and lagged behind the player.* The veil was screen-space: each frame it converted the
  player's position through the camera's transform, which could be a frame stale while the camera eased,
  so the clear patch trailed and jittered. Now the veil's layer follows the viewport (drawn with the
  camera's transform, like the world) and every position is in world px, updated late in the frame
  (`process_priority`), so the clear patch is placed in the same space as the player sprite. Checked in a
  windowed run: the patch's centre equals the player's position on every sampled frame while walking.

## How we work through it

Same as the direction doc: strictly one item at a time. Decide it → record the decision here →
(only then) build if it's a build item → play/verify → commit. No building without explicit
confirmation.
