# The creator-facing sandbox API (§7). Thin facades over `Server.World.Sandbox`, grouped by scope and
# feature — exactly the surface creator code sees. Every call takes a runtime-bound
# `Server.World.Context` as the first argument; creator code can never supply a raw `world_id`.
#
# Multiple small modules live in this one file because each is a thin, cohesive facade.

defmodule Server.World.Player do
  @moduledoc "Per-player world data: `owner` is the player's user_id."
  alias Server.World.Sandbox

  @scope "player"

  def get(ctx, user_id, key), do: Sandbox.get(ctx, @scope, user_id, key)
  def set(ctx, user_id, key, value, opts \\ []), do: Sandbox.set(ctx, @scope, user_id, key, value, opts)
  def increment(ctx, user_id, key, field, n), do: Sandbox.increment(ctx, @scope, user_id, key, field, n)
end

defmodule Server.World.Global do
  @moduledoc "World-wide data (no owner): stored under the sandbox's sentinel global owner."
  alias Server.World.Sandbox

  @scope "world"

  def get(ctx, key), do: Sandbox.get(ctx, @scope, Sandbox.global_owner(), key)
  def set(ctx, key, value, opts \\ []), do: Sandbox.set(ctx, @scope, Sandbox.global_owner(), key, value, opts)
  def increment(ctx, key, field, n), do: Sandbox.increment(ctx, @scope, Sandbox.global_owner(), key, field, n)
end

defmodule Server.World.Entity do
  @moduledoc "Per-entity world data: `owner` is the entity's id."
  alias Server.World.Sandbox

  @scope "entity"

  def get(ctx, entity_id, key), do: Sandbox.get(ctx, @scope, entity_id, key)
  def set(ctx, entity_id, key, value, opts \\ []), do: Sandbox.set(ctx, @scope, entity_id, key, value, opts)
  def increment(ctx, entity_id, key, field, n), do: Sandbox.increment(ctx, @scope, entity_id, key, field, n)
end

defmodule Server.World.List do
  @moduledoc "Bounded, append-only ordered lists with cursor pagination."
  alias Server.World.Sandbox

  def append(ctx, name, item), do: Sandbox.list_append(ctx, name, item)
  def page(ctx, name, cursor, n), do: Sandbox.list_page(ctx, name, cursor, n)
end

defmodule Server.World.Leaderboard do
  @moduledoc """
  Creator leaderboards.

  ── DEFERRED SEAM (Redis): the spec backs leaderboards with Redis ZSETs (cross-node ranking). Per the
  no-scale guidance, that's not built yet — these return `{:error, :not_implemented}`. When ranking is
  actually needed, wire these to Redix ZSETs (`ZADD` / `ZREVRANK` / `ZREVRANGE`), keyed per world:
  `leaderboard:world:{world_id}:{board}`. A small single-node board could instead live in an ETS
  ordered set in the world process; either way the swap happens HERE, behind this unchanged facade. ──
  """
  def submit(_ctx, _name, _user_id, _score), do: {:error, :not_implemented}
  def top(_ctx, _name, _n), do: {:error, :not_implemented}
  def rank(_ctx, _name, _user_id), do: {:error, :not_implemented}
end
