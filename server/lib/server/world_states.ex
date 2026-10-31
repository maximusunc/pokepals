defmodule Server.WorldStates do
  @moduledoc """
  SC-3 (docs/scaling-design.md): the compact wire form of players' live transforms, and the small
  amount of tidying a transform gets before the server keeps or relays it. Pure functions, no state.

  Before SC-3 every movement packet was relayed the moment it arrived, separately to every other
  player, re-encoded as JSON for each one: N × (N − 1) × 20 encodes a second, which is what broke
  the server at ~75 players in one world (SC-1). Now `Server.World` keeps each player's latest
  transform, and on a fixed tick sends ONE bundle of everything that changed, encoded once for
  everyone. This module is that bundle's format:

      "states" %{s: [[id, px, py, fx, fy, cx, cy, lx, ly], ...]}

  - `p`  the player's position (`px, py`), whole pixels; the client eases between updates anyway
  - `pf` the player's facing (`fx, fy`), two decimals
  - `c`  the companion's position (`cx, cy`), whole pixels
  - `cl` the companion's look direction (`lx, ly`), two decimals
  - a field the client didn't send is `nil` in its slots
  - a tenth slot, if present, is a send timestamp the load-test bots stamp (`t`); real clients don't

  A positional array instead of a map with keys roughly halves the bytes per entry.

  `sanitize/1` keeps only those known fields, each a pair of finite numbers within a sane range, so
  nothing else a client puts in its packet is stored or relayed to everyone.
  """

  @fields [{"p", 0}, {"pf", 2}, {"c", 0}, {"cl", 2}]
  @limit 1.0e6

  @doc "The known fields of a client transform, cleaned and rounded; `nil` if nothing usable is left."
  @spec sanitize(term()) :: map() | nil
  def sanitize(transform) when is_map(transform) do
    clean =
      for {key, decimals} <- @fields, pair <- [pair(Map.get(transform, key), decimals)], pair != nil, into: %{} do
        {key, pair}
      end

    clean =
      case Map.get(transform, "t") do
        t when is_integer(t) and t >= 0 -> Map.put(clean, "t", t)
        _ -> clean
      end

    if map_size(clean) == 0, do: nil, else: clean
  end

  def sanitize(_), do: nil

  @doc "One bundle entry for a player's transform: `[id, px, py, fx, fy, cx, cy, lx, ly]` (+ `t`)."
  @spec entry(String.t(), map()) :: list()
  def entry(id, transform) do
    base =
      [id] ++
        Enum.flat_map(@fields, fn {key, _} ->
          case Map.get(transform, key) do
            [x, y] -> [x, y]
            _ -> [nil, nil]
          end
        end)

    case Map.get(transform, "t") do
      nil -> base
      t -> base ++ [t]
    end
  end

  @doc "The `\"states\"` payload for a map of `%{user_id => transform}`."
  @spec bundle(map()) :: map()
  def bundle(transforms) do
    %{s: for({id, t} <- transforms, do: entry(id, t))}
  end

  defp pair([x, y], decimals) when is_number(x) and is_number(y) do
    if abs(x) <= @limit and abs(y) <= @limit, do: [round_to(x, decimals), round_to(y, decimals)], else: nil
  end

  defp pair(_, _), do: nil

  defp round_to(v, 0), do: round(v)
  defp round_to(v, d), do: Float.round(v * 1.0, d)
end
