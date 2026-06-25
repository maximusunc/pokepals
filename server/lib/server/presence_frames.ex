defmodule Server.PresenceFrames do
  @moduledoc """
  Pure translation from `Phoenix.Presence` diffs into the client's wire frames. This is the one
  subtle piece of the roster: a presence diff must become exactly the `join` / `identity` / `leave`
  events the Godot client understands, with no double-spawns and no ghosts. No sockets, no Presence,
  no DB — so it's unit-tested directly (`Server.PresenceFramesTest`).

  `Server.WorldChannel` calls `diff_to_frames/4` in `handle_out("presence_diff", ...)` and pushes
  each returned `{event, payload}` to the client; it uses `identity_from_metas/1` and `peers/2` to
  build the one-shot `welcome` roster.

  Roster keys are the per-connection integer id (minted by `Server.Hub`) stringified — that integer
  is the peer id on the wire, so the presentation layer (which formats peer ids with `%d`) is
  untouched. The owning `user_id` rides in each meta but never reaches a peer.
  """

  @type frame :: {event :: String.t(), payload :: map()}

  @doc """
  Translate a presence diff into `{event, payload}` frames, given the peer ids we've already told
  this client about (`known`). Returns `{frames, known}`.

  A key in BOTH `joins` and `leaves` is a metadata update (identity changed), not a real
  leave/join — handled as identity-only, never a despawn+respawn. Keys in leaves-only are real
  leaves; keys in joins-only are real joins (and may already be `known` if a peer's join raced our
  `welcome` snapshot — then we send only its identity, never a second join).
  """
  @spec diff_to_frames(integer(), MapSet.t(), map(), map()) :: {[frame()], MapSet.t()}
  def diff_to_frames(my_id, known, joins, leaves) do
    updated = MapSet.intersection(MapSet.new(Map.keys(joins)), MapSet.new(Map.keys(leaves)))

    {leave_frames, known} =
      keys_minus(leaves, updated)
      |> Enum.reduce({[], known}, fn key, {frames, known} ->
        id = String.to_integer(key)

        if id != my_id and MapSet.member?(known, id) do
          {[{"leave", %{id: id}} | frames], MapSet.delete(known, id)}
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
            {[{"join", %{id: id}} | identity_frames(id, joins[key])] ++ frames,
             MapSet.put(known, id)}
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

  @doc """
  Shape a `Phoenix.Presence.list/1` result into the `welcome` roster (peers other than `my_id`),
  each `%{id: integer, identity: map}`.
  """
  @spec peers(map(), integer()) :: [map()]
  def peers(presence_list, my_id) do
    presence_list
    |> Enum.reject(fn {key, _} -> String.to_integer(key) == my_id end)
    |> Enum.map(fn {key, %{metas: metas}} ->
      %{id: String.to_integer(key), identity: identity_from_metas(metas)}
    end)
  end

  @doc "The identity map carried by the head meta of a presence entry (or `%{}`)."
  @spec identity_from_metas([map()]) :: map()
  def identity_from_metas([%{identity: ident} | _]), do: ident
  def identity_from_metas(_), do: %{}

  # Keys of `map` that are not in the `exclude` set.
  defp keys_minus(map, exclude), do: Enum.reject(Map.keys(map), &MapSet.member?(exclude, &1))

  # An `identity` frame for `id` if its meta carries a non-empty identity, else nothing.
  defp identity_frames(id, %{metas: metas}) do
    case identity_from_metas(metas) do
      ident when is_map(ident) and map_size(ident) > 0 -> [{"identity", Map.put(ident, :id, id)}]
      _ -> []
    end
  end

  defp identity_frames(_id, _), do: []
end
