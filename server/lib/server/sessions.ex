defmodule Server.Sessions do
  @moduledoc """
  One live session per player: the newest connection wins (issue 175). Two devices playing the same
  companion at once would fight over where it is and what it carries, so when a socket connects, any
  older socket of the same player is told `superseded` and dropped. A device that has been signed out
  is told `signed_out` and dropped the same way.

  How the word reaches the old client BEFORE its socket closes: the message goes out on the player's
  own PubSub topic (`Server.Friends.user_topic/1`), which every one of their channels listens on. Each
  channel then pushes the event to its client and only afterwards sends its own socket process the
  `disconnect` broadcast. Both messages travel from that one channel process to that one socket
  process, and Erlang keeps messages between a pair of processes in order, so the socket writes the
  push frame before it closes. (A plain `Endpoint.broadcast("user_socket:...", "disconnect")` would
  race the push and could close the socket first.) The new socket is never hit: it has no channel yet
  when the word goes out, and the generation check below spares anything newer.

  A socket caught with no channel open (between leaving one world and joining the next) hears nothing
  then; so every join first asks `check/1`, which compares the socket's generation with the account's
  (`accounts.session_gen`, bumped atomically in Postgres on every connect, so it works across nodes)
  and whether its device is still signed in. A stale socket's join is accepted and then immediately
  ends the same way: push, then disconnect.
  """
  import Ecto.Query
  alias Server.{Account, Device, Friends, Repo}

  @doc """
  A socket for `user_id` has just connected: take the next session generation and
  tell the player's older sockets they've been replaced. Returns the new generation.
  """
  @spec begin(Ecto.UUID.t()) :: integer()
  def begin(user_id) do
    {1, [gen]} =
      Repo.update_all(
        from(a in Account, where: a.user_id == ^user_id, select: a.session_gen),
        inc: [session_gen: 1]
      )

    Friends.notify(user_id, {:superseded, gen})
    gen
  end

  @doc """
  Whether a socket (by its assigns) may still play: `:ok`, `:superseded` (a newer connection took
  over) or `:signed_out` (its device was signed out).
  """
  @spec check(map()) :: :ok | :superseded | :signed_out
  def check(%{user_id: user_id, device_id: device_id, session_gen: gen}) do
    row =
      Repo.one(
        from(a in Account,
          left_join: d in Device,
          on: d.device_id == ^device_id and d.user_id == a.user_id,
          where: a.user_id == ^user_id,
          select: {a.session_gen, d.device_id, d.revoked_at}
        )
      )

    case row do
      nil -> :signed_out
      {_, nil, _} -> :signed_out
      {_, _, %DateTime{}} -> :signed_out
      {current, _, nil} when current > gen -> :superseded
      _ -> :ok
    end
  end

  # A socket made without connect/3 (only in tests) carries no session; nothing to check.
  def check(_assigns), do: :ok

  @doc """
  End this channel's socket: push `event` to its client, then close the socket. Called from the
  channel process, so the push is in the socket's mailbox before the disconnect (see the moduledoc).
  """
  @spec end_socket(Phoenix.Socket.t(), String.t()) :: :ok
  def end_socket(socket, event) do
    Phoenix.Channel.push(socket, event, %{})

    # The close waits a moment. Erlang's ordering already puts the push on the wire first, but a
    # client that reads the push and the close in one poll (Godot's WebSocketPeer) drops the unread
    # frame when it sees the close, so the two must not arrive together.
    Process.send_after(
      socket.transport_pid,
      %Phoenix.Socket.Broadcast{topic: socket.id, event: "disconnect", payload: %{}},
      close_delay_ms()
    )

    :ok
  end

  defp close_delay_ms, do: Application.get_env(:server, __MODULE__, [])[:close_delay_ms] || 1_000
end
