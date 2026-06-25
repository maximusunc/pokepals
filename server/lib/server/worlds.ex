defmodule Server.Worlds do
  @moduledoc """
  The world CATALOG boundary: read world definitions (specs) and seed them. This is the source of
  truth for world structure — clients fetch a spec by `world_id` on visit and cache it by `version`,
  so the (eventually millions of) worlds never have to ship inside the client.

  Distinct from `Server.World` (the live per-world session process) and the P4 `world_data` sandbox
  (mutable runtime KV). This module only deals with the authored, versioned definition.
  """
  import Ecto.Query
  alias Server.{Repo, WorldDefinition}

  @doc "Fetch a world definition by its canonical UUID `world_id` (or nil)."
  @spec get(Ecto.UUID.t()) :: WorldDefinition.t() | nil
  def get(world_id) when is_binary(world_id), do: Repo.get(WorldDefinition, world_id)

  @doc "Fetch a world definition by its human `slug` (or nil)."
  @spec get_by_slug(String.t()) :: WorldDefinition.t() | nil
  def get_by_slug(slug) when is_binary(slug), do: Repo.get_by(WorldDefinition, slug: slug)

  @doc """
  A page of visible, active worlds for a catalog/browser. Opts: `:limit` (default 50), `:offset`
  (default 0), `:display_type` (filter to worlds shipping that profile).
  """
  @spec list(keyword()) :: [WorldDefinition.t()]
  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(w in WorldDefinition,
        where: w.visibility == "public" and w.status == "active",
        order_by: [asc: w.name],
        limit: ^limit,
        offset: ^offset
      )

    query =
      case Keyword.get(opts, :display_type) do
        nil -> query
        dt -> from(w in query, where: fragment("? = ANY(?)", ^dt, w.display_types))
      end

    Repo.all(query)
  end

  @doc """
  The just-the-version metadata for a world (cheap; used to answer a client's cache check without
  shipping the whole spec). Returns the integer version or nil if the world is unknown.
  """
  @spec version(Ecto.UUID.t()) :: integer() | nil
  def version(world_id) when is_binary(world_id) do
    Repo.one(from(w in WorldDefinition, where: w.world_id == ^world_id, select: w.version))
  end

  @doc """
  Upsert a definition by `world_id` (idempotent — for seeds). Bumps nothing automatically; the caller
  supplies `version`.
  """
  @spec upsert(map()) :: {:ok, WorldDefinition.t()} | {:error, Ecto.Changeset.t()}
  def upsert(attrs) do
    %WorldDefinition{}
    |> WorldDefinition.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:slug, :name, :owner_id, :display_types, :version, :spec, :visibility, :status, :updated_at]},
      conflict_target: :world_id
    )
  end

  @doc "The client/HTTP-facing view of a definition (the spec plus its identifying metadata)."
  @spec client_view(WorldDefinition.t()) :: map()
  def client_view(%WorldDefinition{} = w) do
    %{
      world_id: w.world_id,
      slug: w.slug,
      name: w.name,
      display_types: w.display_types,
      version: w.version,
      spec: w.spec
    }
  end
end
