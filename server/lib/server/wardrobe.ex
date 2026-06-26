defmodule Server.Wardrobe do
  @moduledoc """
  Cosmetics a player owns by DEFINITION (not instance) — one row per (user, item_def). Unlocking is
  a grant; it goes through `Server.Economy`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  @foreign_key_type :binary_id
  schema "wardrobe" do
    field :user_id, :binary_id, primary_key: true
    field :item_def_id, :id, primary_key: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:user_id, :item_def_id])
    |> validate_required([:user_id, :item_def_id])
  end
end
