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
    * `state` in     → `broadcast_from` the transform (id-stamped) to the rest of the world.
    * `save` in      → persist the companion/appearance under our `user_id` (the canonical write).
    * `presence_diff` → translated by `PresenceFrames` into `join`/`identity`/`leave` pushes.

  The server stamps the sender id on every relayed frame; clients never send their own id, so a peer
  can't impersonate another. Incoming payloads are untrusted — the world clamps/validates them.
  """
  use Phoenix.Channel
  alias Server.{Presence, PresenceFrames, Saves}

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

    {:ok, _ref} = Presence.track(socket, user_id, %{identity: %{}})

    peers = PresenceFrames.peers(Presence.list(@topic), user_id)
    known = MapSet.new(peers, & &1.id)
    push(socket, "welcome", %{id: user_id, peers: peers})

    save = Saves.load(user_id)
    push(socket, "load", %{companion: save.companion, appearance: save.appearance})

    {:noreply, assign(socket, :known, known)}
  end

  # Anything else that reaches the channel process (stray PubSub, etc.) is ignored.
  def handle_info(_msg, socket), do: {:noreply, socket}

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
    # Transforms are transient, not roster data: stamp our id and fan out to the rest of the world
    # (broadcast_from excludes us, so there's no echo to drop client-side).
    broadcast_from!(socket, "state", Map.put(payload, "id", socket.assigns.user_id))
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
