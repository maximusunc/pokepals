defmodule Server.AmbientPalsTest do
  @moduledoc """
  The pure ambient-pal wander sim: it seeds one pal per spec entry, ambles each within its home disk,
  steers clear of the world's solids, and exports the client wire shape. No process, no DB — just
  `new/tick/to_list` over a spec `core` map.
  """
  use ExUnit.Case, async: true
  alias Server.AmbientPals

  # A spec `core` with two pals and the default collision block, plus anything extra a test needs.
  defp core(extra \\ %{}) do
    Map.merge(
      %{
        "ambient_pals" => [
          %{"id" => "a", "home" => [100, 100], "roam_radius" => 50, "look" => %{}},
          %{"id" => "b", "home" => [-40, 20], "roam_radius" => 30, "look" => %{}}
        ],
        "collision" => %{"body_radius" => 6, "margin" => 2}
      },
      extra
    )
  end

  # Advance the sim `n` ticks at 10 Hz, collecting every pal's position at each step.
  defp run(state, n) do
    Enum.reduce(1..n, {state, []}, fn _, {s, acc} ->
      s = AmbientPals.tick(s, 0.1)
      {s, [AmbientPals.to_list(s) | acc]}
    end)
  end

  test "new/1 seeds one pal per def and to_list reports them in order" do
    list = AmbientPals.new(core()) |> AmbientPals.to_list()
    assert length(list) == 2
    assert Enum.map(list, & &1.id) == ["a", "b"]
    assert Enum.all?(list, fn p -> match?([_, _], p.p) and match?([_, _], p.l) end)
  end

  test "pals start at home when nothing blocks it" do
    list = AmbientPals.new(core()) |> AmbientPals.to_list()
    assert Enum.find(list, &(&1.id == "a")).p == [100.0, 100.0]
    assert Enum.find(list, &(&1.id == "b")).p == [-40.0, 20.0]
  end

  test "pals wander but stay within roam_radius of home" do
    state = AmbientPals.new(core())
    start = AmbientPals.to_list(state)

    final =
      Enum.reduce(1..600, state, fn _, s -> AmbientPals.tick(s, 0.1) end)
      |> AmbientPals.to_list()

    for %{"id" => id, "home" => [hx, hy], "roam_radius" => roam} <- core()["ambient_pals"] do
      %{p: [px, py]} = Enum.find(final, &(&1.id == id))
      dist = :math.sqrt(:math.pow(px - hx, 2) + :math.pow(py - hy, 2))
      assert dist <= roam + 1.0, "#{id} strayed #{dist} > #{roam}"
    end

    assert start != final
  end

  test "pals never enter a solid, and one placed on a solid starts clear of it" do
    # A tree out near the edge of pal 'a's roam disk, and 'a's home dropped right on a blocking prop. The
    # tree (excl. 15) and log (excl. 21) are 60 apart, so their exclusion zones don't overlap — a pal can
    # cleanly be outside both.
    extra = %{
      "collision" => %{"body_radius" => 6, "margin" => 2, "tree_radius" => 7},
      "ambient_pals" => [%{"id" => "a", "home" => [110, 100], "roam_radius" => 60, "look" => %{}}],
      "trees" => [[170, 100]],
      "props" => [%{"id" => "log", "type" => "log", "position" => [110, 100]}]
    }

    state = AmbientPals.new(core(extra))

    # Home was on the log (radius 13 + body 8 = 21): the pal is pushed clear at spawn.
    %{p: [sx, sy]} = AmbientPals.to_list(state) |> hd()
    assert :math.sqrt(:math.pow(sx - 110, 2) + :math.pow(sy - 100, 2)) >= 21 - 0.5

    # Over a long run it must never sit inside the tree (r 7) or the log (r 13), body radius 8.
    {_final, frames} = run(state, 800)

    for frame <- frames, %{id: "a", p: [px, py]} <- frame do
      tree = :math.sqrt(:math.pow(px - 170, 2) + :math.pow(py - 100, 2))
      log = :math.sqrt(:math.pow(px - 110, 2) + :math.pow(py - 100, 2))
      assert tree >= 7 + 8 - 0.5, "entered the tree (#{tree})"
      assert log >= 13 + 8 - 0.5, "entered the log (#{log})"
    end
  end

  test "pals are held inside the border treeline via a bounds inset" do
    extra = %{
      "bounds" => %{"min" => [0, 0], "max" => [1000, 1000]},
      "border" => %{"ring" => true, "inset" => 18, "jitter" => 34, "rows" => 2, "row_gap" => 62},
      "collision" => %{"body_radius" => 6, "margin" => 2, "tree_radius" => 7},
      "ambient_pals" => [%{"id" => "a", "home" => [500, 500], "roam_radius" => 3000, "look" => %{}}]
    }

    state = AmbientPals.new(core(extra))
    {_final, frames} = run(state, 500)

    # Border reaches inward 18 + (2-1)*62 + 34 + 7 = 121; plus the body radius 8 → the centre stays 129
    # in from every edge, so the pal stops just inside the treeline instead of among it.
    inset = 121 + 8

    for frame <- frames, %{id: "a", p: [px, py]} <- frame do
      assert px >= inset - 0.5 and px <= 1000 - inset + 0.5
      assert py >= inset - 0.5 and py <= 1000 - inset + 0.5
    end
  end

  test "pals stay inside the world bounds" do
    extra = %{
      "bounds" => %{"min" => [80, 80], "max" => [140, 140]},
      "ambient_pals" => [%{"id" => "a", "home" => [110, 110], "roam_radius" => 200, "look" => %{}}]
    }

    state = AmbientPals.new(core(extra))
    {_final, frames} = run(state, 400)
    # body radius 8 → centre stays a body-width inside each edge.
    for frame <- frames, %{id: "a", p: [px, py]} <- frame do
      assert px >= 80 + 8 - 0.5 and px <= 140 - 8 + 0.5
      assert py >= 80 + 8 - 0.5 and py <= 140 - 8 + 0.5
    end
  end

  test "new/1 tolerates an empty or non-map spec, and any?/1 reflects it" do
    assert AmbientPals.new(%{}) |> AmbientPals.to_list() == []
    assert AmbientPals.new(nil) |> AmbientPals.to_list() == []
    assert AmbientPals.new(%{"ambient_pals" => []}) |> AmbientPals.to_list() == []
    refute AmbientPals.new(%{}) |> AmbientPals.any?()
    assert AmbientPals.new(core()) |> AmbientPals.any?()
  end

  test "ticking an empty sim is a harmless no-op" do
    assert AmbientPals.new(%{}) |> AmbientPals.tick(0.1) |> AmbientPals.to_list() == []
  end
end
