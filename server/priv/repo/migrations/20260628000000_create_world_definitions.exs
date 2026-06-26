defmodule Server.Repo.Migrations.CreateWorldDefinitions do
  @moduledoc """
  P5 (multi-world) — the world CATALOG: the server-hosted, versioned definition of each world. This
  is the world *spec* (authored structure), distinct from the P4 `world_data` sandbox (mutable
  runtime KV) and the live `Server.World` session (transient transforms).

  Clients no longer bake every world in — they fetch a world's spec by `world_id` on visit and cache
  it by `version`. The spec is display-AGNOSTIC: a `core` (semantic logic: regions, interactables,
  portals, spawns) plus per-display-type `profiles` (only "2d" today; 3D/VR can be added to the same
  world later without re-authoring the core).

  Scales to many worlds: metadata + spec jsonb in Postgres now (shardable by `world_id` later), heavy
  assets referenced by URL — DEFERRED SEAM: move spec docs/assets to object storage + CDN when the
  catalog or asset sizes demand it. Not built now.
  """
  use Ecto.Migration

  def change do
    create table(:world_definitions, primary_key: false) do
      add :world_id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :slug, :text
      add :name, :text, null: false
      # Creator/owner; NULL for platform-authored seed worlds. Survives account deletion.
      add :owner_id, references(:accounts, column: :user_id, type: :uuid, on_delete: :nilify_all)
      # Which display profiles this world ships (clients filter to what they can render).
      add :display_types, {:array, :text}, null: false, default: ["2d"]
      add :version, :bigint, null: false, default: 1
      # The spec document: %{"core" => <semantic>, "profiles" => %{"2d" => <presentation>}}.
      add :spec, :map, null: false
      add :visibility, :text, null: false, default: "public"
      add :status, :text, null: false, default: "active"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:world_definitions, [:slug])
    create index(:world_definitions, [:visibility, :status])
    create index(:world_definitions, [:owner_id])
  end
end
