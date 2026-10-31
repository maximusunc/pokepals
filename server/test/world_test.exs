defmodule Server.WorldTest do
  @moduledoc """
  The per-world live process: it stores each player's latest transform, fans updates out on its OWN
  PubSub topic, and is isolated from other worlds. Each test uses a unique world_id (a fresh process
  under the app's registry/supervisor), so no DB is involved.
  """
  use ExUnit.Case, async: true
  alias Server.World

  defp wid, do: "world-test-#{System.unique_integer([:positive])}"

  test "ensure_started is idempotent" do
    w = wid()
    assert World.ensure_started(w) == w
    assert World.ensure_started(w) == w
  end

  test "stores the latest transform per player and snapshots them" do
    w = wid()
    World.ensure_started(w)
    World.update_transform(w, "u1", %{"p" => [1, 2]})
    World.update_transform(w, "u2", %{"p" => [3, 4]})
    World.update_transform(w, "u1", %{"p" => [5, 6]})

    assert World.snapshot(w) == %{"u1" => %{"p" => [5, 6]}, "u2" => %{"p" => [3, 4]}}
  end

  test "forget drops a player's transform" do
    w = wid()
    World.ensure_started(w)
    World.update_transform(w, "u1", %{"p" => [1, 2]})
    World.forget(w, "u1")

    assert World.snapshot(w) == %{}
  end

  test "worlds are isolated: one world's transforms never appear in another" do
    a = wid()
    b = wid()
    World.ensure_started(a)
    World.ensure_started(b)
    World.update_transform(a, "ua", %{"p" => [1, 1]})
    World.update_transform(b, "ub", %{"p" => [2, 2]})

    assert World.snapshot(a) == %{"ua" => %{"p" => [1, 1]}}
    assert World.snapshot(b) == %{"ub" => %{"p" => [2, 2]}}
  end

  test "updates go out as one bundle per tick on that world's channel topic (SC-3)" do
    w = wid()
    World.ensure_started(w)
    Server.Endpoint.subscribe(World.channel_topic(w))

    World.update_transform(w, "u9", %{"p" => [7, 8]})
    World.update_transform(w, "u8", %{"p" => [1.6, 2.4], "pf" => [0.123, -0.987]})

    assert_receive %Phoenix.Socket.Broadcast{event: "states", payload: %{s: entries}}, 500
    assert Enum.sort(entries) == [
             ["u8", 2, 2, 0.12, -0.99, nil, nil, nil, nil],
             ["u9", 7, 8, nil, nil, nil, nil, nil, nil]
           ]
  end

  test "a tick with nobody moving sends nothing" do
    w = wid()
    World.ensure_started(w)
    Server.Endpoint.subscribe(World.channel_topic(w))
    World.update_transform(w, "u1", %{"p" => [1, 1]})
    assert_receive %Phoenix.Socket.Broadcast{event: "states"}, 500
    refute_receive %Phoenix.Socket.Broadcast{event: "states"}, 200
  end

  test "junk fields aren't stored or relayed" do
    w = wid()
    World.ensure_started(w)
    World.update_transform(w, "u1", %{"p" => [1, 1], "evil" => String.duplicate("x", 1000), "c" => "nope"})
    assert World.snapshot(w) == %{"u1" => %{"p" => [1, 1]}}
  end
end
