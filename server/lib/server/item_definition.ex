defmodule Server.ItemDefinition do
  @moduledoc """
  An item TEMPLATE (stored once, referenced by every instance). `item_def_id` is content-supplied
  (not auto-generated). Read constantly, changed rarely — a per-node ETS cache belongs here (see the
  flagged seam in `Server.Economy.item_definition/1`), but is deferred until the read volume needs it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:item_def_id, :id, autogenerate: false}
  schema "item_definitions" do
    field :name, :string
    field :category, :string
    field :slot, :string
    field :stackable, :boolean, default: false
    field :base_attributes, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(item_def, attrs) do
    item_def
    |> cast(attrs, [:item_def_id, :name, :category, :slot, :stackable, :base_attributes])
    |> validate_required([:item_def_id, :name, :category])
  end
end
