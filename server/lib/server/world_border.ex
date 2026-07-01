defmodule Server.WorldBorder do
  @moduledoc """
  The world's BORDER TREELINE positions — a jittered ring of trees just inside the bounds, so the world
  reads as enclosed rather than ending at the void. This used to be generated on the client (for both
  drawing and collision); it now lives here so the SERVER is the single source of truth: the ring is
  baked into each world's spec as `border_trees` (a list of `[x, y]`), the client draws + collides its
  avatars against those exact points, and the ambient-pal sim avoids the very same trees.

  Because the server is now authoritative, there's no client RNG to match — this uses its own fixed
  Elixir seed, so the ring is deterministic (identical every seed, stable `etag`). The geometry mirrors
  the old client `Solids.border_positions`: `rows` concentric rectangles stepped inward from `inset` by
  `row_gap`, trees placed every `spacing` along each edge and jittered up to `jitter`.
  """

  # A fixed seed so the ring is identical on every (re)seed — keeps the spec's content etag stable.
  @seed {0xBEEF, 1, 1}

  @doc """
  The border-ring tree positions for a world, as `[[x, y], …]`. `bounds` is the spec's
  `%{"min" => [x, y], "max" => [x, y]}`; `cfg` is its `border` block. Returns `[]` when the world has no
  ring (no/blank border, or `ring: false`).
  """
  def positions(bounds, cfg) do
    with %{"min" => [minx, miny | _], "max" => [maxx, maxy | _]} <- bounds,
         true <- is_map(cfg) and map_size(cfg) > 0 and Map.get(cfg, "ring", true) == true do
      build(num(minx), num(miny), num(maxx), num(maxy), cfg)
    else
      _ -> []
    end
  end

  defp build(minx, miny, maxx, maxy, cfg) do
    spacing = num(Map.get(cfg, "spacing", 130.0))
    inset = num(Map.get(cfg, "inset", 20.0))
    jitter = num(Map.get(cfg, "jitter", 34.0))
    rows = trunc(num(Map.get(cfg, "rows", 2)))
    row_gap = num(Map.get(cfg, "row_gap", 64.0))
    rows_list = if rows > 0, do: Enum.to_list(0..(rows - 1)), else: []

    # The un-jittered base points, ring by ring, in a stable order (top+bottom along x, then left+right
    # down y) — then a single RNG pass jitters each, so the whole ring is one deterministic stream.
    bases =
      Enum.flat_map(rows_list, fn row ->
        pad = inset + row * row_gap
        rminx = minx + pad
        rminy = miny + pad
        rmaxx = maxx - pad
        rmaxy = maxy - pad

        if rmaxx - rminx <= 0.0 or rmaxy - rminy <= 0.0 do
          []
        else
          xs = seq(rminx, rmaxx, spacing)
          ys = seq_excl(rminy + spacing, rmaxy, spacing)
          top_bottom = Enum.flat_map(xs, fn x -> [{x, rminy}, {x, rmaxy}] end)
          left_right = Enum.flat_map(ys, fn y -> [{rminx, y}, {rmaxx, y}] end)
          top_bottom ++ left_right
        end
      end)

    {pts, _rng} =
      Enum.reduce(bases, {[], :rand.seed_s(:exsp, @seed)}, fn {bx, by}, {acc, rng} ->
        {dx, rng} = rand_range(rng, -jitter, jitter)
        {dy, rng} = rand_range(rng, -jitter, jitter)
        {[[bx + dx, by + dy] | acc], rng}
      end)

    Enum.reverse(pts)
  end

  # from, from+step, … while <= to (inclusive) — matches the client's `while x <= rect.end.x` sweep.
  defp seq(from, to, step) do
    if step > 0, do: do_seq(from, to, step, []), else: []
  end

  defp do_seq(x, to, step, acc) when x <= to, do: do_seq(x + step, to, step, [x | acc])
  defp do_seq(_x, _to, _step, acc), do: Enum.reverse(acc)

  # from, from+step, … while < to (exclusive) — matches the client's `while y < rect.end.y` sweep.
  defp seq_excl(from, to, step) do
    if step > 0, do: do_seq_excl(from, to, step, []), else: []
  end

  defp do_seq_excl(y, to, step, acc) when y < to, do: do_seq_excl(y + step, to, step, [y | acc])
  defp do_seq_excl(_y, _to, _step, acc), do: Enum.reverse(acc)

  defp rand_range(rng, lo, hi) do
    {r, rng} = :rand.uniform_s(rng)
    {lo + r * (hi - lo), rng}
  end

  defp num(n) when is_number(n), do: n * 1.0
  defp num(_), do: 0.0
end
