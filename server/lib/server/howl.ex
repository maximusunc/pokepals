defmodule Server.Howl do
  @moduledoc """
  The relay half of Hollowsong's howling (docs/home-world-and-secrets-design.md, "Hollowsong"). When a player's
  companion howls, everyone else in the world should see the canyon answer it too, so each client tells the
  server "I howled" and the server tells the others WHERE. Nothing is kept: the ripples are drawn from the
  world's own wall geometry on every client, and fade on their own.

  Minimal and server-stamped, like every other relayed action:

    * the client sends nothing but the event: the position is the server's own last-known position of that
      player (from their `state` packets), so a client cannot howl "from" somewhere it isn't;
    * only worlds whose spec has an `echo` secret relay howls at all (`echo_world?/1`);
    * a player is limited to one howl per `min_gap_ms` (`allow?/2`), so a client cannot flood the room.

  Pure functions; the channel holds the socket state.
  """

  @min_gap_ms 1_200

  @doc "Whether this world's spec has an echo secret (the only kind of world that relays howls)."
  @spec echo_world?(map()) :: boolean()
  def echo_world?(definition) do
    get_in(definition.spec, ["core", "secret", "reveal", "type"]) == "echo"
  end

  @doc "Whether a howl at `now_ms` is allowed, given the time of this player's last one (or nil)."
  @spec allow?(integer() | nil, integer()) :: boolean()
  def allow?(nil, _now_ms), do: true
  def allow?(last_ms, now_ms), do: now_ms - last_ms >= @min_gap_ms

  @doc "The relayed payload for a howl from `p` (`[x, y]`), or nil when the server doesn't know where they are."
  @spec payload([number()] | nil) :: map() | nil
  def payload([x, y]) when is_number(x) and is_number(y), do: %{x: x, y: y}
  def payload(_), do: nil
end
