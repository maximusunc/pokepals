defmodule Server.WorldListItem do
  @moduledoc """
  One appended item in a world's named list. The bigserial `id` is the stable, monotonic cursor for
  pagination. Written ONLY through `Server.World.Sandbox` (world_id injected, quota enforced).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "world_list_items" do
    field :world_id, :binary_id
    field :name, :string
    field :item, :map
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(row, attrs) do
    row
    |> cast(attrs, [:world_id, :name, :item])
    |> validate_required([:world_id, :name, :item])
  end
end
