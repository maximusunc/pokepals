defmodule Server.Repo.Migrations.AddHouseToHomes do
  @moduledoc """
  YOUR HOUSE (home building; docs/usable-items-design.md): once the carpenter in the bazaar has been paid
  (Server.House), the home records when she started building, `%{"started_at" => unix_ms}`. Null until then.
  """
  use Ecto.Migration

  def change do
    alter table(:homes) do
      add(:house, :map)
    end
  end
end
