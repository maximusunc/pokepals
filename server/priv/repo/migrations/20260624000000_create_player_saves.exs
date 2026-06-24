defmodule Server.Repo.Migrations.CreatePlayerSaves do
  use Ecto.Migration

  def change do
    create table(:player_saves, primary_key: false) do
      # The client-generated identity token (a random hex string). Opaque to the server.
      add :player_id, :string, primary_key: true
      # Opaque JSON blobs the client owns (jsonb in Postgres).
      add :companion, :map
      add :appearance, :map
      timestamps(type: :utc_datetime_usec)
    end
  end
end
