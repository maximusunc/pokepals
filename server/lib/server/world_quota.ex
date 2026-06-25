defmodule Server.WorldQuota do
  @moduledoc """
  Per-world quota accounting: total bytes stored and key count, against their limits. Checked and
  updated (under lock) in the same transaction as every sandbox write.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "world_quota" do
    field :world_id, :binary_id, primary_key: true
    field :bytes_used, :integer, default: 0
    field :bytes_limit, :integer, default: 5_368_709_120
    field :key_count, :integer, default: 0
    field :key_limit, :integer, default: 10_000_000
    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(quota, attrs) do
    quota
    |> cast(attrs, [:world_id, :bytes_used, :bytes_limit, :key_count, :key_limit])
    |> validate_required([:world_id])
  end
end
