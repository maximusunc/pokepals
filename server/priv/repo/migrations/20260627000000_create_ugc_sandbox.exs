defmodule Server.Repo.Migrations.CreateUgcSandbox do
  @moduledoc """
  P4 — the UGC sandbox: a FENCED store for creator-world data, separate from the platform's typed
  identity/economy tables (the §0 wall). Creator code reaches this only through `Server.World.Sandbox`,
  which injects `world_id` itself — so no query can ever span worlds.

  These tables deliberately have NO foreign keys to accounts/economy: `world_id` and `owner_id` are
  bare UUIDs in the sandbox's own space. Isolation, quotas, and validation are enforced in the
  data-access layer, not in SQL (per §4).
  """
  use Ecto.Migration

  def change do
    # ── Freeform per-world KV. PK is (world_id, scope, owner_id, key); owner_id is a sentinel nil-UUID
    #    for world scope (Postgres PK columns can't be NULL), the user_id for player scope, the entity
    #    id for entity scope — always injected by the runtime. `version` powers optimistic concurrency.
    create table(:world_data, primary_key: false) do
      add :world_id, :uuid, primary_key: true
      add :scope, :text, primary_key: true
      add :owner_id, :uuid, primary_key: true
      add :key, :text, primary_key: true
      add :value, :map, null: false
      add :version, :bigint, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    # Limited, controlled filtered reads on hot fields only (never exposed as arbitrary queries).
    execute(
      "CREATE INDEX world_data_value_gin ON world_data USING GIN (value jsonb_path_ops)",
      "DROP INDEX world_data_value_gin"
    )

    # ── Per-world quota accounting, enforced (under lock) before every write.
    create table(:world_quota, primary_key: false) do
      add :world_id, :uuid, primary_key: true
      add :bytes_used, :bigint, null: false, default: 0
      # 5 GiB default ceiling on total stored bytes…
      add :bytes_limit, :bigint, null: false, default: 5_368_709_120
      add :key_count, :bigint, null: false, default: 0
      # …and 10M keys.
      add :key_limit, :bigint, null: false, default: 10_000_000
      timestamps(type: :utc_datetime_usec)
    end

    # ── Optional creator-registered schemas: if a row exists for a key, its value is validated.
    create table(:world_schemas, primary_key: false) do
      add :world_id, :uuid, primary_key: true
      add :key, :text, primary_key: true
      add :json_schema, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    # ── Append-only lists, the bounded ordered-list primitive (paginated by the bigserial id cursor).
    create table(:world_list_items) do
      add :world_id, :uuid, null: false
      add :name, :text, null: false
      add :item, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:world_list_items, [:world_id, :name, :id])
  end
end
