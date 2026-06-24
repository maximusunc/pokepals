defmodule Server.PresenceRelay do
  @moduledoc """
  One process per connected client (the WebSock behaviour). The roster now lives in
  `Server.Presence` (a CRDT); this module is the **adapter** that translates Presence's
  join/leave/update diffs into the client's existing wire frames, so the Godot client is unchanged:

    * on connect: assign an id (`Server.Hub`), `Presence.track` ourselves, and push `welcome`
      (our id + the current roster from `Presence.list`).
    * `identity` in → `Presence.update` our meta (Presence broadcasts the diff; peers get `identity`).
    * `state` in    → plain PubSub fan-out on a separate topic (transforms aren't presence data).
    * `hello` in    → identify the player by their token and push back their canonical `load`.
    * `save` in     → persist the companion/wardrobe under that token (the server is the sole save).
    * presence diff → `welcome`/`join`/`identity`/`leave` frames via `diff_to_frames/4`.
    * on disconnect: nothing to do — Presence removes us automatically (even on a hard crash), which
      is the whole robustness win over the old hand-rolled roster.

  Ids are minted by `Server.Hub` and stamped server-side, never taken from the client payload, so a
  client still can't impersonate another.
  """
  @behaviour WebSock
  require Logger

  # Presence (roster) rides on this topic; the high-rate state relay rides on a separate one so the
  # CRDT's presence_diff broadcasts and our raw {:relay, ...} messages never mingle.
  @presence_topic "world"
  @state_topic "world:state"

  @impl true
  def init(_opts) do
    id = Server.Hub.next_id()
    Phoenix.PubSub.subscribe(Server.PubSub, @presence_topic)
    Phoenix.PubSub.subscribe(Server.PubSub, @state_topic)
    {:ok, _ref} = Server.Presence.track(self(), @presence_topic, Integer.to_string(id), %{identity: %{}})

    peers = current_peers(id)
    known = MapSet.new(peers, & &1.id)
    welcome = Jason.encode!(%{t: "welcome", id: id, peers: peers})
    {:push, {:text, welcome}, %{id: id, known: known, player_id: nil}}
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, %{"t" => "identity"} = msg} ->
        # Store identity in our Presence meta; the resulting diff carries it to the other clients.
        identity = Map.take(msg, ["name", "appearance", "companion_look"])

        Server.Presence.update(self(), @presence_topic, Integer.to_string(state.id), fn meta ->
          Map.put(meta, :identity, identity)
        end)

        {:ok, state}

      {:ok, %{"t" => "state"} = msg} ->
        # Transforms are transient, not roster data: stamp our id and fan out over the state topic.
        relay = Jason.encode!(Map.put(msg, "id", state.id))
        Phoenix.PubSub.broadcast(Server.PubSub, @state_topic, {:relay, state.id, relay})
        {:ok, state}

      {:ok, %{"t" => "hello", "player_id" => player_id}} when is_binary(player_id) ->
        # Identify this connection's player and return their canonical save (or nulls if new). The
        # token is point-to-point: stored in our state, never relayed to peers.
        save = Server.Saves.load(player_id)
        load = %{t: "load", companion: save && save.companion, appearance: save && save.appearance}
        {:push, {:text, Jason.encode!(load)}, %{state | player_id: player_id}}

      {:ok, %{"t" => "save"} = msg} ->
        # The canonical write. Ignored until the client has said hello (no token = no key).
        if state.player_id do
          Server.Saves.store(state.player_id, msg["companion"], msg["appearance"])
        end

        {:ok, state}

      _ ->
        # Unknown or malformed frame: ignore rather than disconnect.
        {:ok, state}
    end
  end

  # Non-text frames are ignored.
  def handle_in(_other, state), do: {:ok, state}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: %{joins: joins, leaves: leaves}}, state) do
    {frames, known} = diff_to_frames(state.id, state.known, joins, leaves)
    push_frames(frames, %{state | known: known})
  end

  def handle_info({:relay, from_id, text}, state) do
    # State fan-out reaches every connection including the sender; the sender drops its own echo.
    if from_id == state.id, do: {:ok, state}, else: {:push, {:text, text}, state}
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  # --- pure translation (unit-tested directly) ----------------------------------------------

  @doc """
  Translate a `Phoenix.Presence` diff into the client's wire frames, given the peer ids we've
  already told this client about (`known`). Pure — no sockets, no Presence — so it's unit-tested
  directly. Returns `{frames, known}` where `frames` is a list of maps ready to JSON-encode.

  A key appearing in BOTH joins and leaves is a metadata update (identity changed), not a real
  leave/join — so it must be handled as an identity update only, never a despawn+respawn. Keys in
  leaves-only are real leaves; keys in joins-only are real joins (and may already be `known` if a
  peer's join raced our `welcome` snapshot — then we send only its identity, never a second join).
  """
  @spec diff_to_frames(integer(), MapSet.t(), map(), map()) :: {[map()], MapSet.t()}
  def diff_to_frames(my_id, known, joins, leaves) do
    updated = MapSet.intersection(MapSet.new(Map.keys(joins)), MapSet.new(Map.keys(leaves)))

    {leave_frames, known} =
      keys_minus(leaves, updated)
      |> Enum.reduce({[], known}, fn key, {frames, known} ->
        id = String.to_integer(key)

        if id != my_id and MapSet.member?(known, id) do
          {[%{t: "leave", id: id} | frames], MapSet.delete(known, id)}
        else
          {frames, known}
        end
      end)

    {join_frames, known} =
      keys_minus(joins, updated)
      |> Enum.reduce({[], known}, fn key, {frames, known} ->
        id = String.to_integer(key)

        cond do
          id == my_id ->
            {frames, known}

          MapSet.member?(known, id) ->
            # Already announced (welcome/diff race) — only (re)send identity if present.
            {identity_frames(id, joins[key]) ++ frames, known}

          true ->
            {[%{t: "join", id: id} | identity_frames(id, joins[key])] ++ frames, MapSet.put(known, id)}
        end
      end)

    {update_frames, known} =
      Enum.reduce(updated, {[], known}, fn key, {frames, known} ->
        id = String.to_integer(key)

        if id != my_id do
          {identity_frames(id, joins[key]) ++ frames, MapSet.put(known, id)}
        else
          {frames, known}
        end
      end)

    {leave_frames ++ join_frames ++ update_frames, known}
  end

  # Keys of `map` that are not in the `exclude` set.
  defp keys_minus(map, exclude), do: Enum.reject(Map.keys(map), &MapSet.member?(exclude, &1))

  # An `identity` frame for `id` if its meta carries a non-empty identity, else nothing.
  defp identity_frames(id, %{metas: metas}) do
    case identity_from_metas(metas) do
      ident when is_map(ident) and map_size(ident) > 0 -> [Map.merge(ident, %{t: "identity", id: id})]
      _ -> []
    end
  end

  defp identity_frames(_id, _), do: []

  defp identity_from_metas([%{identity: ident} | _]), do: ident
  defp identity_from_metas(_), do: %{}

  # --- helpers ------------------------------------------------------------------------------

  # The current roster (excluding us), shaped for the `welcome` frame.
  defp current_peers(my_id) do
    Server.Presence.list(@presence_topic)
    |> Enum.reject(fn {key, _} -> String.to_integer(key) == my_id end)
    |> Enum.map(fn {key, %{metas: metas}} ->
      %{id: String.to_integer(key), identity: identity_from_metas(metas)}
    end)
  end

  defp push_frames([], state), do: {:ok, state}

  defp push_frames(frames, state) do
    {:push, Enum.map(frames, fn f -> {:text, Jason.encode!(f)} end), state}
  end
end
