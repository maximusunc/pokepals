defmodule Server.LinkCode do
  @moduledoc """
  A "Link a device" code (Server.Links): the owner asks for one on a device they're signed in on, types
  it into the new device, and says yes when the new device asks. Only the code's hash is stored.

  `state`: "open" (waiting to be typed in) -> "pending" (a new device asked; `pending_token_hash` and
  `pending_name` say which) -> "linked" or "denied". "void" once the owner asks for a newer code.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @foreign_key_type :binary_id
  schema "link_codes" do
    field :user_id, :binary_id
    field :code_hash, :string
    field :state, :string, default: "open"
    field :expires_at, :utc_datetime_usec
    field :pending_token_hash, :string
    field :pending_name, :string
    field :answered_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
