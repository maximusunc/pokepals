defmodule Server.Appearance do
  @moduledoc """
  A player's wardrobe/appearance, keyed by `user_id` (1:1 with an account). Like the companion, the
  `data` blob is CLIENT-OWNED and OPAQUE — the server stores and returns it but never reads a field,
  so the client can evolve its appearance format without a server migration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:user_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "player_appearances" do
    field :data, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(appearance, attrs) do
    appearance
    |> cast(attrs, [:user_id, :data])
    |> validate_required([:user_id, :data])
  end
end
