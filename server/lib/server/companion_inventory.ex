defmodule Server.CompanionInventory do
  @moduledoc """
  Items held by a companion. Links the typed item economy to the OPAQUE companion by `companion_id`
  without ever touching the companion's opaque blob. A future seam — present so the schema is whole,
  exercised once the game gives companions item-holding.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:item_instance_id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "companion_inventory" do
    field :companion_id, :binary_id
    field :item_def_id, :id
    field :quantity, :integer, default: 1
    field :attributes, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:item_instance_id, :companion_id, :item_def_id, :quantity, :attributes])
    |> validate_required([:companion_id, :item_def_id, :quantity])
    |> check_constraint(:quantity, name: :quantity_positive)
  end
end
