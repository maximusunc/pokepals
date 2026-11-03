defmodule Server.Repo.Migrations.CreatePlayerLocations do
  @moduledoc """
  Where each player last stood: one row per player — the world they were in and their position there
  — so a returning player (even after a server restart) picks up where they left off rather than at the
  Vale's spawn. See `Server.Whereabouts`. `world_id` is text, not a foreign key: it may be a catalog
  UUID or a home world (`"home:" <> owner_id`), and a retired world simply stops being resumable.
  """
  use Ecto.Migration

  def change do
    create table(:player_locations, primary_key: false) do
      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :world_id, :text, null: false
      add :x, :float, null: false
      add :y, :float, null: false
      timestamps(type: :utc_datetime_usec)
    end
  end
end
