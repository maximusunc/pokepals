defmodule Server.WorldChannel do
  @moduledoc """
  One shared world, as a Phoenix Channel on the topic `"world:" <> world_id`. Multi-world: each world
  has its own topic, so Presence (the roster) and the live-transform fan-out are scoped per world —
  players in different worlds don't see each other. A client joins the channel for the world it is in
  and re-joins (leave + join) when it travels.

  On join we resolve the world's definition (catalog), ensure its live `Server.World` process exists,
  and on `:after_join`:

    * deliver the world SPEC — `world_spec` with the catalog's spec+version, UNLESS the client passed a
      matching `known_version` (then `world_spec_unchanged`, so cached specs aren't re-sent),
    * `Presence.track` ourselves on this world's topic and push `welcome` (this world's roster),
    * push `load` (our canonical companion + appearance — a per-USER concern, same in every world),
    * replay the world's transform `snapshot` so peers already moving appear at once.

  Thereafter: `identity` → Presence.update; `state` → cast to this world's `Server.World`; `save` →
  persist by user_id; presence diffs → join/identity/leave frames. The sender id is always
  server-stamped (the player's user_id); clients never send their own id.
  """
  use Phoenix.Channel
  alias Server.{Presence, PresenceFrames, Saves, World, Worlds}

  intercept ["presence_diff"]

  @impl true
  def join("world:" <> world_id, payload, socket) when world_id != "" do
    case Worlds.get(world_id) do
      nil ->
        {:error, %{reason: "unknown_world"}}

      definition ->
        World.ensure_started(world_id)
        known_version = Map.get(payload, "known_version", 0)
        send(self(), :after_join)

        {:ok,
         assign(socket, %{
           world_id: world_id,
           definition: definition,
           known_version: known_version,
           known: MapSet.new()
         })}
    end
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "bad_topic"}}

  @impl true
  def handle_info(:after_join, socket) do
    %{world_id: world_id, user_id: user_id, definition: definition, known_version: known_version} =
      socket.assigns

    # Deliver the spec (or confirm the client's cache is current).
    if definition.version == known_version do
      push(socket, "world_spec_unchanged", %{world_id: world_id, version: definition.version})
    else
      push(socket, "world_spec", Worlds.client_view(definition))
    end

    topic = "world:" <> world_id
    Phoenix.PubSub.subscribe(Server.PubSub, World.state_topic(world_id))
    {:ok, _ref} = Presence.track(socket, user_id, %{identity: %{}})

    peers = PresenceFrames.peers(Presence.list(topic), user_id)
    known = MapSet.new(peers, & &1.id)
    push(socket, "welcome", %{id: user_id, peers: peers})

    save = Saves.load(user_id)
    push(socket, "load", %{companion: save.companion, appearance: save.appearance})

    for {peer_id, transform} <- World.snapshot(world_id), peer_id != user_id do
      push(socket, "state", Map.put(transform, "id", peer_id))
    end

    {:noreply, assign(socket, :known, known)}
  end

  # A live transform from this world: push to our client unless it's our own echo.
  def handle_info({:world_state, from_user, transform}, socket) do
    if from_user == socket.assigns.user_id do
      {:noreply, socket}
    else
      push(socket, "state", Map.put(transform, "id", from_user))
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns do
      %{world_id: world_id, user_id: user_id} -> World.forget(world_id, user_id)
      _ -> :ok
    end

    :ok
  end

  @impl true
  def handle_in("identity", payload, socket) do
    identity = Map.take(payload, ["name", "appearance", "companion_look"])

    {:ok, _ref} =
      Presence.update(socket, socket.assigns.user_id, fn meta ->
        Map.put(meta, :identity, identity)
      end)

    {:noreply, socket}
  end

  def handle_in("state", payload, socket) do
    World.update_transform(socket.assigns.world_id, socket.assigns.user_id, payload)
    {:noreply, socket}
  end

  def handle_in("save", payload, socket) do
    Saves.store(socket.assigns.user_id, payload["companion"], payload["appearance"])
    {:noreply, socket}
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  @impl true
  def handle_out("presence_diff", %{joins: joins, leaves: leaves}, socket) do
    {frames, known} = PresenceFrames.diff_to_frames(socket.assigns.user_id, socket.assigns.known, joins, leaves)
    Enum.each(frames, fn {event, payload} -> push(socket, event, payload) end)
    {:noreply, assign(socket, :known, known)}
  end
end
