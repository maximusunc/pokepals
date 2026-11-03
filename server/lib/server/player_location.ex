defmodule Server.PlayerLocation do
  @moduledoc """
  Where a player last stood: the world (`world_id` — a catalog UUID or `"home:" <> owner_id`) and
  their position in it. One row per player, overwritten as they move. See `Server.Whereabouts`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:user_id, :binary_id, autogenerate: false}
  schema "player_locations" do
    field :world_id, :string
    field :x, :float
    field :y, :float
    timestamps(type: :utc_datetime_usec)
  end
end
