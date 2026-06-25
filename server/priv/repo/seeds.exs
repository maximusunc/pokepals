# Seed data for local development / smoke tests. Idempotent — run repeatedly:
#
#     mix run priv/repo/seeds.exs
#
# Seeds a handful of item definitions (the cozy, non-combat kind) plus a demo account + companion, so
# the economy has something to reference end to end. No currency/items are minted here — that's the
# game's job once it introduces them.

alias Server.{Accounts, ItemDefinition, Repo, Saves}

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

IO.puts("Seeded #{length(item_defs)} item definitions and demo account #{demo.user_id}.")
