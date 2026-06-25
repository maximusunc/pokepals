defmodule Server.Repo.Migrations.CreateAccountsAndSaves do
  @moduledoc """
  P1 foundation schema. Replaces the single opaque `player_saves` (token -> blobs) table with the
  reconciled identity model:

    * `accounts`            — the identity anchor. The client still holds an anonymous bearer token,
                              but every other row is keyed by the INTERNAL `user_id` UUID. email /
                              username / password_hash are nullable UPGRADE-PATH columns (claim an
                              account later without changing `user_id` or breaking any FK).
    * `companions`          — the companion, kept as a CLIENT-OWNED OPAQUE jsonb blob (1:1 with a
                              player). The server stores and serves it but never interprets a field.
    * `player_appearances`  — the wardrobe/appearance, the same opaque-blob treatment, keyed by
                              `user_id`.

  The game is NOT in production, so this just drops the old table and creates the target schema —
  no backfill, no data to preserve.
  """
  use Ecto.Migration

  def change do
    # gen_random_uuid/0 lives in pgcrypto on PG < 13; harmless to ensure it everywhere.
    execute "CREATE EXTENSION IF NOT EXISTS \"pgcrypto\"", "DROP EXTENSION IF EXISTS \"pgcrypto\""

    # The retired opaque save store. No data to migrate (pre-production).
    drop_if_exists table(:player_saves)

    create table(:accounts, primary_key: false) do
      add :user_id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :token, :text, null: false
      add :email, :text
      add :username, :text
      add :password_hash, :text
      add :status, :text, null: false, default: "active"
      timestamps(type: :utc_datetime_usec)
    end

    # The token is the client-facing credential and the lookup into the table; email/username are
    # unique only once a player claims an account (NULLs are distinct in a Postgres unique index, so
    # the many unclaimed accounts coexist freely).
    create unique_index(:accounts, [:token])
    create unique_index(:accounts, [:email])
    create unique_index(:accounts, [:username])

    create table(:companions, primary_key: false) do
      add :companion_id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        null: false

      add :data, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(type: :utc_datetime_usec)
    end

    # 1:1 with a player — one companion per account.
    create unique_index(:companions, [:user_id])

    create table(:player_appearances, primary_key: false) do
      add :user_id,
          references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
          primary_key: true

      add :data, :map, null: false, default: fragment("'{}'::jsonb")
      timestamps(type: :utc_datetime_usec)
    end
  end
end
