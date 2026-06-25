defmodule Server.Repo.Migrations.CreateEconomy do
  @moduledoc """
  P3 — the economy core: the strict, typed, transactional tables the platform owns and creator/world
  code may NEVER touch (the §0 wall). Money is `BIGINT` (never floats); the `economy_ledger` is an
  append-only audit trail every currency/item movement writes to inside the same transaction.

  Everything is keyed by `user_id` so it shards by user later (config change, not a rewrite) — but no
  sharding is built now. These tables exist as the destination the game grows into when it actually
  introduces money/items; until then they're unused but correct.
  """
  use Ecto.Migration

  def change do
    # ── Item definitions (templates, not instances). item_def_id is content-supplied, not serial. ──
    create table(:item_definitions, primary_key: false) do
      add :item_def_id, :integer, primary_key: true
      add :name, :text, null: false
      add :category, :text, null: false
      add :slot, :text
      add :stackable, :boolean, null: false, default: false
      add :base_attributes, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # ── Currency: one row per (user, currency_type). BIGINT, never negative. ──
    create table(:player_currencies, primary_key: false) do
      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :currency_type, :text, primary_key: true
      add :balance, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:player_currencies, "balance_non_negative", check: "balance >= 0")

    # ── Inventory: one row per item INSTANCE (uuid), owned by a user, of some definition. ──
    create table(:inventory_items, primary_key: false) do
      add :item_instance_id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        null: false

      add :item_def_id,
          references(:item_definitions, column: :item_def_id, type: :integer),
          null: false

      add :quantity, :integer, null: false, default: 1
      add :attributes, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(type: :utc_datetime_usec)
    end

    create index(:inventory_items, [:user_id])
    create constraint(:inventory_items, "quantity_positive", check: "quantity > 0")

    # ── Equipped: slot -> the inventory instance worn there. ──
    create table(:equipped_items, primary_key: false) do
      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :slot, :text, primary_key: true

      add :item_instance_id,
          references(:inventory_items, column: :item_instance_id, type: :uuid, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    # ── Wardrobe: cosmetics owned by DEFINITION (not instance). ──
    create table(:wardrobe, primary_key: false) do
      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :item_def_id,
          references(:item_definitions, column: :item_def_id, type: :integer),
          primary_key: true

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # ── Companion inventory: links the typed item economy to the opaque companion by companion_id,
    #    WITHOUT touching the companion's opaque blob. ──
    create table(:companion_inventory, primary_key: false) do
      add :item_instance_id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :companion_id,
          references(:companions, column: :companion_id, type: :uuid, on_delete: :delete_all),
          null: false

      add :item_def_id,
          references(:item_definitions, column: :item_def_id, type: :integer),
          null: false

      add :quantity, :integer, null: false, default: 1
      add :attributes, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(type: :utc_datetime_usec)
    end

    create index(:companion_inventory, [:companion_id])
    create constraint(:companion_inventory, "quantity_positive", check: "quantity > 0")

    # ── Economy ledger: append-only audit trail. NEVER UPDATE or DELETE these rows. ──
    create table(:economy_ledger, primary_key: false) do
      add :ledger_id, :bigserial, primary_key: true
      # inserted_at == the spec's occurred_at.
      add :txn_type, :text, null: false
      add :from_user, references(:accounts, column: :user_id, type: :uuid)
      add :to_user, references(:accounts, column: :user_id, type: :uuid)
      add :asset_kind, :text, null: false
      add :asset_ref, :text, null: false
      add :amount, :bigint, null: false
      add :context, :map, null: false, default: fragment("'{}'::jsonb")
      add :correlation_id, :uuid, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:economy_ledger, [:from_user, :inserted_at])
    create index(:economy_ledger, [:to_user, :inserted_at])
    create index(:economy_ledger, [:correlation_id])
  end
end
