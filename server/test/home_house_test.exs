defmodule Server.HomeHouseTest do
  @moduledoc """
  The house in a home's spec (Server.HomeWorld): none until the carpenter's paid; then the glade widens north
  and the house stands there, walled in; while it's being built your keepsakes stay out in the glade, and once
  it's built they move in (onto its display spots) with every other find on its curio shelves.
  """
  use ExUnit.Case, async: true
  alias Server.HomeWorld

  @card %{
    "qualities" => ["green"],
    "keepsake" => %{
      "type" => "potted_hedge",
      "label" => "a hedge",
      "line" => "Ours.",
      "color" => [0.4, 0.6, 0.3]
    }
  }
  @t0 1_000_000

  defp template, do: HomeWorld.template()

  defp core(house_state, opts \\ []) do
    now =
      case house_state do
        :building -> @t0 + 1_000
        :built -> @t0 + 10_000_000
        _ -> @t0
      end

    cards = Keyword.get(opts, :cards, [])

    HomeWorld.build_core(template(), %{
      spots: Keyword.get(opts, :spots, 3),
      keepsakes: Keyword.get(opts, :keepsakes, []),
      cards: cards,
      house: if(house_state == :none, do: nil, else: %{"started_at" => @t0}),
      now: now
    })
  end

  defp house(core), do: Enum.find(core["buildings"] || [], &(&1["view"] == "house"))

  test "the home is a place no axe works" do
    assert core(:none)["chopping"] == false
  end

  test "no house: the glade as it was" do
    c = core(:none)
    assert c["bounds"] == %{"min" => [-400, -330], "max" => [400, 330]}
    assert house(c) == nil
  end

  test "being built: the glade widens north and the house stands there, walled, with its floor down" do
    c = core(:building)
    t = template()["house"]
    assert c["bounds"] == %{"min" => [-400, -330 - t["extend_north"]], "max" => [400, 330]}
    assert Enum.all?(c["regions"], &(&1["min"] == [-400, -330 - t["extend_north"]]))
    h = house(c)
    [x, y, w, d] = h["rect"]
    assert w == 560 and d == 220 and x == -280.0
    assert y == -330 - t["extend_north"] + t["from_north"]
    # entirely north of the old glade, and inside the new bounds
    assert y + d < -330 and y > -330 - t["extend_north"]
    assert h["house"]["state"] == "building"
    assert h["house"]["started_at"] == @t0
    # walls only: the furniture comes in once it's built
    assert length(h["solid_rects"]) == length(t["walls"])
    assert length(c["plates"]) == length(t["floors"])
    # a path up to the door
    assert Enum.any?(c["paths"], fn p -> p["to"] == [0.0, y + d + 12] end)
  end

  test "being built: keepsakes stay in the glade, no curios" do
    c = core(:building, keepsakes: ["a"], cards: [{"a", @card}, {"b", @card}])
    [k] = Enum.filter(c["props"], &Map.has_key?(&1, "keepsake"))
    assert k["position"] == hd(template()["keepsake_spots"])
    refute Enum.any?(c["props"], &Map.has_key?(&1, "curio"))
  end

  test "built: furniture walls in, rugs and shelves go down, and every find moves inside" do
    cards = [{"a", @card}, {"b", @card}, {"c", @card}]
    c = core(:built, keepsakes: ["b"], cards: cards)
    t = template()["house"]
    h = house(c)
    [hx, hy, w, d] = h["rect"]
    assert h["house"]["state"] == "built"
    assert length(h["solid_rects"]) == length(t["walls"]) + length(t["furniture_solids"])
    assert length(c["plates"]) == length(t["floors"]) + length(t["built_plates"])

    inside = fn [px, py] -> px > hx and px < hx + w and py > hy and py < hy + d end
    [k] = Enum.filter(c["props"], &Map.has_key?(&1, "keepsake"))
    assert k["keepsake"] == "b"
    assert inside.(k["position"])
    assert k["position"] == hd(c["home"]["spot_positions"])
    curios = Enum.filter(c["props"], &Map.has_key?(&1, "curio"))
    # newest first (cards come oldest first)
    assert Enum.map(curios, & &1["curio"]) == ["c", "a"]
    assert Enum.all?(curios, &inside.(&1["position"]))
    assert Enum.all?(curios, &(&1["interactive"] and &1["lore"] == "Ours."))
  end

  test "built in a big glade: the house follows the north edge out" do
    c = core(:built, spots: 7)
    t = template()["house"]
    [_x, y, _w, _d] = house(c)["rect"]
    assert c["bounds"]["min"] == [-760, -610 - t["extend_north"]]
    assert y == -610 - t["extend_north"] + t["from_north"]
    assert Enum.all?(c["home"]["spot_positions"], fn [_px, py] -> py > y and py < y + 220 end)
  end

  test "with every world's secret found and 7 keepsakes: a showcase inside, each in its own place, none in the doorway" do
    cards =
      for f <- Path.wildcard("priv/world_seeds/*.json") |> Enum.sort(),
          sec = Jason.decode!(File.read!(f))["secret"],
          sec != nil,
          do: {sec["id"], %{"qualities" => sec["qualities"] || [], "keepsake" => sec["keepsake"]}}

    assert length(cards) >= 16
    keepsakes = cards |> Enum.take(7) |> Enum.map(&elem(&1, 0))
    c = core(:built, spots: 7, keepsakes: keepsakes, cards: cards)
    [hx, hy, w, d] = house(c)["rect"]
    t = template()["house"]
    [d0, d1] = t["door"]

    shown = Enum.filter(c["props"], &(Map.has_key?(&1, "keepsake") or Map.has_key?(&1, "curio")))
    # the 7 keepsakes, and the 8 newest of the rest on the shelves: never every find
    assert length(shown) == 7 + t["curio_shown"]
    newest = cards |> Enum.reverse() |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 in keepsakes)) |> Enum.take(t["curio_shown"])
    assert shown |> Enum.filter(&Map.has_key?(&1, "curio")) |> Enum.map(& &1["curio"]) == newest
    assert shown |> Enum.map(& &1["position"]) |> Enum.uniq() |> length() == length(shown)

    for p <- shown do
      [px, py] = p["position"]
      assert px > hx and px < hx + w and py > hy and py < hy + d, "#{p["id"]} isn't inside the house"
      # nothing stands in the way in: the doorway and two bodies' width either side, a few body-lengths deep
      in_door = px > hx + d0 - 30 and px < hx + d1 + 30 and py + 8 > hy + d - 50
      refute in_door, "#{p["id"]} stands in the doorway"
    end

    assert Enum.count(shown, &Map.has_key?(&1, "keepsake")) == 7
    # the cabinet, inside, for everything
    [cx, cy] = house(c)["house"]["cabinet"]
    assert cx > hx and cx < hx + w and cy > hy and cy < hy + d
  end
end
