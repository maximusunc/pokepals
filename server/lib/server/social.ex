defmodule Server.Social do
  @moduledoc """
  The social side of the world channel, kept out of `Server.WorldChannel` so the channel stays a thin
  router: the friends snapshot a client renders, who's online and who's home, and the decisions behind
  invites, visits and the safety controls (FR-0..FR-5).

  "Online" is a Presence topic every connected player is tracked on (whichever world they're in), and
  "home now" is simply being in the roster of your own home's world topic.
  """
  alias Server.{Friends, Homes, HomeWorld, Presence, Profiles}

  @online_topic "online"

  @doc "Track this channel's player as online (called on every world join)."
  @spec track_online(pid(), Ecto.UUID.t()) :: :ok
  def track_online(pid, user_id) do
    case Presence.track(pid, @online_topic, user_id, %{}) do
      {:ok, _ref} -> :ok
      {:error, {:already_tracked, _, _, _}} -> :ok
      _ -> :ok
    end
  end

  @doc "Whether a player is connected anywhere."
  @spec online?(Ecto.UUID.t(), map()) :: boolean()
  def online?(user_id, online \\ Presence.list(@online_topic)), do: Map.has_key?(online, user_id)

  @doc "Whether a player is in their own home right now."
  @spec home_now?(Ecto.UUID.t()) :: boolean()
  def home_now?(user_id), do: Map.has_key?(Presence.list("world:" <> HomeWorld.world_id(user_id)), user_id)

  @doc "Who is in `owner`'s home right now, other than the owner."
  @spec visitors(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def visitors(owner) do
    "world:" <> HomeWorld.world_id(owner) |> Presence.list() |> Map.keys() |> Enum.reject(&(&1 == owner))
  end

  @doc """
  Everything a client shows about its social world, in one push (`friends`): its friends (name,
  whether they're playing, whether they're home), incoming requests, who it has asked, who it has
  blocked, and whether its own home is closed.
  """
  @spec snapshot(Ecto.UUID.t()) :: map()
  def snapshot(user_id) do
    online = Presence.list(@online_topic)
    friends = Friends.friend_ids(user_id)
    incoming = Friends.incoming(user_id)
    names = Profiles.names(Enum.uniq(friends ++ incoming))

    %{
      friends:
        Enum.map(friends, fn id ->
          %{id: id, name: names[id], online: online?(id, online), home_now: home_now?(id)}
        end),
      incoming: Enum.map(incoming, &%{id: &1, name: names[&1]}),
      outgoing: Friends.outgoing(user_id),
      blocked: Friends.blocked(user_id),
      home_closed: Homes.get(user_id).closed
    }
  end

  @doc """
  Whether `user` may read `owner`'s journal: their own; a home they may visit; or the home they're
  standing in right now (a one-off guest's pass is used up on entry, but they're still welcome to the
  book while they're there).
  """
  @spec can_read_journal?(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) :: boolean()
  def can_read_journal?(user, owner, current_world_id) do
    user == owner or current_world_id == HomeWorld.world_id(owner) or Homes.can_visit?(user, owner)
  end

  @doc """
  Send everyone but the owner out of `owner`'s home (closing it, or a removal or block).
  `only` limits it to particular players.
  """
  @spec evict(Ecto.UUID.t(), [Ecto.UUID.t()] | :all) :: :ok
  def evict(owner, only \\ :all) do
    targets = if only == :all, do: visitors(owner), else: only
    Enum.each(targets, &Friends.notify(&1, {:evicted, HomeWorld.world_id(owner)}))
  end
end
