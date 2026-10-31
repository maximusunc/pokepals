defmodule Server.Friends do
  @moduledoc """
  Friends and blocks (FR-1, FR-2, FR-5). Keyed by `user_id`, so like the companion and the wardrobe it
  needs no accounts: it hangs off the identity token.

    * A **request** waits until the other player accepts it. If they had already asked you, asking
      them back simply makes you friends.
    * A **friendship** is stored in both directions, so "my friends" is one lookup.
    * **Removing** a friend is quiet: they're not told, their list just loses you.
    * A **block** ends any friendship and pending requests between you, stops new requests and invites
      from them, and hides your home from them. It's one-directional and silent.

  Anything that changes a player's view is announced on their own PubSub topic (`user_topic/1`), which
  every one of their channels listens on, so a request or a removal reaches them in whatever world
  they're in.
  """
  import Ecto.Query
  alias Server.{Block, FriendRequest, Friendship, Repo}

  @doc "The PubSub topic one player's channels listen on for social events."
  @spec user_topic(Ecto.UUID.t()) :: String.t()
  def user_topic(user_id), do: "user:" <> user_id

  @doc "Tell one player's channels something (a request, an invite, a change to their list)."
  @spec notify(Ecto.UUID.t(), term()) :: :ok
  def notify(user_id, message) do
    Phoenix.PubSub.broadcast(Server.PubSub, user_topic(user_id), message)
  end

  @doc "Whether two players are friends."
  @spec friends?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def friends?(a, b) when is_binary(a) and is_binary(b) do
    Repo.exists?(from(f in Friendship, where: f.user_id == ^a and f.friend_id == ^b))
  end

  @doc "Whether either player has blocked the other."
  @spec blocked_either_way?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def blocked_either_way?(a, b) do
    Repo.exists?(
      from(bl in Block,
        where: (bl.blocker_id == ^a and bl.blocked_id == ^b) or (bl.blocker_id == ^b and bl.blocked_id == ^a)
      )
    )
  end

  @doc "A player's friends' user_ids."
  @spec friend_ids(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def friend_ids(user_id) do
    Repo.all(from(f in Friendship, where: f.user_id == ^user_id, order_by: f.inserted_at, select: f.friend_id))
  end

  @doc "Who has asked this player to be friends (user_ids), oldest first."
  @spec incoming(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def incoming(user_id) do
    Repo.all(from(r in FriendRequest, where: r.to_id == ^user_id, order_by: r.inserted_at, select: r.from_id))
  end

  @doc "Who this player has asked (user_ids)."
  @spec outgoing(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def outgoing(user_id) do
    Repo.all(from(r in FriendRequest, where: r.from_id == ^user_id, select: r.to_id))
  end

  @doc "Who this player has blocked (user_ids)."
  @spec blocked(Ecto.UUID.t()) :: [Ecto.UUID.t()]
  def blocked(user_id) do
    Repo.all(from(bl in Block, where: bl.blocker_id == ^user_id, select: bl.blocked_id))
  end

  @doc """
  `from` asks `to` to be friends. Returns:

    * `{:ok, :requested}` — the request is waiting for them;
    * `{:ok, :friends}` — they had already asked you, so now you're friends;
    * `{:error, :already_friends | :self | :blocked}`.

  A block in either direction answers `:blocked` to the sender, so a blocked player learns nothing
  more than that it didn't go through.
  """
  @spec request(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, :requested | :friends} | {:error, atom()}
  def request(from, to) when is_binary(from) and is_binary(to) do
    cond do
      from == to -> {:error, :self}
      blocked_either_way?(from, to) -> {:error, :blocked}
      friends?(from, to) -> {:error, :already_friends}
      pending?(to, from) -> accept(from, to)
      true ->
        Repo.insert_all(FriendRequest, [%{from_id: from, to_id: to, inserted_at: now()}], on_conflict: :nothing)
        notify(to, {:friends_changed})
        notify(from, {:friends_changed})
        {:ok, :requested}
    end
  end

  @doc "`user` accepts `from`'s request. `{:ok, :friends}`, or `{:error, :no_request}`."
  @spec accept(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, :friends} | {:error, :no_request}
  def accept(user, from) do
    if pending?(from, user) do
      Repo.transaction(fn ->
        delete_requests_between(user, from)
        t = now()

        Repo.insert_all(
          Friendship,
          [%{user_id: user, friend_id: from, inserted_at: t}, %{user_id: from, friend_id: user, inserted_at: t}],
          on_conflict: :nothing
        )
      end)

      notify(user, {:friends_changed})
      notify(from, {:friends_changed})
      {:ok, :friends}
    else
      {:error, :no_request}
    end
  end

  @doc "`user` declines `from`'s request (quietly: the sender's request just stops waiting)."
  @spec decline(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def decline(user, from) do
    Repo.delete_all(from(r in FriendRequest, where: r.from_id == ^from and r.to_id == ^user))
    notify(user, {:friends_changed})
    notify(from, {:friends_changed})
    :ok
  end

  @doc "`user` removes `friend`. Quiet: the other player isn't told, their list just loses you."
  @spec remove(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def remove(user, friend) do
    delete_friendship(user, friend)
    notify(user, {:friends_changed})
    notify(friend, {:friends_changed})
    :ok
  end

  @doc "`user` blocks `other`: ends any friendship and requests between you, and stops new ones."
  @spec block(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, :self}
  def block(user, user), do: {:error, :self}

  def block(user, other) do
    Repo.transaction(fn ->
      delete_friendship(user, other)
      delete_requests_between(user, other)
      Repo.insert_all(Block, [%{blocker_id: user, blocked_id: other, inserted_at: now()}], on_conflict: :nothing)
    end)

    notify(user, {:friends_changed})
    notify(other, {:friends_changed})
    :ok
  end

  @doc "`user` unblocks `other`."
  @spec unblock(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def unblock(user, other) do
    Repo.delete_all(from(bl in Block, where: bl.blocker_id == ^user and bl.blocked_id == ^other))
    notify(user, {:friends_changed})
    :ok
  end

  defp pending?(from, to) do
    Repo.exists?(from(r in FriendRequest, where: r.from_id == ^from and r.to_id == ^to))
  end

  defp delete_friendship(a, b) do
    Repo.delete_all(
      from(f in Friendship,
        where: (f.user_id == ^a and f.friend_id == ^b) or (f.user_id == ^b and f.friend_id == ^a)
      )
    )
  end

  defp delete_requests_between(a, b) do
    Repo.delete_all(
      from(r in FriendRequest,
        where: (r.from_id == ^a and r.to_id == ^b) or (r.from_id == ^b and r.to_id == ^a)
      )
    )
  end

  defp now, do: DateTime.utc_now()
end
