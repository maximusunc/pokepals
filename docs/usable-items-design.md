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


### The fireflies move to the end of the dark worlds (2026-11-13)

Decided by the owner: fireflies (and so lanterns) are a **reward for getting through a dark world once**, making
the second pass easier. Dozewood's three glades are **gone**. There is now **one glade, with its jar, beside the
secret** at the end of each of the two dark worlds:
- **Steamhollow:** just north of the bronze bell, across from the bellkeeper's stool (`tools/gen_steamhollow_world.py`).
- **Underroot:** at the edge of the Heartwood, by the root-heart (`tools/gen_underroot_world.py`).

Gating is **placement only**: anyone who reaches the jar can take a firefly (a friend who leads you there gets you
one too, but you're then standing at the secret and can claim it). The jar gives a **faint** pocket of light in the
fog / dark (`atmosphere.fog.lit.prop_types.firefly_jar_table`, radius 36, about a lantern's), so it glows a little
once you're close. Nothing else changed: the server still honours a catch only at a jar, one at a time.

---

## Home building: the axe, wood, and your house (built 2026-11-15)

Asked for by the owner (issue #141, then "go ahead and build this", 2026-11-15). What the owner decided:
- **The axe** takes **3 driftwood and 2 stones**, both picked up on **the Riverbank**. The tinker in the bazaar makes it.
- With the axe you can **chop trees in every world except the Vale**. Chopping is **instant for now, configurable**.
- A tree gives **2 wood** and **grows back after 5 minutes**.
- **The carpenter** in the bazaar builds your house for **100 wood and 300 coins**. Once paid, she shows up at your
  home working on a house in progress. It takes **10 minutes, configurable**.
- The house is **fairly large**, in the **north of your home**, and **you can go inside**. It's homey (a kitchen, a
  couch, a fireplace, a living room...), and **the secrets you've found move in**, on display in different places.

### How it plays

1. **Stones and driftwood.** Six little heaps of river stones and five pieces of driftwood lie on the Riverbank, at
   the water's edge (the spec's `pickups`). Examine one and it's yours. It's gone **for everyone there** until it
   washes back (3 minutes). Driftwood still comes up while fishing too.
2. **The axe.** The tinker's window now lists it under the lantern: 3 driftwood + 2 river stones, **no fee**. It goes on
   your hotbar. Selected, you carry it over your shoulder (friends see it).
3. **Chopping.** Stand beside a tree and tap **Use** (or F): you turn to it and swing, and it topples with a puff of
   leaves, leaving a stump; **+2 wood**. The stump is shared: everyone in that world sees it, until the tree grows back
   up out of it 5 minutes later. The use button dims when there's no tree in reach. **Not in the Vale or any home**
   (`"chopping": false`), and only trees that are wood: not Thimblewick's fence pickets (its secret's gaps) or flower
   stalks, not crystal spires, glow-flowers, sweets, stone pillars or giant mushrooms.
4. **The carpenter.** The stallholder next to the tinker became the carpenter (a stall with planks, a saw and a little
   sample house). Her window shows the wood and coins she asks for against what you have, a **Build my house** button
   once you have it all, and tells you where wood comes from. Once paid, it says how the build is going.
5. **Being built.** At home, the glade has **widened north** and the house is going up there: the floor is down and a
   timber frame rises over the 10 minutes (posts, then beams, boards climbing the walls, rafters), with scaffolding, a
   stack of planks that shrinks, sawhorses, and a sign with the minutes left. **The carpenter is there** (dressed as in
   the bazaar), walking round the frame and hammering; examine her for how long is left. If you're there when the time
   is up, it's **finished in front of you**.
