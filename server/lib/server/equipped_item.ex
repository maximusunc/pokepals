defmodule Server.EquippedItem do
  @moduledoc """
  Which inventory instance is worn in each (user, slot). Pure presentation/stats wiring — equipping
  does NOT change ownership, so it writes no ledger row. Set through `Server.Economy.equip/3`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  @foreign_key_type :binary_id
  schema "equipped_items" do
    field :user_id, :binary_id, primary_key: true
    field :slot, :string, primary_key: true
    field :item_instance_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(equipped, attrs) do
    equipped
    |> cast(attrs, [:user_id, :slot, :item_instance_id])
    |> validate_required([:user_id, :slot, :item_instance_id])
  end
end
