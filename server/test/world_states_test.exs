defmodule Server.WorldStatesTest do
  use ExUnit.Case, async: true
  alias Server.WorldStates

  test "keeps the known fields, rounded: positions to whole pixels, directions to two decimals" do
    assert WorldStates.sanitize(%{"p" => [10.4, -3.6], "pf" => [0.70711, 0.70711], "c" => [1, 2], "cl" => [0, 1]}) ==
             %{"p" => [10, -4], "pf" => [0.71, 0.71], "c" => [1, 2], "cl" => [0.0, 1.0]}
  end

  test "drops anything else, and anything malformed or absurd" do
    assert WorldStates.sanitize(%{"p" => [1, 1], "name" => "x", "pf" => [1], "c" => [1.0e9, 0], "cl" => ["a", 1]}) ==
             %{"p" => [1, 1]}
    assert WorldStates.sanitize(%{"junk" => true}) == nil
    assert WorldStates.sanitize("nope") == nil
  end

  test "a load-test send stamp survives, if it's a plain non-negative integer" do
    assert WorldStates.sanitize(%{"p" => [0, 0], "t" => 123}) == %{"p" => [0, 0], "t" => 123}
    assert WorldStates.sanitize(%{"p" => [0, 0], "t" => "x"}) == %{"p" => [0, 0]}
  end

  test "an entry is a flat positional array, nil where a field wasn't sent" do
    assert WorldStates.entry("u", %{"p" => [1, 2], "cl" => [0.5, -0.5]}) == ["u", 1, 2, nil, nil, nil, nil, 0.5, -0.5]
    assert WorldStates.entry("u", %{"p" => [1, 2], "t" => 9}) == ["u", 1, 2, nil, nil, nil, nil, nil, nil, 9]
  end

  test "a bundle holds one entry per player" do
    %{s: s} = WorldStates.bundle(%{"a" => %{"p" => [1, 1]}, "b" => %{"p" => [2, 2]}})
    assert Enum.sort(s) == [["a", 1, 1, nil, nil, nil, nil, nil, nil], ["b", 2, 2, nil, nil, nil, nil, nil, nil]]
  end

  test "a pre-encoded bundle is byte for byte the plain bundle's JSON" do
    ts = [{"a", %{"p" => [1, 1], "pf" => [0.5, -1.0], "t" => 9}}, {"b", %{"c" => [3, 4]}}]
    plain = Jason.encode!(%{s: for({id, t} <- ts, do: WorldStates.entry(id, t))})
    encoded = WorldStates.encoded_bundle(for {id, t} <- ts, do: WorldStates.entry_json(id, t))
    assert Jason.encode!(encoded) == plain
    assert Jason.encode!(WorldStates.encoded_bundle([])) == ~s({"s":[]})
  end

  test "a snapshot bundle leaves out the load-test stamp" do
    assert WorldStates.snapshot_bundle(%{"a" => %{"p" => [1, 1], "t" => 5}}) == %{s: [["a", 1, 1, nil, nil, nil, nil, nil, nil]]}
  end
end
