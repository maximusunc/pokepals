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
    # Every entry carries its current form (formless pals report an empty species).
    assert Enum.all?(list, fn p -> Map.has_key?(p, :s) and Map.has_key?(p, :v) end)
  end

  test "a seeded species is reported, and a formless pal stays formless forever" do
    extra = %{
      "ambient_pals" => [
        %{"id" => "cat", "home" => [0, 0], "roam_radius" => 20, "species" => "cat", "variant" => 2},
        %{"id" => "none", "home" => [0, 0], "roam_radius" => 20}
      ]
    }

    state = AmbientPals.new(core(extra))
    seeded = AmbientPals.to_list(state)
    assert Enum.find(seeded, &(&1.id == "cat")) |> Map.take([:s, :v]) == %{s: "cat", v: 2}
    assert Enum.find(seeded, &(&1.id == "none")).s == ""

    # Over a long run the formless pal never sprouts a species (the client can't swap puppet kinds).
    {_final, frames} = run(state, 3000)

    assert Enum.all?(frames, fn frame ->
             Enum.find(frame, &(&1.id == "none")).s == ""
           end)
  end

  test "a species pal eventually shifts into a DIFFERENT known animal" do
    known = ~w(cat fox rabbit bird wolf)

    extra = %{
      "ambient_pals" => [
        %{"id" => "a", "home" => [0, 0], "roam_radius" => 20, "species" => "fox", "variant" => 0}
      ]
    }

    state = AmbientPals.new(core(extra))

    # Run well past the max morph window (120s = 1200 ticks) so at least one shift is guaranteed.
    {_final, frames} = run(state, 2000)
    forms = frames |> Enum.map(fn f -> hd(f) |> Map.take([:s, :v]) end)

    species_seen = forms |> Enum.map(& &1.s) |> Enum.uniq()
    assert length(species_seen) >= 2, "the pal never shifted species"
    assert Enum.all?(species_seen, &(&1 in known)), "shifted to an unknown species: #{inspect(species_seen)}"
    # A coat is always in the shifted species' real range (cat/rabbit/bird/wolf: 0..3, fox: 0..2).
    assert Enum.all?(forms, fn %{s: s, v: v} -> v >= 0 and v < Map.fetch!(%{"cat" => 4, "fox" => 3, "rabbit" => 4, "bird" => 4, "wolf" => 4}, s) end)
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

  test "pals avoid the server-baked border treeline (border_trees)" do
    # A lone border tree parked in pal 'a's roam disk — the sim must never sit inside it.
    extra = %{
      "collision" => %{"body_radius" => 6, "margin" => 2, "tree_radius" => 7},
      "ambient_pals" => [%{"id" => "a", "home" => [100, 100], "roam_radius" => 50, "look" => %{}}],
      "border_trees" => [[130, 100]]
    }

    state = AmbientPals.new(core(extra))
    {_final, frames} = run(state, 800)

    for frame <- frames, %{id: "a", p: [px, py]} <- frame do
      dist = :math.sqrt(:math.pow(px - 130, 2) + :math.pow(py - 100, 2))
      assert dist >= 7 + 8 - 0.5, "entered a border tree (#{dist})"
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
