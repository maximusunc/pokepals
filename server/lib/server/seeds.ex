defmodule Server.Seeds do
  @moduledoc """
  Idempotent seed data, callable from both `mix run priv/repo/seeds.exs` (dev) and the packaged
  release via `Server.Release.seed/0` (Docker/prod, where Mix is unavailable).

  The SEED WORLDS are essential bootstrap content, not just demo data: the client can't enter a world
  that isn't in the catalog, so a fresh server must have them. The item definitions + demo account are
  convenience dev data (harmless, idempotent).
  """
  alias Server.{Accounts, ItemDefinition, Repo, Saves, Worlds}

  # Fixed ids for the seed worlds — must match the client (WorldRouter.VALE_ID / RIVERBANK_ID).
  @seed_worlds [
    %{world_id: "11111111-1111-1111-1111-111111111111", slug: "vale", name: "The Vale", file: "vale.json"},
    %{world_id: "22222222-2222-2222-2222-222222222222", slug: "riverbank", name: "The Riverbank", file: "riverbank.json"}
  ]

  @item_defs [
    %{item_def_id: 1, name: "Straw Hat", category: "cosmetic", slot: "head", stackable: false},
    %{item_def_id: 2, name: "Woven Scarf", category: "cosmetic", slot: "neck", stackable: false},
    %{item_def_id: 3, name: "River Pebble", category: "trinket", slot: nil, stackable: true},
    %{item_def_id: 4, name: "Lantern", category: "tool", slot: "hand", stackable: false}
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
