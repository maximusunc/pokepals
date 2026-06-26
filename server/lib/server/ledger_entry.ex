defmodule Server.LedgerEntry do
  @moduledoc """
  An immutable row in the append-only `economy_ledger`. Every currency or item movement writes one
  (or more, sharing a `correlation_id`) INSIDE the same transaction as the mutation — the audit trail
  for scam reports, dupe investigations, and rollbacks. NEVER `UPDATE` or `DELETE` a ledger row.

  `from_user`/`to_user` are nullable: a mint (grant/reward) has no `from_user`; a sink (burn) has no
  `to_user`. `asset_ref` is the currency_type or the item_instance_id, per `asset_kind`. The schema's
  `inserted_at` is the spec's `occurred_at`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:ledger_id, :id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "economy_ledger" do
    field :txn_type, :string
    field :from_user, :binary_id
    field :to_user, :binary_id
    field :asset_kind, :string
    field :asset_ref, :string
    field :amount, :integer
    field :context, :map, default: %{}
    field :correlation_id, :binary_id
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:txn_type, :from_user, :to_user, :asset_kind, :asset_ref, :amount, :context, :correlation_id])
    |> validate_required([:txn_type, :asset_kind, :asset_ref, :amount, :correlation_id])
  end
end
