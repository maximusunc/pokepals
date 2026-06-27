defmodule Server.Worlds do
  @moduledoc """
  The world CATALOG boundary: read world definitions (specs) and seed them. This is the source of
  truth for world structure — clients fetch a spec by `world_id` on visit and cache it by its content
  `etag/1`, so the (eventually millions of) worlds never have to ship inside the client.

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
  The author-facing integer `version` of a world (cheap to fetch; human-meaningful metadata, NOT the
  cache validator — that is `etag/1`, which is content-derived). Returns the version or nil if the
  world is unknown.
  """
  @spec version(Ecto.UUID.t()) :: integer() | nil
  def version(world_id) when is_binary(world_id) do
    Repo.one(from(w in WorldDefinition, where: w.world_id == ^world_id, select: w.version))
  end

  @doc """
  A content-derived ETAG for a world's spec: a short, stable token that changes if and only if the
  spec's content changes. It is the cache validator the client echoes back (`known_etag`) so an
  unchanged world is never re-shipped — and, because it falls straight out of the content, ANY
  back-end edit to a world invalidates every client's cache automatically, with no version to
  remember to bump and no new client build to ship.

  Order-independent (it hashes the decoded term, so map key order doesn't matter) and stable across
  nodes of the same release. It MAY change across Erlang/OTP releases, which would harmlessly make
  every client re-fetch the spec once.
  """
  @spec etag(WorldDefinition.t() | map() | nil) :: String.t()
  def etag(%WorldDefinition{spec: spec}), do: etag(spec)
  def etag(spec) when is_map(spec), do: spec |> :erlang.phash2() |> Integer.to_string(16)
  def etag(_), do: "0"

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

  @doc """
  The client/HTTP-facing view of a definition: the spec, its identifying metadata, and the content
  `etag` the client caches by (and echoes back as `known_etag` on its next visit).
  """
  @spec client_view(WorldDefinition.t()) :: map()
  def client_view(%WorldDefinition{} = w) do
    %{
      world_id: w.world_id,
      slug: w.slug,
      name: w.name,
      display_types: w.display_types,
      version: w.version,
      etag: etag(w),
      spec: w.spec
    }
  end
end
