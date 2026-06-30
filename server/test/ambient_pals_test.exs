defmodule Server.AmbientPalsTest do
  @moduledoc """
  The pure ambient-pal wander sim: it seeds one pal per spec entry, ambles each within its home disk,
  and exports the client wire shape. No process, no DB — just `new/tick/to_list`.
  """
  use ExUnit.Case, async: true
  alias Server.AmbientPals

  defp defs do
    [
      %{"id" => "a", "home" => [100, 100], "roam_radius" => 50, "look" => %{}},
      %{"id" => "b", "home" => [-40, 20], "roam_radius" => 30, "look" => %{}}
    ]
  end

  test "new/1 seeds one pal per def and to_list reports them in order" do
    list = AmbientPals.new(defs()) |> AmbientPals.to_list()
    assert length(list) == 2
    assert Enum.map(list, & &1.id) == ["a", "b"]
    # Each carries a position and a facing unit vector as [x, y] pairs.
    assert Enum.all?(list, fn p -> match?([_, _], p.p) and match?([_, _], p.l) end)
  end

  test "pals start at home" do
    list = AmbientPals.new(defs()) |> AmbientPals.to_list()
    assert Enum.find(list, &(&1.id == "a")).p == [100, 100]
    assert Enum.find(list, &(&1.id == "b")).p == [-40, 20]
  end

  test "pals wander but stay within roam_radius of home" do
    state = AmbientPals.new(defs())
    start = AmbientPals.to_list(state)

    # Advance ~60 s at 10 Hz — plenty of pause/roam cycles.
    final =
      Enum.reduce(1..600, state, fn _, s -> AmbientPals.tick(s, 0.1) end)
      |> AmbientPals.to_list()

    for d <- defs() do
      [hx, hy] = d["home"]
      pal = Enum.find(final, &(&1.id == d["id"]))
      [px, py] = pal.p
      dist = :math.sqrt(:math.pow(px - hx, 2) + :math.pow(py - hy, 2))
      assert dist <= d["roam_radius"] + 1.0, "#{d["id"]} strayed #{dist} > #{d["roam_radius"]}"
    end

    # And it actually moved — it's not frozen at home.
    assert start != final
  end

  test "new/1 tolerates an empty or non-list spec, and any?/1 reflects it" do
    assert AmbientPals.new([]) |> AmbientPals.to_list() == []
    assert AmbientPals.new(nil) |> AmbientPals.to_list() == []
    refute AmbientPals.new([]) |> AmbientPals.any?()
    assert AmbientPals.new(defs()) |> AmbientPals.any?()
  end

  test "ticking an empty sim is a harmless no-op" do
    state = AmbientPals.new([])
    assert AmbientPals.tick(state, 0.1) |> AmbientPals.to_list() == []
  end
end
