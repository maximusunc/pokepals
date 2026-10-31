defmodule Server.HomeWorldTest do
  use ExUnit.Case, async: true
  alias Server.HomeWorld

  @template %{
    "base" => %{
      "bounds" => %{"min" => [-400, -330], "max" => [400, 330]},
      "border" => %{"ring" => true, "spacing" => 120, "inset" => 18, "jitter" => 30, "rows" => 1, "row_gap" => 58},
      "props" => [%{"id" => "home_sign"}],
      "trees" => [[0, 0]]
    },
    "discoveries" => %{
      "hedge_seed" => %{
        "area" => %{"min" => [400, -330], "max" => [900, 330]},
        "props" => [%{"id" => "home_hedge_sprout"}],
        "hedges" => [%{"from" => [440, -170], "to" => [780, -170], "thickness" => 22.0}]
      }
    }
  }

  test "an empty home is just the base glade, with its border baked" do
    core = HomeWorld.build_core(@template, [])
    assert core["bounds"] == %{"min" => [-400, -330], "max" => [400, 330]}
    assert Enum.map(core["props"], & &1["id"]) == ["home_sign"]
    refute Map.has_key?(core, "hedges")
    assert core["discoveries"] == []
    assert core["border_trees"] != []
  end

  test "a discovery widens the glade to its area and adds its things" do
    core = HomeWorld.build_core(@template, ["hedge_seed"])
    assert core["bounds"] == %{"min" => [-400, -330], "max" => [900, 330]}
    assert Enum.map(core["props"], & &1["id"]) == ["home_sign", "home_hedge_sprout"]
    assert length(core["hedges"]) == 1
    assert core["discoveries"] == ["hedge_seed"]
  end

  test "the border moves out with the bounds" do
    empty = HomeWorld.build_core(@template, [])
    grown = HomeWorld.build_core(@template, ["hedge_seed"])
    max_x = fn core -> core["border_trees"] |> Enum.map(&hd/1) |> Enum.max() end
    assert max_x.(grown) > max_x.(empty)
  end

  test "unknown or repeated ids are ignored" do
    core = HomeWorld.build_core(@template, ["hedge_seed", "nope", "hedge_seed"])
    assert core["discoveries"] == ["hedge_seed"]
    assert length(core["hedges"]) == 1
  end

  test "the shipped template parses and its empty glade has a way out" do
    core = HomeWorld.build_core(HomeWorld.template(), [])
    assert [%{"target_world" => "11111111-1111-1111-1111-111111111111"} | _] = core["portals"]
  end
end
