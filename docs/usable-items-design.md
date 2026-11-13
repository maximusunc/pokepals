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
- ✅ **U-4 — What fishing feels like: a light skill moment, landed with a timing ring.**
  *(Decided 2026-11-10; the ring is "for now," open to revisiting once it's been played.)* Landing a
  fish is a short timing moment in the spirit of the Riverbank hunt: a ring shrinks around the bobber
  and you tap when it lines up. Rarer fish make the window smaller. Still cozy: a fish that gets away
  is just "next time," never a loss. Not chosen: purely gentle cast-and-tap, a game mostly about
  reading the water, a tension bar, or following the fish's pull with the joystick. **Tuning left
  for build time:** window sizes, ring speed, and how much smaller a rare fish's window is (as data).
- ✅ **U-5 — The companion's part: it keeps you company.** *(Decided 2026-11-10, "for now.")* While
  you fish, the companion sits beside you, watches the water, perks up on a bite, and is delighted
  when you land one. It has **no mechanical effect**: no form-based hints, no bond-based help. Parked
  for later, not rejected: form-based help (a cat pointing at fish, a bird spotting shadows, a fox
  nosing the bobber before a bite) and bond making those hints better.
- ✅ **U-6 — Where you can fish: anywhere there is water.** *(Decided 2026-11-10.)* The rod works
  in any water in every world from the start, not in a couple of pilot worlds first. A world can
  **opt out** where fishing would get in the way (see U-10), but none is excluded by default.
  **Stillglass is not excluded:** the owner doesn't think the mirror lake necessarily needs to be
  off-limits. How fishing sits beside its reflection secret is a detail for build time. Each world's
  water needs its own catches, or a sensible default set (U-7, U-10).
- ✅ **U-7 — What fishing pays.** *(Decided 2026-11-10.)*
  - **Common fish sell for coins** at a shop: fishing is a steady, calm source of coins.
  - **Some catches are materials** (things reeled up, like shells, sea-glass or an old boot) that
    can be traded between players, and later used in crafting (U-11). Each world's water yields
    different ones, which gives players reasons to trade.
  - **Rare fish go in a tank in your home**, on display for you and visiting friends.
  - **Not in the journal:** catches are not logged as journal entries.
  - **Every catch goes into your inventory** *(decided 2026-11-11)*: fish and materials are ordinary
    owned items, so they can be sold, traded or (rare fish) put in the tank from there.
  **Still to decide:** what the tank looks like and how it fits the home's layout; whether a rare
  fish can also be sold or traded instead of kept; and the actual fish and materials for each world.
- 🔶 **U-8 — How you get the rod: a free starter rod, on a post in the Vale.** *(Decided
  2026-11-10.)* Every player gets a plain rod for free, so fishing is something anyone can try from
  day one; the pilot needs no shop and no crafting. The rod rests on a post at a small fishing spot by
  a Vale pond; you pick it up, and that is how you find out fishing exists. Not chosen: having it
  silently in your bag from the start. **Still to decide:** which pond and what the spot looks like;
  whether the post stays empty once you've taken yours (it is personal, so a friend still sees theirs);
  and whether to have better rods later (bought at the bazaar, eventually crafted) and what "better"
  would mean. Better rods were suggested but not decided.
- ✅ **U-9 — Using an item: a hotbar plus a use button.** *(Decided 2026-11-10.)* Like
  Minecraft's hotbar: a row of **slots** where you put your frequently used items. **One slot is
  selected**, and that is the item you use; tap another slot to switch. A **use-item button** sits on
  the right, beside the companion button, and uses whatever is selected (with the rod: cast toward
  the water, then tap again when the timing ring lines up). Built as the general mechanism, so the
  rod is the first of many items, not a one-off. Not chosen: tapping the water to cast (it would
  clash with tap-to-move and tap-to-order), or a single held-item button with no slots.
  - **5 slots**, room to grow without crowding a phone screen.
  - **Bottom centre, small and low**, between the joystick (left) and the companion and use
    buttons (right).
  - A newly picked-up item **drops into the first free slot by itself**, so the starter rod is
    ready the moment you take it. A **bag screen** (from the gear menu) rearranges slots.
  - The use button always shows the selected item's icon. When there's nothing to use it on it
    **dims**, and tapping it explains (e.g. "Find some water to fish in").
  - **Keyboard:** number keys **1–5** switch slots; **F** uses the selected item.
- ⬜ **U-10 — Worlds declare what they allow.** How a world spec says "fishing works here, with these
  catches" (and later, "no lights here"), as data in the world seed. With U-6 decided, the shape is
  set: fishing is **on by default**, worlds **opt out** and **name their own catches**, and worlds
  that name none get a default set. Still open: the exact data format.
- ⬜ **U-11 — Materials and crafting.** Which materials exist, which worlds yield them, and how a
  recipe works. Probably *after* the rod, unless U-8 picks crafting for the rod.
- 🔶 **U-12 — Shops: a fish buyer in the bazaar.** *(Decided 2026-11-11.)* You sell fish from your
  inventory to a **different shopkeeper in the bazaar**, not the one who sells dyes. Not chosen: a
  fishmonger in the Vale by the fishing spot, or selling from anywhere through the bag. **Still to
  decide:** whether other worlds get their own shops later. (Who, where, prices and what they buy were
  settled 2026-11-11 and built in step 2, below.)
- ✅ **U-13 — Being seen: yes.** *(Decided 2026-11-10.)* Friends see what you hold and what you
  do with it: the rod in your hand, the cast, and the catch, so fishing beside a friend feels shared.
  What you hold is relayed with each player's state (one more field), like the companion's form.
- ⬜ **U-14 — What comes after the rod.** Which item is second, from the candidates above.

---

## The first build (scope agreed 2026-11-11)

The smallest end-to-end slice of fishing:

- The **starter rod** on a post by a Vale pond (U-8), dropping into the **hotbar** (U-9).
- **Fishing in any water** in any world, with the **timing ring** (U-4, U-6); the companion keeps
  you company (U-5); friends see the rod, the cast and the catch (U-13).
- **One default set of common fish** that every water uses, a **short list of rare fish**, and a
  couple of reeled-up **materials** (e.g. an old boot, sea-glass). Every catch goes into your
  inventory (U-7).
- **Selling** to a new **fish buyer in the bazaar** (U-12).
- **The tank** at your home, for rare fish (U-7).

**Later, not in the first build:** each world's own fish (a few worlds at a time), crafting (U-11),
better rods, the second item (U-14).

### Details agreed for the first build (2026-11-11)

- **The tank (step 3):** a glass tank at your home that you walk up to and tap. It shows your rare fish
  from your inventory, and you choose which ones swim in it. A fish in the tank leaves your inventory, and
  you can take it back out. Rare fish not in the tank stay sellable and tradeable.
- **The fish buyer (step 2):** a stall in the bazaar with a weathered awning and a barrel of ice. Buys
  common fish and materials, but **not rare fish**. Common fish sell for **2–8 coins** (a dye costs 30–60,
  so a few minutes of fishing earns about one dye). A starting price, to tune after playing.
- **The fishing spot:** a small pond in the Vale near where you arrive, with a wooden post holding the rod.
  Once you've taken the rod, the post is empty **for you only**; everyone else still sees a rod waiting.
- **Built in three steps,** each played before the next: (1) fishing itself, (2) selling, (3) the tank.

### Step 1, fishing itself: built (2026-11-11)

**Server** (`server/lib/server/`):
- `fishing.ex` (`Server.Fishing`): the rod (item 10, a `"tool"`) and the default catches: five common
  fish (200–204), three rare fish (220–222) and two materials (old boot, sea-glass; 240–241), each with a
  roll weight, a timing-ring difficulty (window and speed) and a sell price (common fish and materials
  only; selling itself is step 2). About 5% of casts hook a rare fish and 9% a material. Seeded with the
  other item definitions.
- `hotbar.ex` (`Server.Hotbar`) + migration `create_hotbars`: 5 slots per player, saved server-side. A new
  usable item drops into the first free slot.
- `economy.ex`: `grant_stack/4` (a catch adds onto the one stack of that kind you hold), plus
  `owned_quantity/2` and `inventory_summary/1`.
- `world_channel.ex`: pushes `inventory` and `hotbar` on every join; `take_rod` (only while standing at a
  prop with `"gives": "rod"`, and only once), `cast` (needs a rod and a world that allows fishing, at most one
  per second; the server rolls the catch and the wait and tells the client only the wait and the ring's
  difficulty), `reel` (grants the catch only for a landed reel after the bite and before the ring could have
  run out). What you hold and your fishing (`held`, `fishing`) are relayed with your identity, validated.
- The Vale (`priv/world_seeds/vale.json`): a small new pond just south-east of the spawn, and the
  `rod_post` prop at its edge.
- Tests: `test/fishing_test.exs`, `test/fishing_channel_test.exs`.

**Client** (`pokepals/scripts/`):
- `world/fishing_ring.gd` (`FishingRing`, pure, tested): the timing ring. A ring closes on the bobber over
  1.4 s / speed, meets the target circle 70% of the way through, and a tap within the window lands it. Two
  passes, then the fish swims off. The first tap decides.
- `world/fishing_water.gd` (`FishingWater`, pure, tested): where the water is (ponds, a single pond, the
  Riverbank's river, plus water a world adds, which is Ebbmere's tide) and where a cast lands: the way you
  face first, else the nearest water within reach all around (18–96 px).
- `presentation/hotbar.gd` (`Hotbar`), `presentation/use_button.gd` (`UseButton`), `presentation/item_icon.gd`
  (`ItemIcon`, procedural pictures of the rod and the catches, no art yet).
- `presentation/rod_view.gd` (`RodView`): the rod in hand, the cast, the line, the bobber, the bite (a dip,
  ripples, a "!" over your head), the timing ring (yours only) and the catch rising out of the water. Used
  for friends too.
- `presentation/mechanics/fishing_director.gd` (`FishingDirector`): ties it together. The companion keeps you
  company (it watches the bobber, glances at the bite, is delighted at a catch). Walking off reels the line in.
- `net/net.gd`, `presence_director.gd` (`set_activity`, and friends' rods), `world_controller.gd` (the HUD,
  keys **1–5** and **F**, the post), `world_art.gd` (the post), `companion_radial.gd` (`chip_rect`),
  `player_controller.gd` (`look_toward`).
- Tests: `tests/test_fishing.gd` (unit) and `tests/smoke_fishing.gd` (plays a whole catch in the real Vale
  scene, the server's side played by hand: the post, the hotbar, a cast, the ring, a catch, a miss, walking
  off, switching slots, a friend's rod and catch).

**Not in step 1:** the bag screen (rearranging slots, seeing everything you carry), selling (step 2), the
tank (step 3), per-world catches.

### First play (2026-11-12) and tuning

Picking up the rod and fishing worked well. It felt **too easy**: bites came quickly and the ring was easy
to land. Tuned in `Server.Fishing` (the server tells the client how hard each ring is, so no client change):
- **The wait** before a bite: 1.8-5.2 s became **3-8 s**.
- **The ring:** every window narrower and every ring quicker. A common fish's tap window went from about
  0.37 s to 0.15-0.21 s; a rare fish's to about 0.08-0.1 s. Still two passes before it swims off.
- **Sell prices** spread to the agreed 2-8 coins: minnow 2, perch 3, loach 4, bream 6, carp 8; old boot 1,
  sea-glass 5.

### Step 2, selling (and the bag): built (2026-11-12)

Decided 2026-11-12: build **the bag** first (there was nowhere to see your catches), then the fish buyer,
with both **Sell 1** and **Sell all** for each kind.

- **The bag** (`BagPanel`, gear menu → Bag): everything you carry with how many of each, grouped as Tools,
  Fish, Rare fish, and Odds and ends. Read-only; rearranging the hotbar comes once there's more than one
  tool.
- **The fishmonger** in the bazaar: the stall nearest where you arrive (about 140 px away) became the
  fishmonger's stall (`fish_stall`, a weathered awning, fish on the counter, a barrel of ice) and its
  stallholder the fish buyer (`"buys": "fish"`), both in `tools/gen_bazaar.py` so nothing else in the lane
  moved. Examine them to open their window (`FishBuyerPanel`): what they buy with the price each, **Sell 1**,
  and **Sell all (N coins)** when you hold more than one; rare fish listed apart, as yours to keep; your coins.
- **Server:** `Economy.sell/4` (one transaction: the stacks drawn down oldest first, the coins minted, both
  ledgered under one correlation id; refuses rare fish, unknown items, a bad quantity, or more than you
  hold), and the channel's `sell` (only while you stand at a stall that buys fish; answers `sold` + the fresh
  `inventory`, or `sell_failed`). The inventory snapshot now carries each item's sell price.
- **Tests:** server `test/fishing_test.exs` and `test/fishing_channel_test.exs` (selling one, all, across
  stacks, refusals, only at the stall); client `tests/smoke_fish_buyer.gd` (the Bazaar's fishmonger, their
  window, a sale, the bag).

**Next: step 3, the tank** at home for rare fish (details agreed above).

### Step 3, the tank: built (2026-11-12)

Decided 2026-11-12 (all as suggested): the tank stands **by the journal**; it holds **3** fish; they
**swim** behind the glass with bubbles rising; **friends see it** and can look in, only you change it; your
**companion wanders over to watch** now and then; a fish **taken out goes back to your bag**.

- **Server:** `Server.Tank` (put a rare fish in, take one out; each move is one transaction through
  `Economy.consume/4` or `Economy.grant_stack/4`, ledgered, together with the tank's contents, so a fish is
  always in exactly one place; only rare fish; full at 3). The home's record gains a `tank` column
  (migration `add_tank_to_homes`, `Homes.set_tank/2`). The home's spec carries `home.tank` (what's
  swimming) and `home.tank_capacity`; the template (`priv/home/home.json`) gains the `home_tank` prop
  (`"tank": true`) beside the journal. The channel's `tank_put` / `tank_take` work only in your own home;
  everyone there gets the new contents (`tank`, broadcast); refusals answer `tank_failed`.
  `Economy.sell/4` and `consume/4` now share one draw-down.
