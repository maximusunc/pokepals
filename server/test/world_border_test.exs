defmodule Server.WorldBorderTest do
  @moduledoc """
  The server-side border-treeline generator: a deterministic jittered ring baked into each world spec so
  the client draws + collides against it and the ambient-pal sim avoids it — one source of truth.
  """
  use ExUnit.Case, async: true
  alias Server.WorldBorder

  @bounds %{"min" => [-1000, -1000], "max" => [1000, 1000]}
  @cfg %{"ring" => true, "spacing" => 132, "inset" => 18, "jitter" => 34, "rows" => 2, "row_gap" => 62}

  test "generates a non-empty, deterministic ring of [x, y] floats" do
    a = WorldBorder.positions(@bounds, @cfg)
    b = WorldBorder.positions(@bounds, @cfg)
    assert length(a) > 0
    assert a == b
    assert Enum.all?(a, fn [x, y] -> is_float(x) and is_float(y) end)
  end

  test "points sit in the border band, within a jitter of the bounds" do
    j = 34

    for [x, y] <- WorldBorder.positions(@bounds, @cfg) do
      assert x >= -1000 - j and x <= 1000 + j
      assert y >= -1000 - j and y <= 1000 + j
    end
  end

  test "no ring → no trees" do
    assert WorldBorder.positions(@bounds, %{}) == []
    assert WorldBorder.positions(@bounds, %{"ring" => false}) == []
    assert WorldBorder.positions(nil, @cfg) == []
    assert WorldBorder.positions(%{"min" => [0, 0], "max" => [10, 10]}, Map.put(@cfg, "rows", 0)) == []
  end
end
