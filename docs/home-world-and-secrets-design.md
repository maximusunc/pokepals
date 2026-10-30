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
  legible, and it maps one-to-one to one discovery in your home. No side-collectibles.
- ✅ **H2 — The home is a display only.** Discoveries appear in the home world when earned; the
  player **does not arrange or place** them. (Where each one appears is authored, see HW-3.) It is
  a reflection of your journey, not a decorating game.
- ✅ **H3 — Visits by friendship only.** You can visit a home only if its owner has accepted you as a
  **friend** (friend request) or invited you. No open/public browsing of homes.
- ✅ **H4 — The Gateway links to friends' homes.** The Gateway's world picker gains friends' homes as
  destinations, alongside the catalog worlds. (Your own home is presumably reachable from there too,
  see HW-5.)
- ✅ **H5 — Secrets go into existing worlds, but not the Vale.** The Vale stays the hub and the home
  of the **companion** beats (the finding, the form-verb objects); it gets **no** world secret.
  Today's destination worlds each get one: **the Ruin, Nocthollow, the Riverbank, the Maze, the
  Bazaar**. New worlds author theirs from day one.

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
- ⬜ **S-4 — Solving together.** If two players crack a secret together, do both get it? (Leaning
  "yes", since solvable alone and better together, but it needs a decision on what "together" means:
  same world at the moment of solving? helped?)
- ✅ **S-5 — The moment of finding: small and warm.** Decided: no popups or fanfare. The companion
  perks up and noses the find, a gentle line plays (for the seed: "A curled seed from the oldest
  hedge… it wants to be planted somewhere of your own"), and a soft note says something changed at
  home.

### The secrets themselves (one per world; authored one at a time)
Each needs its own design pass. Per P-2 in the direction doc, aim for 2–3 routes of differing
elegance, not lock-and-key. Vary the *kind* of secret so it never reads as a checklist: a puzzle, a
small game, patience, a time of day, a form only the companion can take, or just noticing.
- ⬜ **W-1 — The Ruin.**
- ⬜ **W-2 — Nocthollow.**
- ⬜ **W-3 — The Riverbank.**
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
- ⬜ **W-5 — The Bazaar.**

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
  traveled. *Built:* the base glade (800×660) has a pond, a bench, a lantern, a mushroom ring, a log,
  a HOME signpost ("…keeping space for things you haven't found yet") and a portal back to the Vale's
  Gateway. Each discovery's authored `area` widens the bounds, and the border treeline is re-baked
  around the new size.
- 🔶 **HW-3 — Where each discovery appears.** Since the home is display-only (H2), each discovery
  has an authored place in the home. A discovery should *change the place* (a glowing pool opens, a
  carved pillar stands), not sit on a shelf. Each one quietly hints at where it came from.
  *First one built:* the hedge seed grows the glade **east** into a walkable hedge spiral, with the
  sprout (examinable) at its heart and a path leading to its entrance. The rest are authored as each
  world's secret is designed.
- ⬜ **HW-4 — The companion at home.** Does the companion relate to the discoveries (favourite spots,
  lingering by things it found with you)? Ties to companion-as-self.
- ✅ **HW-5 — Getting home: the Gateway, on its own tab. (Built.)** Decided: the Gateway's world picker gets a
  **separate tab** holding **your home** (and, later, friends' homes, per H4/FR-4), apart from the
  catalog worlds. No Vale portal. Leaving home returns you to the Gateway like any catalog world.

### Friends & visiting
- ⬜ **FR-1 — A friends list.** There's no friend system today; identity is only the local token.
  Sending, accepting, and removing friends, stored server-side. *Note:* CLAUDE.md puts real
  **authentication** out of scope; a friends list over the token is fine, but it's worth a
  conscious check that it doesn't need accounts.
- ⬜ **FR-2 — How you find someone to friend.** You meet them in a shared world (tap their avatar)?
  A share code? Both? Decides how friend requests start.
- ⬜ **FR-3 — Invitations.** H3 says "invitation/friend request". Is an invite a one-off pass for a
  non-friend, or just "friends can always come"? Decide if both exist.
- ⬜ **FR-4 — Friends' homes in the Gateway.** The world picker lists friends' homes (H4): with their
  name, maybe how many discoveries, maybe whether they're home now. *Reuse:* `WorldPicker` /
  `WorldDirectory`, `list_worlds`.
- ⬜ **FR-5 — Visiting etiquette.** Can you visit when the owner is offline? What does a visitor see
  or do (look only; examine discoveries for their hint)? Safety: the owner can remove a friend at any
  time, and visiting must never be possible without consent.

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

## How we work through it

Same as the direction doc: strictly one item at a time. Decide it → record the decision here →
(only then) build if it's a build item → play/verify → commit. No building without explicit
confirmation.
