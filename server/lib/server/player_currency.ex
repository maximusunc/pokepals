defmodule Server.PlayerCurrency do
  @moduledoc """
  One row per (user, currency_type). Balance is `BIGINT` (never a float) and can never go negative
  (a DB CHECK backs the in-transaction verification). Mutated ONLY through `Server.Economy`, always
  alongside an `economy_ledger` row in the same transaction.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  @foreign_key_type :binary_id
  schema "player_currencies" do
    field :user_id, :binary_id, primary_key: true
    field :currency_type, :string, primary_key: true
    field :balance, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(currency, attrs) do
    currency
    |> cast(attrs, [:user_id, :currency_type, :balance])
    |> validate_required([:user_id, :currency_type, :balance])
    |> check_constraint(:balance, name: :balance_non_negative)
  end
end
