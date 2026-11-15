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

  # Where the house's front door stands: `door_from_pond` north of the pond's top edge (the template's first pond).
  defp door_y do
    t = template()
    [_x, cy] = hd(t["base"]["ponds"])["center"]
    cy - hd(t["base"]["ponds"])["radius"] - t["house"]["door_from_pond"]
  end

  test "being built: the house stands by the pond, in line with the way in, walled, with its floor down" do
    c = core(:building)
    t = template()["house"]
    h = house(c)
    [x, y, w, d] = h["rect"]
    assert w == 560 and d == 220 and x == -280.0
    # its front door: door_from_pond north of the pond's top edge, centred on x = 0 like the portal home
    assert y + d == door_y()
    assert Enum.sum(t["door"]) / 2 + x == 0
    assert [px, _] = hd(c["portals"])["position"]
    assert px == 0
    # the glade reaches north just far enough for the house and its treeline
    assert c["bounds"] == %{"min" => [-400, y - t["from_north"]], "max" => [400, 330]}
    assert Enum.all?(c["regions"], &(&1["min"] == [-400, y - t["from_north"]]))
    assert h["house"]["state"] == "building"
    assert h["house"]["started_at"] == @t0
    # walls only: the furniture comes in once it's built
    assert length(h["solid_rects"]) == length(t["walls"])
    assert length(c["plates"]) == length(t["floors"])
    # a path up to the door
    assert Enum.any?(c["paths"], fn p -> p["to"] == [0.0, y + d + 12] end)
  end

  test "nothing in the glade stands where the house does, whatever the bond and finds" do
    cards = for q <- ~w(glowing watery green old warm wild quiet odd), i <- 1..3, do: {"#{q}#{i}", put_in(@card, ["qualities"], [q])}
    c = core(:building, spots: 7, keepsakes: Enum.map(Enum.take(cards, 7), &elem(&1, 0)), cards: cards)
    [x, y, w, d] = house(c)["rect"]
    inside = fn [px, py] -> px > x - 10 and px < x + w + 10 and py > y - 10 and py < y + d + 16 end
    things =
      Enum.map(c["props"], &{&1["id"], &1["position"]}) ++
        Enum.map(c["trees"] || [], &{"tree", &1}) ++
        Enum.map(c["landmarks"] || [], &{"landmark", &1["position"]}) ++
        Enum.map(c["ponds"] || [], &{"pond", &1["center"]})

    for {id, [px, py | _]} <- things, do: refute(inside.([px, py]), "#{id} stands where the house does")
  end

  test "being built: keepsakes stay in the glade, no curios, the tank by the journal" do
    c = core(:building, keepsakes: ["a"], cards: [{"a", @card}, {"b", @card}])
    tank = Enum.find(c["props"], &(&1["tank"] == true))
    assert tank["position"] == Enum.find(template()["base"]["props"], &(&1["tank"] == true))["position"]
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
    # the fish tank has moved in
    tank = Enum.find(c["props"], &(&1["tank"] == true))
    assert inside.(tank["position"])
    assert tank["position"] == house(c)["house"]["tank"]
    curios = Enum.filter(c["props"], &Map.has_key?(&1, "curio"))
    # newest first (cards come oldest first)
    assert Enum.map(curios, & &1["curio"]) == ["c", "a"]
    assert Enum.all?(curios, &inside.(&1["position"]))
    assert Enum.all?(curios, &(&1["interactive"] and &1["lore"] == "Ours."))
  end

  test "built in a big glade: the house stays by the pond, and the glade already holds it" do
    c = core(:built, spots: 7)
    [_x, y, _w, d] = house(c)["rect"]
    assert y + d == door_y()
    assert c["bounds"]["min"] == [-760, min(-610, y - template()["house"]["from_north"])]
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
