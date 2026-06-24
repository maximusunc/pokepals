defmodule Server.PlayerSave do
  @moduledoc """
  One row per player, keyed by the client-generated identity token. The companion and wardrobe are
  opaque JSON blobs (jsonb) the client owns the schema of — the server just stores and returns them,
  so the client can evolve its save format without a server migration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:player_id, :string, autogenerate: false}
  schema "player_saves" do
    field :companion, :map
    field :appearance, :map
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(save, attrs) do
    save
    |> cast(attrs, [:player_id, :companion, :appearance])
    |> validate_required([:player_id])
  end
end
