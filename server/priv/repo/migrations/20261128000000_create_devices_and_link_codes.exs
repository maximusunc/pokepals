defmodule Server.Repo.Migrations.CreateDevicesAndLinkCodes do
  @moduledoc """
  Accounts that outlive one device (issue 175). Until now a player WAS one anonymous bearer token in
  `accounts.token`; lose the device and the companion was gone. Now:

    * `devices`    — one row per signed-in device: the SHA-256 of its token (never the token itself),
                     a name the player recognises ("Sam's phone"), when it was last seen, and
                     `revoked_at` once it has been signed out from another device. An account can
                     carry several.
    * `link_codes` — the short-lived "Link a device" codes (10 minutes). They live in Postgres, not
                     ETS, so a restart or a second node doesn't lose a code half-way through linking.
    * `accounts.session_gen` — bumped on every socket connect, so the newest connection wins and an
                     older one (even one caught between two worlds, with no channel open) knows it was
                     replaced the next time it tries to join.

  Every existing account gets one device carrying its current token's hash ("First device"), so every
  player already out there keeps playing with the token they have.

  `accounts.token` becomes NULLABLE and the code stops reading and writing it (new accounts leave it
  NULL). It is deliberately NOT dropped, and its values are NOT cleared, in this release: if we have to
  roll the code back, the old code still finds every pre-existing player by their token. Drop it in a
  later release once this one has settled.
  """
  use Ecto.Migration

  def up do
    create table(:devices, primary_key: false) do
      add :device_id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        null: false

      add :token_hash, :text, null: false
      add :name, :text, null: false, default: "Device"
      add :last_seen_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:devices, [:token_hash])
    create index(:devices, [:user_id])

    # pgcrypto has been enabled since the first migration. Lowercase hex SHA-256, exactly what
    # Server.Devices.hash_token/1 computes from the same token.
    execute """
    INSERT INTO devices (device_id, user_id, token_hash, name, last_seen_at, inserted_at, updated_at)
    SELECT gen_random_uuid(), user_id, encode(digest(token, 'sha256'), 'hex'), 'First device',
           updated_at, now(), now()
    FROM accounts
    WHERE token IS NOT NULL
    """

    execute "ALTER TABLE accounts ALTER COLUMN token DROP NOT NULL"

    alter table(:accounts) do
      add :session_gen, :bigint, null: false, default: 0
    end

    create table(:link_codes) do
      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        null: false

      # SHA-256 of the normalised code (8 letters/digits, no dash). Short-lived, but still not kept
      # in the clear, like the tokens.
      add :code_hash, :text, null: false
      # open -> pending (a new device asked) -> linked | denied; void when the owner asks for another.
      add :state, :text, null: false, default: "open"
      add :expires_at, :utc_datetime_usec, null: false
      add :pending_token_hash, :text
      add :pending_name, :text
      add :answered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:link_codes, [:code_hash])
    create index(:link_codes, [:user_id])
    create index(:link_codes, [:expires_at])
  end

  # Going back leaves `accounts.token` nullable: accounts made under this release have no token, so
  # NOT NULL can't come back without losing them.
  def down do
    drop table(:link_codes)

    alter table(:accounts) do
      remove :session_gen
    end

    drop table(:devices)
  end
end
