defmodule Server.Repo.Migrations.AddWorldDirectoryFields do
  @moduledoc """
  The world DIRECTORY — what the Vale's Gateway lists and searches. Each catalog row gains the small
  card a traveller browses by (a one-line `blurb`, searchable `tags`, an `accent` colour), so the
  directory never has to ship a world's spec just to draw a list of them.

    * `featured` floats a world into the Gateway's Featured shelf.
    * `listed` — false keeps a world out of the directory while it stays joinable (the Vale itself:
      it's the hub you search FROM, not somewhere to travel to).

  Search is a plain ILIKE over name/blurb/tags — fine for hundreds of worlds. DEFERRED SEAM: a pg_trgm
  GIN index (or full-text search) when the catalog reaches thousands.
  """
  use Ecto.Migration

  def change do
    alter table(:world_definitions) do
      add :blurb, :text, null: false, default: ""
      add :tags, {:array, :text}, null: false, default: []
      add :accent, {:array, :float}
      add :featured, :boolean, null: false, default: false
      add :listed, :boolean, null: false, default: true
    end

    create index(:world_definitions, [:listed, :featured])
  end
end
