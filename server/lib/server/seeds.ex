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
  @seed_worlds [
    %{world_id: "11111111-1111-1111-1111-111111111111", slug: "vale", name: "The Vale", file: "vale.json"},
    %{world_id: "22222222-2222-2222-2222-222222222222", slug: "riverbank", name: "The Riverbank", file: "riverbank.json"},
    %{world_id: "33333333-3333-3333-3333-333333333333", slug: "bazaar", name: "The Bazaar", file: "bazaar.json"},
    %{world_id: "44444444-4444-4444-4444-444444444444", slug: "the-ruin", name: "The Ruin", file: "the-ruin.json"}
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

      {:ok, _} =
        Worlds.upsert(%{
          world_id: w.world_id,
          slug: w.slug,
          name: w.name,
          display_types: ["2d"],
          version: 1,
          spec: %{"core" => core, "profiles" => %{"2d" => %{}}},
          visibility: "public",
          status: "active"
        })
    end
  end
end
