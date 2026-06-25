defmodule Server.InventoryItem do
  @moduledoc """
  One row per item INSTANCE, owned by a user. `attributes` carries per-instance state (durability,
  enchants). Ownership changes ONLY through `Server.Economy` (trade/grant), always with a matching
  `economy_ledger` row in the same transaction.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:item_instance_id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "inventory_items" do
    field :user_id, :binary_id
    field :item_def_id, :id
    field :quantity, :integer, default: 1
    field :attributes, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:item_instance_id, :user_id, :item_def_id, :quantity, :attributes])
    |> validate_required([:user_id, :item_def_id, :quantity])
    |> check_constraint(:quantity, name: :quantity_positive)
  end
end
