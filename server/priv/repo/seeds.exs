# Seed data for local development / smoke tests. Idempotent — run repeatedly:
#
#     mix run priv/repo/seeds.exs
#
# Seeds a handful of item definitions (the cozy, non-combat kind) plus a demo account + companion, so
# the economy has something to reference end to end. No currency/items are minted here — that's the
# game's job once it introduces them.

alias Server.{Accounts, ItemDefinition, Repo, Saves, Worlds}

item_defs = [
  %{item_def_id: 1, name: "Straw Hat", category: "cosmetic", slot: "head", stackable: false},
  %{item_def_id: 2, name: "Woven Scarf", category: "cosmetic", slot: "neck", stackable: false},
  %{item_def_id: 3, name: "River Pebble", category: "trinket", slot: nil, stackable: true},
  %{item_def_id: 4, name: "Lantern", category: "tool", slot: "hand", stackable: false}
]

for attrs <- item_defs do
  %ItemDefinition{}
  |> ItemDefinition.changeset(attrs)
  |> Repo.insert!(
    on_conflict: {:replace, [:name, :category, :slot, :stackable, :base_attributes]},
    conflict_target: :item_def_id
  )
end

{:ok, demo} = Accounts.resolve_token("demo-token")
{:ok, _} = Saves.store(demo.user_id, %{"bond" => 0.5}, %{"equipped" => %{}})

# ── World catalog ─────────────────────────────────────────────────────────────────────────────────
# The authored seed worlds, now SERVER-hosted. Their content lives in priv/world_seeds/*.json (the
# canonical copy; the Godot client ships the same files only as an offline first-paint fallback). We
# wrap each into the display-agnostic spec shape — core (semantic) + profiles (per display type, only
# "2d" today) — under a FIXED world_id so portals/clients can reference it stably.
seed_worlds = [
  %{world_id: "11111111-1111-1111-1111-111111111111", slug: "vale", name: "The Vale", file: "vale.json"},
  %{world_id: "22222222-2222-2222-2222-222222222222", slug: "riverbank", name: "The Riverbank", file: "riverbank.json"}
]

for %{file: file} = w <- seed_worlds do
  core = Application.app_dir(:server, "priv/world_seeds/#{file}") |> File.read!() |> Jason.decode!()

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

IO.puts(
  "Seeded #{length(item_defs)} item definitions, #{length(seed_worlds)} worlds, and demo account #{demo.user_id}."
)