6. **The house.** A big cottage (560 x 220 px): plaster and timber, a stone plinth, six windows with shutters and
   flower boxes, a green door with a lamp, a shingled roof, a chimney that smokes. Walk in through the door and the
   roof and front wall lift away (a **cutaway**, like a doll's house; the camera keeps the whole room in view):
   - **Kitchen:** a tiled floor; a counter with a sink, bread and fruit; an iron stove with a pot steaming; a table
     with four chairs, flowers and plates; jars on shelves, pans on a rail, a window with curtains.
   - **Living room:** a fireplace with a crackling fire and candles on the mantel; a red rug; two armchairs; a coffee
     table with a teapot; a couch facing the fire with a knitted throw; a bookshelf; a floor lamp; paintings.
   - **Bedroom:** a big bed with a patchwork quilt; two nightstands with candles; a wardrobe; a chest at the bed's foot;
     a blue rug; a clock with a swinging pendulum.
   - **Your finds:** the keepsakes your companion chose stand on **display plinths** (the favourite by the fire, one
     either side of it, one in the kitchen, one in the bedroom, side tables in the living room's front corners, the chest), and **every other
     find** sits on **curio shelves** along the walls, spread from room to room. A find your companion later picks as a
     keepsake leaves its shelf for a plinth. The journal holds them all, as before.
   Friends see the same house (and the same build) when they visit.

### Tunables (all configurable without a client build)

Server config (`server/config/config.exs`), each also settable when the server boots, in seconds, from the
environment (`server/config/runtime.exs`):

| Setting | Default | Env var |
|---|---|---|
| How long a chop takes (`Server.Harvest` `chop_ms`; 0 = one swing) | 0 | `CHOP_SECONDS` |
| A felled tree grows back (`tree_regrow_ms`) | 5 min | `TREE_REGROW_SECONDS` |
| A stone / driftwood comes back (`pickup_regrow_ms`) | 3 min | `PICKUP_REGROW_SECONDS` |
| Wood per tree (`wood_per_tree`) | 2 | `WOOD_PER_TREE` |
| The house's build time (`Server.House` `build_ms`) | 10 min | `HOUSE_BUILD_SECONDS` |
| What the carpenter asks (`wood`, `coins`) | 100, 300 | `HOUSE_WOOD`, `HOUSE_COINS` |

A house's state is worked out from when she started and the **current** build time, so changing it applies at once,
even to a house already going up. With `chop_ms` above 0 the client swings for that long (the crown shivers at each
bite) and the server honours the chop only that long after you started on that very tree.

### Built

**Server** (`server/lib/server/`):
- `harvest.ex` (`Server.Harvest`): the axe (item 11, a `"tool"`, `"use": "chop"`), River Stone (243) and Wood (244),
  materials; the rules (`check_tree/3`, `check_pickup/3`, `chopping_allowed?/1`, `wood_kind?/1`, `chop_ripe?/3`); and
  the shared felled / taken state: an ETS table owned by this process (`{world_id, node} => regrow_at`), so it outlives
  a world process; `take/3` is a call, so two players can't both have one tree. Forgotten on a restart (everything has
  grown back). A tree's node is `"t<index>"` in its spec's `trees`; a pickup's is its id.
- `house.ex` (`Server.House`): `commission/1` (one transaction: 100 wood consumed, 300 coins sunk, the house started,
  ledgered), `status/1`, `state/2`, `at_carpenter?/2`. Stored as `homes.house` (`%{"started_at" => unix_ms}`;
  migration `add_house_to_homes`, `Homes.set_house/2`).
- `crafting.ex`: the axe recipe. `home_world.ex`: once a house exists, the glade widens north by `extend_north`
  and the house stands there as a building (`"view": "house"`) whose `solid_rects` are its walls (and, once built, its
  furniture), its floors as `plates` (and, once built, its rugs, plinths and shelves), a path to the door; a built
  house's keepsake spots are its display spots and every other find goes on its curio spots (`curio` props).
- `world_channel.ex`: pushes `harvest` (what's down here, how long until each grows back, `chop_ms`) and `house`
  (your house's status and price) on every join; handles `chop` (and `chop_start`), `gather` and `commission_house`.
  A felled tree or a taken pickup is broadcast (`harvested`); the gatherer gets `harvest_got` and the fresh
  `inventory`, or `harvest_refused`.
- Worlds: the Riverbank's `pickups` (hand-placed in `priv/world_seeds/riverbank.json`), the Vale's `"chopping": false`,
  the bazaar's carpenter (`tools/gen_bazaar.py`: the stallholder nearest the tinker, her stall `carpenter_stall`,
  `"builds": "house"`), and the home template's `house` block and `"chopping": false` (`tools/gen_home_house.py`,
  which documents the layout: three rooms side by side, so every inner wall runs north-south and the cutaway reads
  cleanly).
- Tests: `test/harvest_test.exs`, `test/harvest_channel_test.exs`, `test/house_test.exs`, `test/home_house_test.exs`.

**Client** (`pokepals/scripts/`):
- `presentation/mechanics/harvest_director.gd` (`HarvestDirector`, with its `PickupView`): the axe's use, the target
  tree, timed chops, the pickups as examinable things, and the shared state (each felled tree and taken pickup comes
  back on its own timer from the server's figure). `FishingDirector` (the hotbar's owner) hands it the axe.
- `presentation/axe_view.gd` (`AxeView`): the axe over your shoulder and its swing, chips flying (also the
  carpenter's hammer). Friends' axes in `PresenceDirector`.
- `presentation/tree_view.gd`: a tree topples, leaves a stump, grows back; `Scenery.spec_tree(i)`.
- `presentation/carpenter_panel.gd` (`CarpenterPanel`).
- `presentation/house_view.gd` (`HouseView`, a `BuildingView`: the frame, the cottage, the cutaway),
  `house_back_wall.gd` (`HouseBackWall`), `house_furniture.gd` (`HouseFurniture`), and
  `mechanics/house_director.gd` (`HouseDirector`: the carpenter at work, finishing the house in front of you, moving
  your finds in). `WorldArt` draws the house's plates (floorboards, tiles, low walls, rugs, plinths, the chest,
  shelves) under the props, so your finds stand on them, and grows no grass or bushes on a floor. `CameraRig`
  `keep_top_in_view` keeps the back wall in frame inside.
- `ItemIcon`: the axe, a river stone, wood. `Net`: the new messages.
- Tests: `tests/smoke_harvest.gd` (the Riverbank: picking up, regrowing, the axe, felling, a friend's axe),
  `tests/smoke_carpenter.gd` (the bazaar), `tests/smoke_house.gd` (a home: the build, the carpenter, finishing,
  walking in and out), with fixtures `home_house_building.json` / `home_house_built.json` made by `Server.HomeWorld`.
  Checked with rendered screenshots (Godot under Xvfb) of the construction site, the cottage, and the cutaway inside.

### Choices made at build time (open for review)

- **Shared trees:** a felled tree is gone for everyone in that world until it grows back (not per player).
- **Pickups** come back after 3 minutes, also shared. Wood and stones **can't be sold** to the fishmonger (no price).
- **The axe has no fee** at the tinker (the lantern costs 10 coins).
- **Which trees are wood:** everything in a world's `trees` except a short list of kinds (`Server.Harvest`'s
  `@not_wood`, mirrored in `HarvestDirector.NOT_WOOD`). Stillglass's mirror lake keeps reflecting a tree you've felled on
  its north bank (its reflections are baked once); Lanternfold's paper trees can be chopped.
- **A stump still blocks** like the trunk did (so routing and collision don't change while a tree is down).
- **One house per player.** It isn't something you can rearrange (yet): the rooms, furniture and display spots are
  fixed by the template.
- **The cutaway** follows your own feet: friends inside look hidden under the roof from outside (as anyone behind a
  building is).

### After the first play (2026-11-15)

- **The doorway while it's being built** had a frame post (and the scaffold plank) right across it, so it looked
  blocked though it wasn't. No post or plank crosses the doorway now; a post stands either side of it instead.
- **The carpenter glided.** Her body was moved directly, so its walk cycle never played. Now she walks: a point is
  moved at walking pace and her body eases after it, like a friend's puppet.
- **You could get stuck inside.** The couch, two side tables and two low shelves sat just inside the front door with
  no gap a body fits through, so once the house finished (and the furniture walled in) you couldn't get in or out.
  The couch now stands further back, the side tables are in the living room's front corners, and the two shelves by
  the door moved to the kitchen's and the bedroom's front walls. `tools/gen_home_house.py` now checks, before it
  writes anything, that from outside the door you can walk into every room and up to every place a find stands (a
  flood fill with a body's clearance), and `tests/smoke_house.gd` walks in, round the couch and back out through the
  real collision. The server builds homes from the template on every visit, so houses already built get the new
  layout straight away.
- **Tests now run with a full house.** The house fixtures are made by `server/test/fixtures/gen_home_house_fixtures.exs`
  (the real `Server.HomeWorld`) for a player who has found every world's secret, with 7 keepsakes chosen: so every
  display plinth and curio shelf is taken. `tests/smoke_house.gd` checks all 17 move in, the keepsakes onto the
  plinths, and flood-fills from the doorstep through the real collision to check each one can be walked up to; the
  server's `home_house_test.exs` checks each stands inside, in a place of its own, and none in the doorway. Both fail
  on the old layout.

### Performance, and how the finds scale (2026-11-15)

**Performance.** The house drew everything live, every frame (thousands of little shapes for its shell, back wall
and floors), drew its outside while faded away, and drew the finds inside while you were outside. Its still parts are
now baked once into textures (`PaintBake`, a SubViewport rendered once, like `StaticBake`): the outside, the back
wall, the floors and rugs (in `WorldArt`), and every still piece of furniture. Only the smoke, the door lamp, the fire,
the stove, the lamp and the clock's pendulum stay live. The finds inside are hidden while you're outside. Measured
(software renderer, so only the comparisons mean anything): outside the house 512 -> 37 draw calls; inside 529 -> about
400 with a full showcase, about 20 per find on show (each is drawn shape by shape by `WorldArt`, as every keepsake
is). Baking each keepsake type into a sprite would cut that further; not done yet.

**How the finds scale** (decided by the owner, 2026-11-15: options 2 and 3 of those offered). The house never tries to
show every find:
- **A curated showcase:** the companion's **keepsakes** stand on the display plinths (up to 7, by bond, as before), and
  the **newest** of the other finds stand on the shelves, up to `curio_shown` (**8**, in the template's `house` block;
  the 8 was the suggested number), so new finds rotate in and older ones rotate out. At most 15 on show.
- **The curio cabinet:** a glass-fronted cabinet by the living room's west wall. Examine it (`CabinetPanel`) for every
  find you've ever made, newest first, each with its line and where it is ("On show: a keepsake", "On show: on a shelf",
  "In the cabinet"). A friend can look in yours.
- `Server.HomeWorld` picks the shelves' finds (newest first, not keepsakes); `HouseDirector` makes the same choice when
  a house finishes in front of you. Tested in `home_house_test.exs` and `tests/smoke_house.gd` (17 finds: 15 on show,
  all 17 in the cabinet).

### Where the house stands (2026-11-15)

Asked for by the owner: the house was too far north (it stood from the glade's north edge, which moves out as the bond
opens keepsake spots, so a well-bonded home put it a long way off). It now stands **by the pond, in line with the way
in**: its front door `door_from_pond` (140 px, about 10 yards) north of the pond's top edge, centred on x = 0 like the
portal home, and it doesn't move as the glade grows. The glade reaches north only as far as the house needs (its back
plus `from_north` for the treeline). The seventh keepsake spot in the glade (used only before a house is finished)
moved out of its way, and `home_house_test.exs` checks nothing in the glade stands where the house does, at any bond.

### The fish tank moves in (2026-11-15)

Asked for by the owner: once the house is built, the fish tank (which stood by the journal in the glade) stands in
the **living room**, on its east side by the armchair and the bookshelf (the template's `house.tank`, with its
collision the tank prop's own). `Server.HomeWorld` moves the tank prop there for a built house; `HouseDirector` moves
it (view, examine spot, collision) when the house finishes in front of you. Like the finds inside, it isn't drawn while
you're outside the house. Your companion still wanders over to watch the fish. Checked by the layout's flood fill,
`home_house_test.exs` and `tests/smoke_house.gd`.
