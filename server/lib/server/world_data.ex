defmodule Server.WorldData do
  @moduledoc """
  One freeform KV row in the UGC sandbox, scoped to a world. Written ONLY through
  `Server.World.Sandbox`, which injects `world_id` and enforces quota/schema/version. The composite
  key is (world_id, scope, owner_id, key); `value` is a JSON object; `version` powers optimistic
  concurrency.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "world_data" do
    field :world_id, :binary_id, primary_key: true
    field :scope, :string, primary_key: true
    field :owner_id, :binary_id, primary_key: true
    field :key, :string, primary_key: true
    field :value, :map
    field :version, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(row, attrs) do
    row
    |> cast(attrs, [:world_id, :scope, :owner_id, :key, :value, :version])
    |> validate_required([:world_id, :scope, :owner_id, :key, :value, :version])
  end
end
