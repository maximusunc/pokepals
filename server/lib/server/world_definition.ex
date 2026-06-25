defmodule Server.WorldDefinition do
  @moduledoc """
  A world's server-hosted, versioned spec (the catalog row). `spec` is display-agnostic —
  `%{"core" => <semantic logic>, "profiles" => %{"2d" => <presentation>}}` — so a world can gain a
  3D/VR profile later without re-authoring its core. `world_id` (UUID) is the canonical handle used
  for routing, the live session, and the UGC sandbox; `slug` is an optional human handle.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:world_id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "world_definitions" do
    field :slug, :string
    field :name, :string
    field :owner_id, :binary_id
    field :display_types, {:array, :string}, default: ["2d"]
    field :version, :integer, default: 1
    field :spec, :map
    field :visibility, :string, default: "public"
    field :status, :string, default: "active"
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(definition, attrs) do
    definition
    |> cast(attrs, [:world_id, :slug, :name, :owner_id, :display_types, :version, :spec, :visibility, :status])
    |> validate_required([:name, :spec, :display_types, :version])
    |> unique_constraint(:slug)
  end
end
