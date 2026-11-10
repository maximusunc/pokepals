# Usable Items — Working Design (Action Backlog)

A living record of the **usable items** direction: things you earn, buy, craft or trade that **do
something**, and that work across many worlds. It is broken into action items we walk through **one
at a time**. Every item here is a decision the project owner makes; nothing is pre-approved, and
nothing gets built until it's confirmed in words.

**Status legend:** ✅ Resolved (decided; ready to build or built) · 🔶 In progress · ⬜ Open /
not yet decided · 🅿️ Parked (deliberately deferred).

**Working rule (from CLAUDE.md):** never assume a decision or act before actual confirmation. If
a question doesn't reach the owner, stop and wait. No best-guessing.

---

## Why (the problem this answers)

Every destination world so far is built around **one secret**. Once you've found it, the world
has little left to offer. Replayable mini-games like the Riverbank's salamander hunt don't fix that
on their own, because **what they pay out has nowhere to go**:

- The hunt pays 0–10 coins and the maze pays 10 (`world_channel.ex`, `@hunt_rewards` / `@maze_reward`).
- The only things coins buy are five skin/hair dyes at the bazaar (`Economy.purchase/2` sells only
  `category: "color"`).
- Keepsakes and journal entries come once per world's secret, so they run out.

The model is the Oasis from *Ready Player One*, without the fighting. People keep coming back
because **items do things, and they work everywhere**: you earn something in one world, buy or trade
for it, and it opens up something in another world. That is the missing connection between
Kithbound's worlds. It is also the right foundation for the north star: when players eventually
build worlds, those worlds plug into the same item vocabulary, so what you carry stays meaningful
anywhere.

## The shape of it

- **Items describe what they can do.** A rod can fish and a lantern gives light, defined as data.
- **Worlds decide what they allow.** A world says "fishing works here, with these catches," or "no
  lights in this cave, on purpose." Like the Oasis's zones.
- **Replayable worlds are where you earn.** Mini-games pay coins and materials, which buy or craft
  items, which open up more in other worlds. A replayable world becomes one *source* in a loop,
  not a dead end.

**The guard-rail (CLAUDE.md: no punishing progression).** Items **open up more ways to play and
never gate the core.** You can always walk, explore, and be with your companion anywhere. A
lantern makes the dark nicer, but you never need one to visit.

## Candidate items (brainstorm, all liked; none scheduled)

| Item | What it does | Where it would matter today |
|---|---|---|
| Fishing rod | Fish any water; catches differ per world | Riverbank, the Vale's ponds, Stillglass, Ebbmere, Nocthollow's lake, Bobbledown's Fizzwell, Thimblewick's teacup |
| Lantern | Lights your way | Underroot, Steamhollow's fog |
| Glider | Cross gaps; ride a hill's updraft | Loftreach's islands |
| Little boat | Go out on water that is a wall today | Stillglass, Nocthollow |
| Instruments | Play music together | Anywhere; social |
| Seeds | Plant at home or in shared places | Homes |
| Kite, camera, picnic blanket | Small toys for being somewhere with friends | Anywhere |
| Companion items | A new form, trick or accessory it carries everywhere | Anywhere |

## What already exists (reuse surface)

| Capability | Where it lives | Note |
|---|---|---|
| Item templates with a `category`, `slot` and free-form `base_attributes` | `server/lib/server/item_definition.ex` | Room to describe what an item does as data |
| Owned item instances with per-instance `attributes` | `server/lib/server/inventory_item.ex` | |
| Ledgered grants, sinks, purchases, trades | `server/lib/server/economy.ex` | The "wall": every movement is ledgered, no dupes |
| A `"tool"` category and a seeded **Lantern** (id 4) | `server/lib/server/seeds.ex` | Seeded but does nothing yet |
| Player-to-player trading | `server/lib/server/trade_session.ex` | |
| A shop in the bazaar | `world_channel.ex` `"buy"` → `Economy.purchase/2` | Sells dyes only, today |
| Server-decided rewards | `world_channel.ex` `"hunt_complete"`, `"maze_complete"` | The pattern for paying out from a mini-game |

**New machinery this direction needs:** a way to *use* an equipped item in the world, a way for
worlds to declare what they allow, materials and recipes, and shops that sell more than dyes.

---

## Decisions

- ✅ **U-1 — Direction.** *(Decided 2026-11-10.)* Build toward usable items that work across worlds
  and are honoured world by world, with replayable worlds as where you earn. Items open up more
  play and never gate the core.
- ✅ **U-2 — How players get items.** *(Decided 2026-11-10.)* **Buy with coins**, **craft from
  materials**, and **trade between players**. *Not* chosen as a main route: items as one-off finds
  or rewards in particular worlds. Materials give trading a purpose: each world yields its own, so
  players trade for what their world doesn't have.
- ✅ **U-3 — The pilot item: the fishing rod.** *(Decided 2026-11-10.)* Built end to end first:
  one way to earn it, one way to get it, two worlds where it does something. Chosen because a calm
  activity that differs in every world's water naturally makes worlds replayable.
- 🔶 **U-4 — What fishing feels like: a light skill moment.** *(Direction decided 2026-11-10;
  the exact mechanic is still open.)* Landing a fish is a short timing or tension moment, in the
  spirit of the Riverbank hunt, with rarer fish asking a little more of you. Not chosen: purely
  gentle cast-and-tap, or a game mostly about reading the water. Still cozy: a fish that gets away
  is just "next time," never a loss. **Still to decide:** the mechanic itself (a timing ring, a
  tension bar, following the fish's pull), and how much harder a rare fish is.

## Open items (walk through one at a time)

- ⬜ **U-5 — The companion's part.** How the companion joins in, by form. E.g. a cat watches the
  water and points; a bird spots shadows from above. Fishing should be something you do *together*.
- 🔶 **U-6 — Where you can fish.** The owner said **"fish anywhere"** (2026-11-10), which replaces
  "two pilot worlds." *Reading to confirm:* the rod works in **any water in every world** from the
  start, rather than only in a couple of pilot worlds. If so, each world's water needs its own
  catches, or at least a sensible default set.
- ⬜ **U-7 — What fishing pays.** Catches as journal entries, as materials, as things to sell for
  coins, or some mix. Rare catches per world give a long tail to chase.
- ⬜ **U-8 — How you get the rod.** Bought at a shop, crafted from materials, or both. Its price, and
  whether the very first rod is easy to come by so a newcomer can try fishing early.
- ⬜ **U-9 — Using an item (the general mechanism).** How a player holds and uses an item on screen
  (a radial slot, a hand slot, a tap), designed so the rod is the first of many, not a one-off.
- ⬜ **U-10 — Worlds declare what they allow.** How a world spec says "fishing works here, with these
  catches" (and later, "no lights here"), as data in the world seed. If U-6 is "any water in every
  world," this flips to worlds **opting out** and **naming their own catches**, with a default for
  worlds that name none.
- ⬜ **U-11 — Materials and crafting.** Which materials exist, which worlds yield them, and how a
  recipe works. Probably *after* the rod, unless U-8 picks crafting for the rod.
- ⬜ **U-12 — Shops.** Whether the bazaar sells more than dyes, and whether other worlds get their
  own shops.
- ⬜ **U-13 — Being seen.** Whether friends see you fishing (the rod in hand, the cast, the catch),
  so it is something to do together in a shared world.
- ⬜ **U-14 — What comes after the rod.** Which item is second, from the candidates above.
