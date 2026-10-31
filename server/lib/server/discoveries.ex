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
  @spec record(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil, keyword()) :: {:ok, :new | :already}
  def record(user_id, discovery_id, world_id \\ nil, opts \\ []) when is_binary(user_id) and is_binary(discovery_id) do
    row = %{
      user_id: user_id,
      discovery_id: discovery_id,
      world_id: world_id,
      together: Keyword.get(opts, :together, false),
      with_ids: Keyword.get(opts, :with_ids, []),
      card: Keyword.get(opts, :card, %{}),
      inserted_at: DateTime.utc_now()
    }

    # insert_all reports how many rows it actually wrote: 0 means the pair already existed.
    case Repo.insert_all(Discovery, [row], on_conflict: :nothing, conflict_target: [:user_id, :discovery_id]) do
      {1, _} -> {:ok, :new}
      {0, _} -> {:ok, :already}
    end
  end

  @doc """
  Every find of a player as an ordered list of `{discovery_id, card}` (oldest first), with the
  card's `together` flag folded in. A find recorded before cards existed (the first hedge seeds) gets
  its card from `legacy` (the home template's `legacy_cards`), so it still has a keepsake.
  """
  @spec cards(Ecto.UUID.t(), map()) :: [{String.t(), map()}]
  def cards(user_id, legacy \\ %{}) when is_binary(user_id) do
    Repo.all(
      from(d in Discovery,
        where: d.user_id == ^user_id,
        order_by: [asc: d.inserted_at, asc: d.discovery_id],
        select: {d.discovery_id, d.card, d.together}
      )
    )
    |> Enum.map(fn {id, card, together} ->
      card = if map_size(card || %{}) == 0, do: Map.get(legacy, id, %{}), else: card
      {id, Map.put(card, "together", together)}
    end)
  end

  @doc """
  A player's JOURNAL (HS-5): every find, newest first, as entries ready to show: the keepsake and its
  found line, the world it came from (to travel back to), when, and the friends who were there.
  """
  @spec journal(Ecto.UUID.t(), map()) :: [map()]
  def journal(user_id, legacy \\ %{}) when is_binary(user_id) do
    rows =
      Repo.all(
        from(d in Discovery,
          where: d.user_id == ^user_id,
          order_by: [desc: d.inserted_at, desc: d.discovery_id],
          select: %{id: d.discovery_id, world_id: d.world_id, card: d.card, with_ids: d.with_ids, at: d.inserted_at}
        )
      )

    names = rows |> Enum.flat_map(& &1.with_ids) |> Enum.uniq() |> Server.Profiles.names()

    Enum.map(rows, fn r ->
      card = if map_size(r.card || %{}) == 0, do: Map.get(legacy, r.id, %{}), else: r.card
      k = Map.get(card, "keepsake", %{})

      %{
        id: r.id,
        world_id: r.world_id || Map.get(card, "world_id"),
        world_name: Map.get(card, "world_name", "somewhere"),
        found_line: Map.get(card, "found_line", ""),
        keepsake: Map.take(k, ["label", "type", "color"]),
        found_at: Date.to_iso8601(DateTime.to_date(r.at)),
        with: Enum.map(r.with_ids, &Map.get(names, &1))
      }
    end)
  end

  @doc """
  The snapshot card stored with a new find, taken from the world's `secret` block: the world's name,
  the found line, its qualities (1 to 3 of the core set), and its keepsake.
  """
  @spec card_for(map(), Ecto.UUID.t() | nil, String.t()) :: map()
  def card_for(secret, world_id, world_name) when is_map(secret) do
    %{
      "world_id" => world_id,
      "world_name" => world_name,
      "found_line" => Map.get(secret, "found_line", ""),
      "qualities" => secret |> Map.get("qualities", []) |> Enum.filter(&is_binary/1) |> Enum.take(3),
      "keepsake" => Map.get(secret, "keepsake", %{})
    }
  end

  @doc """
  "Found together" with the companion (HS-3/S-4): was it within `radius` of the player when they took
  the find? Reads the player's last streamed transform (`p` = player, `c` = companion).
  """
  @spec together?(map(), number()) :: boolean()
  def together?(transform, radius \\ 140) do
    within?(Map.get(transform, "p"), Map.get(transform, "c"), radius)
  end

  @doc """
  "With whom" (S-4/HS-5): which of `friend_ids` stood within `radius` (about a screen) of the player
  when they took the find, from the world's latest transforms (`%{user_id => transform}`).
  """
  @spec nearby_friends(map(), Ecto.UUID.t(), [Ecto.UUID.t()], number()) :: [Ecto.UUID.t()]
  def nearby_friends(transforms, user_id, friend_ids, radius \\ 720) do
    me = transforms |> Map.get(user_id, %{}) |> Map.get("p")

    Enum.filter(friend_ids, fn id ->
      within?(me, transforms |> Map.get(id, %{}) |> Map.get("p"), radius)
    end)
  end

  defp within?([ax, ay | _], [bx, by | _], radius) when is_number(ax) and is_number(ay) and is_number(bx) and is_number(by) do
    :math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by)) <= radius
  end

  defp within?(_a, _b, _radius), do: false

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
