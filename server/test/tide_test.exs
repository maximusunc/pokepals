defmodule Server.TideTest do
  use ExUnit.Case, async: true
  alias Server.Tide

  # The SAME vectors the client's TideClock is held to (pokepals/tests/world_fixtures/tide_vectors.json): if
  # these ever disagree, the server and the clients no longer share a tide.
  @vectors Path.join([__DIR__, "fixtures", "tide_vectors.json"]) |> File.read!() |> Jason.decode!()

  defp near(a, b, eps \\ 1.0e-9), do: abs(a - b) <= eps

  test "the low window's half width matches the reference" do
    assert near(Tide.low_half_s(@vectors["params"]), @vectors["low_half_s"])
  end

  test "phase, cycle, level, the low window (with and without grace) and the countdown agree with the reference" do
    params = @vectors["params"]

    for v <- @vectors["vectors"] do
      t = v["t"]
      assert near(Tide.phase(params, t), v["phase"]), "phase at #{t}"
      assert Tide.cycle(params, t) == v["cycle"], "cycle at #{t}"
      assert near(Tide.level(params, t), v["level"]), "level at #{t}"
      assert Tide.low_window?(params, t) == v["low"], "low at #{t}"
      assert Tide.low_window?(params, t, 30.0) == v["low_grace_30"], "low with grace at #{t}"
      assert near(Tide.seconds_until_low(params, t), v["until_low"], 1.0e-6), "until low at #{t}"
    end
  end

  test "high water at phase 0, lowest at 0.5" do
    p = @vectors["params"]
    assert near(Tide.level(p, 0), 0.78)
    assert near(Tide.level(p, 180_000), 0.30)
  end

  test "the cycle steps up at high water and counts back before the epoch" do
    p = @vectors["params"]
    assert Tide.cycle(p, 359_999) == 0
    assert Tide.cycle(p, 360_000) == 1
    assert Tide.cycle(p, -1) == -1
  end

  test "a yield level under the lowest water gives no window; one over the highest gives always" do
    p = @vectors["params"]
    refute Tide.low_window?(Map.put(p, "yield_level", 0.2), 180_000 + 1_000)
    assert Tide.low_window?(Map.put(p, "yield_level", 0.9), 0)
  end

  test "no clock, no window" do
    refute Tide.low_window?(@vectors["params"], nil)
  end
end
