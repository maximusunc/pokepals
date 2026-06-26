defmodule Server.WorldSchema do
  @moduledoc """
  An optional creator-registered schema for a key. If a row exists for (world_id, key), the sandbox
  validates values written to that key against `json_schema`.

  NOTE: validation currently supports a small, JSON-Schema-shaped subset (top-level `type`,
  `required`, and `properties` field types) — see `Server.World.Sandbox`. Full JSON Schema (via a lib
  like ex_json_schema) is a future enhancement; the column is jsonb so the stored schema can grow
  into it without a migration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "world_schemas" do
    field :world_id, :binary_id, primary_key: true
    field :key, :string, primary_key: true
    field :json_schema, :map
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:world_id, :key, :json_schema])
    |> validate_required([:world_id, :key, :json_schema])
  end
end
