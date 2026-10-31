defmodule Server.Discovery do
  @moduledoc """
  One world secret a player has found — keyed by (user_id, discovery_id), so each can be found once.
  The discovery_id is the `secret.id` authored in the world's spec (e.g. `"hedge_seed"`); what it
  looks like at home is the home template's business (`Server.HomeWorld`), not this row's.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  @foreign_key_type :binary_id
  schema "discoveries" do
    field :user_id, :binary_id, primary_key: true
    field :discovery_id, :string, primary_key: true
    field :world_id, :binary_id
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(discovery, attrs) do
    discovery
    |> cast(attrs, [:user_id, :discovery_id, :world_id])
    |> validate_required([:user_id, :discovery_id])
  end
end