- **Client:** `TankView` (the glass tank, water, sand, weed, fish swimming back and forth, bubbles; a
  y-sorted node), `TankPanel` (yours: Take out for each fish, Put in for each rare fish you carry while
  there's room; a friend's: look only), `TankDirector` (places it from the spec, keeps it current from the
  broadcast, opens the window, sends the companion over to watch every 40-80 s while you're nearby).
- **Tests:** server `test/tank_test.exs`, `test/tank_channel_test.exs`; client `tests/smoke_tank.gd`.

With step 3 the **first build of fishing is complete**. Open next: **U-11** (materials and crafting: what
the old boots and sea-glass are for) and **U-14** (the second usable item).

### Crafting (U-11) and the second item, the lantern (U-14): built (2026-11-13)

Decided 2026-11-13 (the owner's idea, details as suggested): you can **craft a lantern** at a **tinker** in the
bazaar from **one sea-glass, one firefly and one piece of wood**.
- **Fireflies** gather in **Dozewood** (a forest at a long dusk): three glades. Stand in one with an **empty
  hand** and the use button becomes an open jar; tap it and a firefly comes along (gently: it chooses to stay).
- **Wood** is **driftwood**, reeled up while fishing like the boot and the sea-glass, so crafting feeds back
  into fishing. (Sea-glass came up more often too: weight 3 -> 5.)
- **The tinker** is one of the bazaar's lantern-makers, at the stall across the lane from the fishmonger. Her
  window lists what she can make, ticks off what you have of what it takes, and has a **Craft** button. She
  charges **10 coins** on top of the materials.
- **The lantern** goes on your hotbar. While it's selected you carry it lit: in **Underroot** and
  **Steamhollow's fog** it clears a big warm pocket round you (130 px, against 40-50 px of clear view; a
  world's fog can set `lantern_radius`); everywhere else it's a soft warm glow. Friends see it, and their
  lanterns light the dark round them too. It never runs out, and it's never needed.
- **You can craft more than one** (a spare to trade or give).

Built:
- **Server:** `Server.Crafting` (the recipe, the lantern (item 4, now a real `"tool"` with `"use": "light"`)
  and the firefly (250); one transaction per craft: each material consumed, the fee sunk, the lantern
  granted and put on the hotbar, all ledgered; `at_crafter?`, `at_firefly_glade?`). Driftwood (242) added to
  `Server.Fishing`'s catches. The channel pushes `recipes` on join and answers `craft` (only at a stall with
  `"crafts": true`) and `catch_firefly` (only in one of this world's `firefly_glades`, one every 4 s).
- **Worlds:** `tools/gen_dozewood_world.py` adds `firefly_glades` (by the landing, over the toadstool ring, by
  the lantern log); `tools/gen_bazaar.py` turns the lantern-maker across from the fishmonger into the tinker
  (`crafter`, `"crafts": true`) and her stall into `tinker_stall`. Nothing else moved in either world.
- **Client:** `CrafterPanel`, `FireflyDirector` (+ its `FireflyGlade` drift), `LanternView` (yours and
  friends'), `ItemIcon` gains the lantern, firefly, driftwood and jar; `FishingDirector` handles the lantern
  and the empty hand's jar; `world_controller._mist_pockets` adds the lanterns' light to the fog.
- **Tests:** server `test/crafting_test.exs`, `test/crafting_channel_test.exs`; client
  `tests/smoke_crafting.gd` (the tinker, a craft, carrying the lantern, its light, a friend's),
  `tests/smoke_fireflies.gd` (the glades and the jar).

### The firefly jar (2026-11-13, after the first play)

The empty-hand jar on the use button was **too hidden**. Changed, as the owner asked:
- Each glade has a **glass jar on a little table** (a `firefly_jar_table` prop, `"firefly_jar": true`, added in
  `tools/gen_dozewood_world.py` after the layout so nothing else moved). **Examine it** and a short **cutscene**
  plays: your steering rests a moment, a firefly drifts down out of the glade into the jar, the jar glows, and the
  firefly is in your bag (`FireflyDirector.examine_jar`, `FireflyGlade.fly_one_into`). The use button no longer
  does anything with an empty hand.
- **One firefly at a time:** you can carry only one (`Crafting.firefly_room?/1`, checked by the server on
  `catch_firefly`; the client checks first so the cutscene never plays for nothing). Once it's in a lantern,
  another will come. This replaces the few-seconds cooldown.

### The lantern's light, and the hotbar across portals (2026-11-13, after the first play)

- **The lantern changed nothing you could see.** Its light was a moving "pocket" in the fog, and a pocket fades
  from full at its centre to nothing at its edge, so even a 130 px one only thinned a small core. (Rendered
  screenshots, Godot under Xvfb, showed a faint warm haze and the dark as close as ever.) Now **your own
  lantern widens your own clear circle**: `MistVeil.set_lantern`, easing in over about half a second, takes it
  from the world's `clear_radius` / `fade_radius` to `lantern_clear` / `lantern_fade` (defaults: max(130, 2.6 x
  clear) and fade + 120; Underroot 52 -> 135 px clear, Steamhollow 40 -> 130), and the mist round you glows
  lamp-gold (`lantern_color`, shader `lamp` / `lamp_color`). **Friends' lanterns** stay pockets, but bigger (220
  px, `lantern_radius`).
- **The hotbar selection reset on every portal** (the world, and the director that held the selection, are
  rebuilt on every hop). The selected slot now lives in `Net.hotbar_selected` for the session, so the item in
  your hand stays in your hand from world to world.
- **Test:** `tests/smoke_lantern.gd` (Underroot: the dark pushed back and closing in again; the lantern still in
  hand and lit after a world rebuild).

