defmodule Server.Seeds do
  @moduledoc """
  Idempotent seed data, callable from both `mix run priv/repo/seeds.exs` (dev) and the packaged
  release via `Server.Release.seed/0` (Docker/prod, where Mix is unavailable).

  The SEED WORLDS are essential bootstrap content, not just demo data: the client can't enter a world
  that isn't in the catalog, so a fresh server must have them. The item definitions + demo account are
  convenience dev data (harmless, idempotent).
  """
  alias Server.{Accounts, Economy, ItemDefinition, Repo, Saves, Worlds}

  # Fixed ids for the seed worlds — must match the client (WorldRouter.VALE_ID / RIVERBANK_ID / BAZAAR_ID).
  # Each also carries its DIRECTORY card — what the Vale's Gateway lists + searches (blurb, tags,
  # accent colour, featured). The Vale is the hub you search FROM, so it stays unlisted.
  @seed_worlds [
    %{world_id: "11111111-1111-1111-1111-111111111111", slug: "vale", name: "The Vale", file: "vale.json",
      listed: false, blurb: "The meadow everyone comes home to.", tags: ["hub", "meadow"], accent: [0.74, 0.66, 0.96]},
    %{world_id: "22222222-2222-2222-2222-222222222222", slug: "riverbank", name: "The Riverbank", file: "riverbank.json",
      blurb: "Turn over river stones with your companion and see who's hiding underneath.",
      tags: ["river", "search", "salamanders"], accent: [0.66, 0.8, 0.96]},
    %{world_id: "33333333-3333-3333-3333-333333333333", slug: "bazaar", name: "The Bazaar", file: "bazaar.json",
      blurb: "A sun-warmed market of a thousand knots — dyes, wanderers, and trading with friends.",
      tags: ["market", "shop", "trade", "colours"], accent: [0.96, 0.82, 0.5]},
    %{world_id: "44444444-4444-4444-4444-444444444444", slug: "the-ruin", name: "The Ruin", file: "the-ruin.json",
      blurb: "An overgrown ruin whose doors only open when companions work together.",
      tags: ["puzzle", "co-op", "ancient"], accent: [0.55, 0.7, 0.55], featured: true},
    %{world_id: "55555555-5555-5555-5555-555555555555", slug: "maze", name: "The Hedge Maze", file: "maze.json",
      blurb: "Tall green walls and a quiet heart. Your companion knows the way.",
      tags: ["maze", "explore", "hedges"], accent: [0.46, 0.66, 0.42]},
    %{world_id: "66666666-6666-6666-6666-666666666666", slug: "nocthollow", name: "Nocthollow", file: "nocthollow.json",
      blurb: "A night that never ends, and a world that glows to fill it. Wander among living light and strange, gentle creatures.",
      tags: ["night", "glow", "explore", "creatures", "otherworld"], accent: [0.45, 0.85, 1.0], featured: true},
    %{world_id: "77777777-7777-7777-7777-777777777777", slug: "bobbledown", name: "Bobbledown", file: "bobbledown.json",
      blurb: "A soft, round world breathed by a sleeping giant. Gumdrop hills, fizzing water, and creatures that bounce.",
      tags: ["round", "soft", "bubbles", "explore", "creatures", "otherworld"], accent: [1.0, 0.72, 0.88], featured: true},
    %{world_id: "88888888-8888-8888-8888-888888888888", slug: "clickton", name: "Clickton", file: "clickton.json",
      blurb: "A little city built entirely of small colourful bricks, you and your companion included. Look low down.",
      tags: ["city", "bricks", "toys", "explore", "cozy", "secret"], accent: [0.96, 0.78, 0.18], featured: true},
    %{world_id: "99999999-9999-9999-9999-999999999999", slug: "drifthallow", name: "Drifthallow", file: "drifthallow.json",
      blurb: "A snowfield at blue hour. Deep, untouched snow, frozen birches, and footprints that fill back in. Something small has left tracks only a fox could follow.",
      tags: ["snow", "winter", "quiet", "explore", "cozy", "secret"], accent: [0.66, 0.78, 1.0], featured: true},
    %{world_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", slug: "dozewood", name: "Dozewood", file: "dozewood.json",
      blurb: "A drowsy forest at a long lilac dusk. Mossy hollows, hammocks, slow lamps. Everything moves at half speed, and yawns are catching. Somewhere your companion dreams of.",
      tags: ["forest", "sleepy", "quiet", "explore", "cozy", "secret"], accent: [0.78, 0.74, 1.0], featured: true},
    %{world_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", slug: "steamhollow", name: "Steamhollow", file: "steamhollow.json",
      blurb: "A bathhouse village lost in fog. Boardwalks, hot springs and paper lanterns, and a bell too faint for you to hear.",
      tags: ["fog", "hot-springs", "lanterns", "quiet", "explore", "cozy", "secret"], accent: [1.0, 0.80, 0.52], featured: true},
    %{world_id: "dddddddd-dddd-dddd-dddd-dddddddddddd", slug: "hollowsong", name: "Hollowsong", file: "hollowsong.json",
      blurb: "An echo canyon at sunset. Banded red cliffs, wind-carved arches and a dry riverbed, where every voice comes back as a ripple. One answer comes from the wrong place.",
      tags: ["canyon", "echo", "sunset", "wolf", "explore", "cozy", "secret"], accent: [1.0, 0.70, 0.44], featured: true},
    %{world_id: "cccccccc-cccc-cccc-cccc-cccccccccccc", slug: "underroot", name: "Underroot", file: "underroot.json",
      blurb: "Caves beneath the great tree: root tunnels, glow-moss and slow dripping water, so dark you see only a small circle of light. Let your companion go first, and follow.",
      tags: ["caves", "dark", "roots", "glow", "quiet", "explore", "cozy", "secret"], accent: [0.50, 0.95, 0.72], featured: true},
    %{world_id: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", slug: "lanternfold", name: "Lanternfold", file: "lanternfold.json",
      blurb: "A shadow-puppet world cut from paper, all lit by one great lantern. Everything casts a shadow on the cliff, and the mural there is missing a bird.",
      tags: ["paper", "shadow", "lantern", "amber", "quiet", "explore", "cozy", "secret"], accent: [1.0, 0.76, 0.34], featured: true}
  ]

  # The currency the bazaar shop charges in.
  @color_price_currency "coins"

  # The shop's stock: COLOR cosmetics the bazaar shopkeeper sells. category "color" is what marks a def
  # purchasable (Economy.purchase refuses anything else); base_attributes carries the color_slot it
  # recolors, the named ramp, a display swatch [r,g,b], and the price (in "coins"). Buying grants the
  # def into the player's wardrobe — the "stored choice". (The recolor render itself is still deferred.)
  @item_defs [
    %{item_def_id: 1, name: "Straw Hat", category: "cosmetic", slot: "head", stackable: false},
    %{item_def_id: 2, name: "Woven Scarf", category: "cosmetic", slot: "neck", stackable: false},
    %{item_def_id: 3, name: "River Pebble", category: "trinket", slot: nil, stackable: true},
    %{item_def_id: 4, name: "Lantern", category: "tool", slot: "hand", stackable: false},
    %{item_def_id: 100, name: "Rose Blush", category: "color", slot: nil, stackable: false,
      base_attributes: %{"color_slot" => "skin_tone", "ramp" => "rose", "swatch" => [0.96, 0.74, 0.74], "price" => 30, "currency" => "coins"}},
    %{item_def_id: 101, name: "River Teal", category: "color", slot: nil, stackable: false,
      base_attributes: %{"color_slot" => "hair_color", "ramp" => "teal", "swatch" => [0.30, 0.66, 0.66], "price" => 45, "currency" => "coins"}},
    %{item_def_id: 102, name: "Marigold", category: "color", slot: nil, stackable: false,
      base_attributes: %{"color_slot" => "hair_color", "ramp" => "marigold", "swatch" => [0.96, 0.74, 0.30], "price" => 45, "currency" => "coins"}},
    %{item_def_id: 103, name: "Plum", category: "color", slot: nil, stackable: false,
      base_attributes: %{"color_slot" => "hair_color", "ramp" => "plum", "swatch" => [0.55, 0.35, 0.62], "price" => 60, "currency" => "coins"}},
    %{item_def_id: 104, name: "Slate", category: "color", slot: nil, stackable: false,
      base_attributes: %{"color_slot" => "skin_tone", "ramp" => "slate", "swatch" => [0.55, 0.60, 0.66], "price" => 60, "currency" => "coins"}}
  ]

  @doc "Run all seeds (idempotent). Returns a short summary string."
  def run do
    seed_item_definitions()
    seed_demo_account()
    seed_worlds()

    summary =
      "Seeded #{length(@item_defs)} item definitions, #{length(@seed_worlds)} worlds, and the demo account."

    summary
  end

  defp seed_item_definitions do
    for attrs <- @item_defs do
      %ItemDefinition{}
      |> ItemDefinition.changeset(attrs)
      |> Repo.insert!(
        on_conflict: {:replace, [:name, :category, :slot, :stackable, :base_attributes]},
        conflict_target: :item_def_id
      )
    end
  end

  defp seed_demo_account do
    {:ok, demo} = Accounts.resolve_token("demo-token")
    {:ok, _} = Saves.store(demo.user_id, %{"bond" => 0.5}, %{"equipped" => %{}})
    # Top the demo wallet up to a known floor so it can always afford a few colors in the bazaar,
    # even on a re-seed of an existing account (resolve_token only gifts a brand-new one).
    if Economy.balance(demo.user_id, @color_price_currency) < 120 do
      Economy.grant_currency(demo.user_id, @color_price_currency, 120)
    end
  end

  defp seed_worlds do
    for %{file: file} = w <- @seed_worlds do
      core =
        :server
        |> Application.app_dir("priv/world_seeds/#{file}")
        |> File.read!()
        |> Jason.decode!()
        |> bake_border_trees()

      {:ok, _} =
        Worlds.upsert(%{
          world_id: w.world_id,
          slug: w.slug,
          name: w.name,
          display_types: ["2d"],
          version: 1,
          spec: %{"core" => core, "profiles" => %{"2d" => %{}}},
          visibility: "public",
          status: "active",
          blurb: Map.get(w, :blurb, ""),
          tags: Map.get(w, :tags, []),
          accent: Map.get(w, :accent),
          featured: Map.get(w, :featured, false),
          listed: Map.get(w, :listed, true)
        })
    end
  end

  # Generate the world's border treeline server-side and bake it into the spec as `border_trees` (the
  # server is the source of truth now — the client draws + collides against these exact points, and the
  # ambient-pal sim avoids them). Deterministic, so it doesn't churn the content etag across re-seeds.
  defp bake_border_trees(core) do
    trees = Server.WorldBorder.positions(Map.get(core, "bounds"), Map.get(core, "border", %{}))
    Map.put(core, "border_trees", trees)
  end
end
