defmodule Server.WorldCounter do
  @moduledoc """
  A number a world keeps for good, by `{world_id, key}` (the wishing fountain's wishes in Lingerlong). Read and
  bumped through `Server.Wishes`, which caches it; the table is only ever written by an upsert-increment.
  """
  use Ecto.Schema

  schema "world_counters" do
    field :world_id, :string
    field :key, :string
    field :value, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end
