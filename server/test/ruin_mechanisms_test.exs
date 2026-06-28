defmodule Server.RuinMechanismsTest do
  @moduledoc """
  The pure, server-side Ruin ward rules (the authority for shared worlds): a hidden plate the search
  uncovers, weight on an uncovered plate raising the slab, the latch holding a Threshold slab open, and
  uncover/settle order never mattering. Mirrors the client's old reference suite.
  """
  use ExUnit.Case, async: true
  alias Server.RuinMechanisms, as: R

  defp gate(latch \\ true), do: R.new([%{"id" => "gate", "latch" => latch}])

  test "a fresh ward starts hidden and shut" do
    s = gate()
    refute R.found?(s, "gate")
    refute R.open?(s, "gate")
  end

  test "uncover sets found" do
    s = gate() |> R.uncover("gate")
    assert R.found?(s, "gate")
  end

  test "weight on a still-buried plate opens nothing" do
    s = gate() |> R.set_occupied("gate", true)
    refute R.open?(s, "gate")
  end

  test "an uncovered, weighted plate opens the slab" do
    s = gate() |> R.uncover("gate") |> R.set_occupied("gate", true)
    assert R.open?(s, "gate")
  end

  test "a latched Threshold slab stays open after the plate clears" do
    s =
      gate(true)
      |> R.uncover("gate")
      |> R.set_occupied("gate", true)
      |> R.set_occupied("gate", false)

    assert R.open?(s, "gate")
  end

  test "a non-latching slab is open only while weighted" do
    s = gate(false) |> R.uncover("gate") |> R.set_occupied("gate", true)
    assert R.open?(s, "gate")
    refute s |> R.set_occupied("gate", false) |> R.open?("gate")
  end

  test "settle-then-uncover opens too — order never matters" do
    s = gate() |> R.set_occupied("gate", true) |> R.uncover("gate")
    assert R.open?(s, "gate")
  end

  test "operating on an undeclared ward is a harmless no-op" do
    s = R.new([]) |> R.uncover("ghost") |> R.set_occupied("ghost", true)
    refute R.open?(s, "ghost")
    assert R.to_list(s) == []
  end

  test "to_list reflects ids and flags" do
    assert [%{id: "gate", found: true, open: false}] = gate() |> R.uncover("gate") |> R.to_list()
  end
end
