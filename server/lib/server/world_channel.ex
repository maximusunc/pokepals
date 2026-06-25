defmodule Server.WorldChannel do
  @moduledoc """
  The (still single) shared world, as a Phoenix Channel — one channel process per connected client.
  It replaces the hand-rolled `PresenceRelay`; the wire frames the Godot client sees are unchanged in
  meaning, only now they're channel events instead of raw JSON.

  The client is identified to its peers by its `user_id` (resolved from the token at connect) — that
  is also the Presence roster key, so a player is one roster entry regardless of the connection. On
  `:after_join` we:

    * `Presence.track` ourselves under our `user_id` (with an empty identity meta), and
    * push `welcome` (our id + the current roster) and `load` (our canonical companion + appearance,
      loaded from Postgres by that same `user_id` — no client "hello" needed).

  Thereafter:

    * `identity` in  → `Presence.update` our meta; the resulting diff carries it to peers.
    * `state` in     → cast our transform to `Server.World`, which stores it and fans it out over
      PubSub; we push peers' transforms (skipping our own echo) via `handle_info`.
    * `save` in      → persist the companion/appearance under our `user_id` (the canonical write).
    * `presence_diff` → translated by `PresenceFrames` into `join`/`identity`/`leave` pushes.

  Live transforms now flow through `Server.World` (the world-as-a-process seam) rather than a direct
  channel broadcast, so the world holds an authoritative snapshot. On join we replay that snapshot to
  the newcomer, so existing peers appear at their real positions immediately instead of popping in.

  The server stamps the sender id on every relayed frame; clients never send their own id, so a peer
  can't impersonate another. Incoming payloads are untrusted — the world clamps/validates them.
  """
  use Phoenix.Channel
  alias Server.{Presence, PresenceFrames, Saves, World}

  @topic "world"

  # We translate presence diffs into the client's frames rather than forwarding the raw CRDT diff.
  intercept ["presence_diff"]

  @impl true
  def join(@topic, _payload, socket) do
    send(self(), :after_join)
    {:ok, assign(socket, :known, MapSet.new())}
  end

  @impl true
  def handle_info(:after_join, socket) do
    user_id = socket.assigns.user_id

    # Subscribe to the world's live-transform fan-out, then track ourselves in the roster.
    Phoenix.PubSub.subscribe(Server.PubSub, World.state_topic())
    {:ok, _ref} = Presence.track(socket, user_id, %{identity: %{}})

    peers = PresenceFrames.peers(Presence.list(@topic), user_id)
    known = MapSet.new(peers, & &1.id)
    push(socket, "welcome", %{id: user_id, peers: peers})

    save = Saves.load(user_id)
    push(socket, "load", %{companion: save.companion, appearance: save.appearance})

    # Replay the current world snapshot so existing peers appear at their real positions at once
    # (their puppets, spawned from the roster above, get an immediate `state` rather than waiting for
    # the next ~20 Hz tick). Our own entry is skipped.
    for {peer_id, transform} <- World.snapshot(), peer_id != user_id do
      push(socket, "state", Map.put(transform, "id", peer_id))
    end

    {:noreply, assign(socket, :known, known)}
  end

  # A live transform from the world: push it to our client unless it's our own echo.
  def handle_info({:world_state, from_user, transform}, socket) do
    if from_user == socket.assigns.user_id do
      {:noreply, socket}
    else
      push(socket, "state", Map.put(transform, "id", from_user))
      {:noreply, socket}
    end
  end

  # Anything else that reaches the channel process (stray PubSub, etc.) is ignored.
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    # Drop our transform from the world so we aren't shown to future joiners. (Presence handles the
    # roster leave on its own.) The socket may not have a user_id if connect/join never completed.
    case socket.assigns do
      %{user_id: user_id} -> World.forget(user_id)
      _ -> :ok
    end

    :ok
  end

  @impl true
  def handle_in("identity", payload, socket) do
    # Store identity in our Presence meta; the resulting diff carries it to the other clients.
    identity = Map.take(payload, ["name", "appearance", "companion_look"])

    {:ok, _ref} =
      Presence.update(socket, socket.assigns.user_id, fn meta ->
        Map.put(meta, :identity, identity)
      end)

    {:noreply, socket}
  end

  def handle_in("state", payload, socket) do
    # Transforms are transient, not roster data: hand ours to the world process, which stores it and
    # fans it out over PubSub to every channel (each drops its own echo in handle_info).
    World.update_transform(socket.assigns.user_id, payload)
    {:noreply, socket}
  end

  def handle_in("save", payload, socket) do
    # The canonical write, keyed by the user_id the socket authenticated as.
    Saves.store(socket.assigns.user_id, payload["companion"], payload["appearance"])
    {:noreply, socket}
  end

  # Unknown frame: ignore rather than crash the channel.
  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  @impl true
  def handle_out("presence_diff", %{joins: joins, leaves: leaves}, socket) do
    {frames, known} = PresenceFrames.diff_to_frames(socket.assigns.user_id, socket.assigns.known, joins, leaves)
    Enum.each(frames, fn {event, payload} -> push(socket, event, payload) end)
    {:noreply, assign(socket, :known, known)}
  end
end
