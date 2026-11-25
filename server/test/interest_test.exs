defmodule Server.InterestTest do
  @moduledoc "SC-4's interest-cell maths (pure)."
  use ExUnit.Case, async: true
  alias Server.Interest

  describe "config" do
    test "reads core.crowd.cell; anything else means no interest cells" do
      assert Interest.config(%{"crowd" => %{"cell" => 480, "full" => 40, "lite" => 80}}) == %{cell: 480}
      assert Interest.config(%{"crowd" => %{"cell" => 480.0}}) == %{cell: 480}
      assert Interest.config(%{"crowd" => %{}}) == nil
      assert Interest.config(%{"crowd" => %{"cell" => 0}}) == nil
      assert Interest.config(%{"crowd" => %{"cell" => 8}}) == nil
      assert Interest.config(%{"crowd" => %{"cell" => "480"}}) == nil
      assert Interest.config(%{}) == nil
      assert Interest.config(nil) == nil
    end
  end

  describe "cells" do
    test "floor division, negative coordinates included" do
      assert Interest.cell_of([0, 0], 480) == {0, 0}
      assert Interest.cell_of([479, 479], 480) == {0, 0}
      assert Interest.cell_of([480, -1], 480) == {1, -1}
      assert Interest.cell_of({-480, -481}, 480) == {-1, -2}
    end

    test "positions round to whole pixels first, the way the world stores them" do
      assert Interest.cell_of([479.4, 0], 480) == {0, 0}
      assert Interest.cell_of([479.6, 0], 480) == {1, 0}
      assert Interest.cell_of([-0.4, 0], 480) == {0, 0}
      assert Interest.cell_of([-0.6, 0], 480) == {-1, 0}
    end

    test "cell_for reads the player position of a raw packet, or nil" do
      assert Interest.cell_for(%{"p" => [500, 10], "c" => [0, 0]}, 480) == {1, 0}
      assert Interest.cell_for(%{"c" => [500, 10]}, 480) == nil
      assert Interest.cell_for(%{"p" => ["a", 1]}, 480) == nil
      assert Interest.cell_for(%{"p" => [1.0e9, 1]}, 480) == nil
      assert Interest.cell_for(%{"p" => nil}, 480) == nil
      assert Interest.cell_for("junk", 480) == nil
    end
  end

  describe "neighbourhoods" do
    test "the 3 x 3 block around a cell" do
      n = Interest.neighbourhood({2, -1})
      assert length(n) == 9
      assert {1, -2} in n and {3, 0} in n and {2, -1} in n
      refute {4, -1} in n
    end

    test "near? is Chebyshev distance at most 1" do
      assert Interest.near?({0, 0}, {1, 1})
      assert Interest.near?({0, 0}, {0, 0})
      refute Interest.near?({0, 0}, {2, 0})
      refute Interest.near?({0, 0}, {1, -2})
    end

    test "newly visible cells on a move" do
      assert Enum.sort(Interest.newly_visible(nil, {0, 0})) == Enum.sort(Interest.neighbourhood({0, 0}))
      assert Interest.newly_visible({0, 0}, {0, 0}) == []
      # one step east: the column at x = 2 comes into view
      assert Enum.sort(Interest.newly_visible({0, 0}, {1, 0})) == [{2, -1}, {2, 0}, {2, 1}]
      # one step diagonally: an L of five
      assert length(Interest.newly_visible({0, 0}, {1, 1})) == 5
      # a jump (a portal, a resume): the whole new neighbourhood
      assert length(Interest.newly_visible({0, 0}, {5, 5})) == 9
    end
  end

  describe "group" do
    test "an entry goes to each occupied cell in its neighbourhood, once" do
      occupied = %{{0, 0} => :x, {1, 0} => :x, {5, 5} => :x}
      grouped = Interest.group([{:a, [{0, 0}]}], occupied)
      assert grouped == %{{0, 0} => [:a], {1, 0} => [:a]}
    end

    test "a mover that changed cell reaches its old neighbourhood and its new one" do
      occupied = %{{-1, 0} => :x, {3, 0} => :x, {9, 9} => :x}
      # moved from {0, 0} to {2, 0}: {-1, 0} is near the old cell only, {3, 0} near the new one only
      grouped = Interest.group([{:a, [{2, 0}, {0, 0}]}], occupied)
      assert grouped == %{{-1, 0} => [:a], {3, 0} => [:a]}
    end

    test "entries with no cell go nowhere, and cells with nothing are left out" do
      assert Interest.group([{:a, []}], %{{0, 0} => :x}) == %{}
      grouped = Interest.group([{:a, [{0, 0}]}, {:b, [{0, 1}]}, {:c, [{7, 7}]}], %{{0, 0} => :x, {7, 8} => :x})
      assert Enum.sort(grouped[{0, 0}]) == [:a, :b]
      assert grouped[{7, 8}] == [:c]
      assert map_size(grouped) == 2
    end
  end

  test "topic names the world and the cell" do
    assert Interest.topic("w1", {-2, 3}) == "world:w1:cell:-2,3"
  end
end
