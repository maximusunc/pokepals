defmodule Server.Repo.Migrations.CreateDiscoveries do
  @moduledoc """
  World SECRETS a player has found — the record their HOME WORLD is built from (see
  `Server.HomeWorld`). One row per (player, discovery): every destination world hides one secret,
  and finding it is a one-time thing, so the pair is unique. `world_id` is where it was found (the
  catalog world whose spec carried the secret) — kept for the home's "where it came from" and for
  later friend-visit views; it is not a foreign key so retiring a world never erases a memory.
  """
  use Ecto.Migration

  def change do
    create table(:discoveries, primary_key: false) do
      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :discovery_id, :text, primary_key: true
      add :world_id, :uuid
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end
end
