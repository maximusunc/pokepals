defmodule Server.Companion do
  @moduledoc """
  A player's bonded companion, 1:1 with an account. The `data` blob is CLIENT-OWNED and OPAQUE —
  traits, identity, birth, bond, observations, mood — and the server NEVER interprets a field of it.
  There is no level/xp; do not add typed gameplay columns. The server's only typed concerns are the
  identity (`companion_id`), the ownership (`user_id`), and later which platform items it holds (a
  separate `companion_inventory` table that links by `companion_id` without touching this blob).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:companion_id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "companions" do
    field :user_id, :binary_id
    field :data, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(companion, attrs) do
    companion
    |> cast(attrs, [:user_id, :data])
    |> validate_required([:user_id, :data])
    |> unique_constraint(:user_id)
  end
end
