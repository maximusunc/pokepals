defmodule Server.Device do
  @moduledoc """
  One device a player is signed in on (issue 175). The device holds a random 128-bit bearer token;
  the server keeps only its SHA-256 (`token_hash`), so a copy of the database can't be replayed as a
  login. A token that random needs no slow, salted hash: there is nothing to guess.

  `revoked_at` is set when the player signs this device out from another one; its token then never
  resolves again (and never mints a fresh account either).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:device_id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "devices" do
    field :user_id, :binary_id
    field :token_hash, :string
    field :name, :string, default: "Device"
    field :last_seen_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [:user_id, :token_hash, :name, :last_seen_at])
    |> validate_required([:user_id, :token_hash, :name])
    |> unique_constraint(:token_hash)
  end
end
