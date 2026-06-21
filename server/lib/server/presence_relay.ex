defmodule Server.PresenceRelay do
  @moduledoc """
  One process per connected client (the WebSock behaviour). It assigns the client an id via the
  Hub, subscribes to the shared "world" topic, and relays presentation frames between clients:

    * on connect: push `welcome` (our id + the current roster), and broadcast `join` to others.
    * `identity` in  → store in the Hub, broadcast it id-stamped to others.
    * `state` in     → broadcast it id-stamped to others (not stored; ~20 Hz, newest wins).
    * on disconnect: drop from the Hub, broadcast `leave`.

  The id stamped onto every relayed frame comes from the Hub, never from the client payload, so a
  client can't impersonate another. The server routes presentation only — it never simulates
  movement or runs the companion. Discrete, validated world-events are a later Rung-4 step; they
  drop in here as one more `handle_in` clause on the same dispatch-by-"t" shape.
  """
  @behaviour WebSock
  require Logger

  @topic "world"

  @impl true
  def init(_opts) do
    {id, peers} = Server.Hub.join()
    Phoenix.PubSub.subscribe(Server.PubSub, @topic)
    # Tell everyone already here that we've arrived (we filter our own copy out in handle_info).
    broadcast(id, %{t: "join", id: id})
    welcome = Jason.encode!(%{t: "welcome", id: id, peers: peers})
    {:push, {:text, welcome}, %{id: id}}
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, %{"t" => "identity"} = msg} ->
        # Relay only the known identity fields, id-stamped; store it so late joiners learn it.
        identity = Map.take(msg, ["name", "appearance", "companion_look"])
        Server.Hub.put_identity(state.id, identity)
        broadcast(state.id, Map.merge(identity, %{"t" => "identity", "id" => state.id}))
        {:ok, state}

      {:ok, %{"t" => "state"} = msg} ->
        # Stamp our id (overwriting anything the client claimed) and relay; never stored.
        broadcast(state.id, Map.put(msg, "id", state.id))
        {:ok, state}

      _ ->
        # Unknown or malformed frame: ignore rather than disconnect.
        {:ok, state}
    end
  end

  # Non-text frames are ignored.
  def handle_in(_other, state), do: {:ok, state}

  @impl true
  def handle_info({:relay, from_id, text}, state) do
    # Fan-out reaches every connection including the sender; the sender drops its own echo.
    if from_id == state.id do
      {:ok, state}
    else
      {:push, {:text, text}, state}
    end
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, %{id: id}) do
    Server.Hub.drop(id)
    broadcast(id, %{t: "leave", id: id})
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # Fan a frame out to every connection on the topic, JSON-encoded once.
  defp broadcast(from_id, payload) do
    Phoenix.PubSub.broadcast(Server.PubSub, @topic, {:relay, from_id, Jason.encode!(payload)})
  end
end
