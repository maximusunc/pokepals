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

  test "an update broadcasts on that world's own state topic" do
    w = wid()
    World.ensure_started(w)
    Phoenix.PubSub.subscribe(Server.PubSub, World.state_topic(w))

    World.update_transform(w, "u9", %{"p" => [7, 8]})

    assert_receive {:world_state, "u9", %{"p" => [7, 8]}}
  end
end
