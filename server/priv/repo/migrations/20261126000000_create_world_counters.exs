defmodule Server.Repo.Migrations.CreateWorldCounters do
  @moduledoc """
  Small shared numbers a world keeps for good (Server.WorldCounter): Lingerlong's wishing fountain counts every
  wish ever tossed into it (`key` "wishes"). One row per world and key, bumped with an upsert-increment.
  """
  use Ecto.Migration

  def change do
    create table(:world_counters) do
      add :world_id, :text, null: false
      add :key, :text, null: false
      add :value, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:world_counters, [:world_id, :key])
  end
end
