defmodule Server.Repo.Migrations.CreateHotbars do
  @moduledoc """
  Each player's HOTBAR (usable items, U-9): a short row of slots holding the items they use often, one row
  per player. `slots` is a JSON array of item definition ids (or null for an empty slot), so the bar keeps
  its layout from session to session and device to device. See `Server.Hotbar`.
  """
  use Ecto.Migration

  def change do
    create table(:hotbars, primary_key: false) do
      add :user_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :slots, {:array, :integer}, null: false, default: []
      timestamps(type: :utc_datetime_usec)
    end
  end
end
