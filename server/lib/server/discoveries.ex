defmodule Server.Discoveries do
  @moduledoc """
  The persistence boundary for world SECRETS a player has found. Server-canonical like the companion
  and the wardrobe: a discovery is only ever recorded here, by the channel, after the server has
  judged the claim (`claimable?/3` — the world's spec carries that secret, and the player is
  actually standing at it). Each discovery can be found once; a repeat claim is a harmless no-op.
  """
  import Ecto.Query
  alias Server.{Discovery, Repo}

  @doc "The discovery ids a player has found, oldest first."
  @spec list(Ecto.UUID.t()) :: [String.t()]
  def list(user_id) when is_binary(user_id) do
    Repo.all(
      from(d in Discovery,
        where: d.user_id == ^user_id,
        order_by: [asc: d.inserted_at, asc: d.discovery_id],
        select: d.discovery_id
      )
    )
  end

  @doc """
  Record that `user_id` found `discovery_id` (in `world_id`). Returns `{:ok, :new}` the first time and
  `{:ok, :already}` after that — so the client can play the finding beat only once.
  """
  @spec record(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil) :: {:ok, :new | :already}
  def record(user_id, discovery_id, world_id \\ nil) when is_binary(user_id) and is_binary(discovery_id) do
    row = %{
      user_id: user_id,
      discovery_id: discovery_id,
      world_id: world_id,
      inserted_at: DateTime.utc_now()
    }

    # insert_all reports how many rows it actually wrote: 0 means the pair already existed.
    case Repo.insert_all(Discovery, [row], on_conflict: :nothing, conflict_target: [:user_id, :discovery_id]) do
      {1, _} -> {:ok, :new}
      {0, _} -> {:ok, :already}
    end
  end

  @doc """
  Whether a claim of `discovery_id` should be honoured in a world with this spec `core`, for a player
  last seen at `pos` (`[x, y]`, or nil if they haven't moved yet). The world must author that secret
  (`core.secret.id`), and the player must be within its `radius` (default 120) of its `position` — so
  a secret can't be claimed from another world, or from across the maze.
  """
  @spec claimable?(map(), String.t(), list() | nil) :: boolean()
  def claimable?(core, discovery_id, pos) when is_map(core) and is_binary(discovery_id) do
    with %{"id" => ^discovery_id, "position" => [sx, sy | _]} = secret <- Map.get(core, "secret"),
         [px, py | _] when is_number(px) and is_number(py) <- pos do
      radius = Map.get(secret, "radius", 120)
      :math.sqrt((px - sx) * (px - sx) + (py - sy) * (py - sy)) <= radius
    else
      _ -> false
    end
  end

  def claimable?(_core, _discovery_id, _pos), do: false
end
