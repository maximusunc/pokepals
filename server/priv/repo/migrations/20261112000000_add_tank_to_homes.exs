defmodule Server.Repo.Migrations.AddTankToHomes do
  @moduledoc """
  The fish TANK at home (usable items, step 3; docs/usable-items-design.md): the rare fish swimming in it,
  as item definition ids in the order they were put in. A fish in the tank has left its owner's inventory
  (Server.Tank moves it, ledgered, through Server.Economy).
  """
  use Ecto.Migration

  def change do
    alter table(:homes) do
      add :tank, {:array, :integer}, null: false, default: []
    end
  end
end
