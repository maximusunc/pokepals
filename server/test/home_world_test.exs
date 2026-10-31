defmodule Server.HomeWorldTest do
  use ExUnit.Case, async: true
  alias Server.HomeWorld

  @seed_card %{
    "qualities" => ["green", "quiet"],
    "together" => true,
    "keepsake" => %{"type" => "potted_hedge", "label" => "a potted spiral hedge", "line" => "It guards this one.",
                    "color" => [0.4, 0.6, 0.3], "temperament" => %{"curiosity" => 0.7}}
  }

  defp template, do: HomeWorld.template()

  test "an empty home is the base glade with its journal and a way out" do
    core = HomeWorld.build_core(template(), %{spots: 3, keepsakes: [], cards: []})
    assert core["bounds"] == %{"min" => [-400, -330], "max" => [400, 330]}
    assert Enum.any?(core["props"], &(&1["journal"] == true))
    assert [%{"target_world" => "11111111-1111-1111-1111-111111111111"}] = core["portals"]
    assert core["home"]["finds"] == []
    refute Map.has_key?(core, "art")
    assert core["border_trees"] != []
  end

  test "the glade widens with each keepsake spot past three, and the border moves out" do
    small = HomeWorld.build_core(template(), %{spots: 3, keepsakes: [], cards: []})
    big = HomeWorld.build_core(template(), %{spots: 7, keepsakes: [], cards: []})
    assert big["bounds"] == %{"min" => [-760, -610], "max" => [760, 610]}
    max_x = fn c -> c["border_trees"] |> Enum.map(&hd/1) |> Enum.max() end
    assert max_x.(big) > max_x.(small)
  end

  test "chosen keepsakes stand at the spots, favourite first, as examinable props" do
    core = HomeWorld.build_core(template(), %{spots: 3, keepsakes: ["hedge_seed"], cards: [{"hedge_seed", @seed_card}]})
    [k] = Enum.filter(core["props"], &(&1["tags"] == ["keepsake"]))
    assert k["type"] == "potted_hedge" and k["favourite"] and k["interactive"]
    assert k["lore"] == "It guards this one."
    assert k["position"] == hd(template()["keepsake_spots"])
    assert core["home"]["keepsakes"] == ["hedge_seed"]
    assert [%{"id" => "hedge_seed", "together" => true}] = core["home"]["finds"]
  end

  test "keepsakes beyond the open spots, or with no find behind them, don't show" do
    cards = for i <- 1..5, do: {"f#{i}", @seed_card}
    core = HomeWorld.build_core(template(), %{spots: 3, keepsakes: ["f1", "f2", "f3", "f4", "ghost"], cards: cards})
    assert core["props"] |> Enum.count(&(&1["tags"] == ["keepsake"])) == 3
  end

  test "qualities show gently: a little life and a tint for one find, features only once clear" do
    one = HomeWorld.build_core(template(), %{spots: 3, keepsakes: [], cards: [{"a", @seed_card}]})
    ids = Enum.map(one["props"], & &1["id"])
    assert "q_quiet_1" in ids
    refute "q_quiet_f1" in ids
    assert one["atmosphere"]["day_tint"] != template()["base"]["atmosphere"]["day_tint"]
    assert get_in(one, ["art", "entities", "ambient_life", "butterflies", "count"]) > 6

    many = HomeWorld.build_core(template(), %{spots: 3, keepsakes: [], cards: for(i <- 1..3, do: {"g#{i}", @seed_card})})
    assert Enum.any?(many["props"], &(&1["id"] == "q_quiet_f1"))
    assert Enum.any?(many["landmarks"] || [], &(&1["type"] == "great_tree"))
  end

  test "however lopsided the mix, the tint stays within its cap" do
    glow = %{"qualities" => ["glowing"], "keepsake" => %{}}
    core = HomeWorld.build_core(template(), %{spots: 3, keepsakes: [], cards: for(i <- 1..20, do: {"x#{i}", glow})})
    [r0, g0, b0] = template()["base"]["atmosphere"]["day_tint"]
    [r, g, b] = core["atmosphere"]["day_tint"]
    assert Enum.all?([r - r0, g - g0, b - b0], &(abs(&1) <= 0.0801))
    assert get_in(core, ["art", "entities", "ambient_life", "fireflies", "always"]) == true
  end

  test "a visitor's view carries the resident; strengths ignore unknown qualities" do
    core = HomeWorld.build_core(template(), %{spots: 3, keepsakes: [], cards: [], resident: %{"companion_form" => %{"species" => "fox"}}})
    assert core["home"]["resident"]["companion_form"]["species"] == "fox"
    counts = HomeWorld.qualities_of([{"a", %{"qualities" => ["glowing", "glowing", "made-up"]}}])
    assert counts == %{"glowing" => 1, "made-up" => 1}
  end
end
