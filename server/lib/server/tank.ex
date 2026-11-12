defmodule Server.Tank do
  @moduledoc """
  The fish TANK at home (usable items, step 3; docs/usable-items-design.md): a glass tank by the journal
  where the owner chooses which of their RARE fish swim. It holds `capacity/0` fish.

  Putting a fish in takes it out of the owner's inventory, and taking it out puts it back; each move is one
  transaction through `Server.Economy` (ledgered) together with the tank's new contents
  (`Server.Homes.set_tank/2`), so a fish is always in exactly one place. Only rare fish go in (common fish
  are for selling). Anyone who can visit the home sees the tank; only its owner changes it (the channel
  checks that).
  """
  alias Server.{Economy, Homes, Repo}

  @capacity 3

  @doc "How many fish the tank holds."
  def capacity, do: @capacity

  @doc "What's in the owner's tank: item definition ids, in the order they went in."
  @spec contents(Ecto.UUID.t()) :: [integer()]
  def contents(owner_id), do: Homes.get(owner_id).tank || []

  @doc """
  The tank as the client draws it: each fish's id, key, name and colour, in order. Unknown ids (a
  definition since removed) are skipped.
  """
  @spec view(Ecto.UUID.t()) :: [map()]
  def view(owner_id) do
    for id <- contents(owner_id), d = Economy.item_definition(id), d != nil do
      attrs = d.base_attributes || %{}
      %{item_def_id: id, key: Map.get(attrs, "key", ""), name: d.name, color: Map.get(attrs, "color")}
    end
  end

  @doc """
  Put one of the owner's rare fish into the tank. `{:ok, contents}` or `{:error, reason}` with nothing
  moved: `:not_rare` (only rare fish go in), `:full`, `:not_enough` (they don't have one).
  """
  @spec put(Ecto.UUID.t(), integer()) :: {:ok, [integer()]} | {:error, atom()}
  def put(owner_id, item_def_id) when is_integer(item_def_id) do
    Repo.transaction(fn ->
      d = Economy.item_definition(item_def_id)
      if d == nil or d.category != "rare_fish", do: Repo.rollback(:not_rare)
      current = contents(owner_id)
      if length(current) >= @capacity, do: Repo.rollback(:full)

      case Economy.consume(owner_id, item_def_id, 1, txn_type: "tank_in", context: %{"item_def_id" => item_def_id}) do
        {:ok, _left} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      next = current ++ [item_def_id]
      Homes.set_tank(owner_id, next)
      next
    end)
  end

  def put(_owner_id, _item_def_id), do: {:error, :not_rare}

  @doc """
  Take the fish at `index` (0-based) out of the tank, back into the owner's inventory.
  `{:ok, contents}` or `{:error, :no_fish}`.
  """
  @spec take(Ecto.UUID.t(), integer()) :: {:ok, [integer()]} | {:error, atom()}
  def take(owner_id, index) when is_integer(index) do
    Repo.transaction(fn ->
      current = contents(owner_id)
      if index < 0 or index >= length(current), do: Repo.rollback(:no_fish)
      id = Enum.at(current, index)

      case Economy.grant_stack(owner_id, id, 1, txn_type: "tank_out", context: %{"item_def_id" => id}) do
        {:ok, _stack} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      next = List.delete_at(current, index)
      Homes.set_tank(owner_id, next)
      next
    end)
  end

  def take(_owner_id, _index), do: {:error, :no_fish}
end
