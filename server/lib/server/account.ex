defmodule Server.Account do
  @moduledoc """
  The identity anchor. The client authenticates with an anonymous 128-bit bearer `token`; the
  `user_id` UUID it maps to is the INTERNAL key every other table (companion, appearance, and later
  the economy) points at. `email` / `username` / `password_hash` are nullable upgrade-path columns —
  a player can "claim" their account later without the `user_id` ever changing.

  The server never derives gameplay from this row; it's purely identity + status.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:user_id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "accounts" do
    field :token, :string
    field :email, :string
    field :username, :string
    field :password_hash, :string
    field :status, :string, default: "active"
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:token, :email, :username, :password_hash, :status])
    |> validate_required([:token])
    |> unique_constraint(:token)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end
end
