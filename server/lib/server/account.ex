defmodule Server.Account do
  @moduledoc """
  The identity anchor. The `user_id` UUID is the INTERNAL key every other table (companion,
  appearance, the economy) points at. A player signs in from one or more DEVICES (`Server.Device`),
  each with its own anonymous bearer token; the account itself no longer holds a token. `email` / `username` / `password_hash` are nullable upgrade-path columns —
  a player can "claim" their account later without the `user_id` ever changing.

  The server never derives gameplay from this row; it's purely identity + status.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:user_id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "accounts" do
    # `accounts.token` still exists in the table (kept, nullable, for a safe rollback; see the
    # devices migration) but is deliberately left out of the schema: it is neither read nor written.
    field :email, :string
    field :username, :string
    field :password_hash, :string
    field :status, :string, default: "active"
    # FR-0/FR-2: a generated two-word name and a short friend code, both assigned lazily on first
    # connect (Server.Profiles). Never typed by the player, so neither needs moderating.
    field :display_name, :string
    field :friend_code, :string
    # Bumped on every socket connect (Server.Devices.next_session/1): the newest connection wins.
    field :session_gen, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:email, :username, :password_hash, :status])
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> unique_constraint(:friend_code)
  end
end
