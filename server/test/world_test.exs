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

  test "only changes are sent: a repeated transform is not relayed, but its sender stays present" do
    w = wid()
    World.ensure_started(w)
    Server.Endpoint.subscribe(World.channel_topic(w))
    World.update_transform(w, "u1", %{"p" => [1, 1], "t" => 100})
    assert_receive %Phoenix.Socket.Broadcast{event: "states", payload: %{s: [["u1", 1, 1 | _]]}}, 500

    # A keepalive: same pose (rounding to the same pixel counts as the same), a newer load-test stamp.
    World.update_transform(w, "u1", %{"p" => [1.2, 0.9], "t" => 200})
    refute_receive %Phoenix.Socket.Broadcast{event: "states"}, 200
    assert World.snapshot(w) == %{"u1" => %{"p" => [1, 1], "t" => 100}}

    # A real change goes out with its own, latest stamp.
    World.update_transform(w, "u1", %{"p" => [2, 1], "t" => 300})
    assert_receive %Phoenix.Socket.Broadcast{event: "states", payload: %{s: [["u1", 2, 1, nil, nil, nil, nil, nil, nil, 300]]}}, 500
  end

  test "a changed facing alone is a change" do
    w = wid()
    World.ensure_started(w)
    Server.Endpoint.subscribe(World.channel_topic(w))
    World.update_transform(w, "u1", %{"p" => [1, 1], "pf" => [1, 0]})
    assert_receive %Phoenix.Socket.Broadcast{event: "states"}, 500
    World.update_transform(w, "u1", %{"p" => [1, 1], "pf" => [0, 1]})
    assert_receive %Phoenix.Socket.Broadcast{event: "states", payload: %{s: [["u1", 1, 1, +0.0, 1.0 | _]]}}, 500
  end

  test "junk fields aren't stored or relayed" do
    w = wid()
    World.ensure_started(w)
    World.update_transform(w, "u1", %{"p" => [1, 1], "evil" => String.duplicate("x", 1000), "c" => "nope"})
    assert World.snapshot(w) == %{"u1" => %{"p" => [1, 1]}}
  end

  describe "interest cells (SC-4, a world with a crowd block)" do
    alias Server.Interest

    @crowd %{"crowd" => %{"cell" => 100}}

    defp crowd_world do
      w = wid()
      World.ensure_started(w, [], @crowd)
      w
    end

    defp watch(w, cell), do: Phoenix.PubSub.subscribe(Server.PubSub, Interest.topic(w, cell))

    # Wait for the cell bundle sent to `cell`'s topic (the Broadcast carries the CHANNEL topic, so
    # clients see an ordinary "states" frame); its entries' ids.
    defp ids_from(w) do
      topic = World.channel_topic(w)
      assert_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "states", payload: %{s: entries}}, 500
      entries |> Jason.encode!() |> Jason.decode!() |> Enum.map(&hd/1) |> Enum.sort()
    end

    test "nothing goes out on the world-wide topic" do
      w = crowd_world()
      Server.Endpoint.subscribe(World.channel_topic(w))
      World.update_transform(w, "u1", %{"p" => [10, 10]})
      refute_receive %Phoenix.Socket.Broadcast{event: "states"}, 200
    end

    test "a bundle goes to the occupied cells around a mover, not far ones" do
      w = crowd_world()
      # watchers standing in {1, 0} (near) and {5, 5} (far)
      World.update_transform(w, "near", %{"p" => [150, 50]})
      World.update_transform(w, "far", %{"p" => [550, 550]})
      Process.sleep(120)
      watch(w, {1, 0})
      watch(w, {5, 5})

      World.update_transform(w, "mover", %{"p" => [50, 50]})
      assert ids_from(w) == ["mover"]
      refute_receive %Phoenix.Socket.Broadcast{event: "states"}, 200
    end

    test "a mover crossing a cell border is sent to the old and the new neighbourhoods that tick, then only the new" do
      w = crowd_world()
      World.update_transform(w, "west", %{"p" => [-50, 50]})
      World.update_transform(w, "east", %{"p" => [350, 50]})
      World.update_transform(w, "mover", %{"p" => [50, 50]})
      Process.sleep(120)
      watch(w, {-1, 0})
      watch(w, {3, 0})

      # {0, 0} -> {2, 0}: {-1, 0} was near the old cell, {3, 0} is near the new one
      World.update_transform(w, "mover", %{"p" => [250, 50]})
      assert ids_from(w) == ["mover"]
      assert ids_from(w) == ["mover"]

      # one more step inside {2, 0}: only the new neighbourhood hears it
      World.update_transform(w, "mover", %{"p" => [260, 50]})
      assert ids_from(w) == ["mover"]
      refute_receive %Phoenix.Socket.Broadcast{event: "states"}, 200
    end

    test "a cell bundle's frame on the wire is the ordinary states format (entries pre-encoded once)" do
      w = crowd_world()
      World.update_transform(w, "watch", %{"p" => [10, 10]})
      Process.sleep(120)
      watch(w, {0, 0})
      World.update_transform(w, "m", %{"p" => [20.4, 10], "pf" => [0.5, -0.5], "t" => 7})
      assert_receive %Phoenix.Socket.Broadcast{event: "states"} = msg, 500
      {:socket_push, :text, frame} = Phoenix.Socket.V2.JSONSerializer.fastlane!(msg)
      topic = World.channel_topic(w)

      assert [nil, nil, ^topic, "states", %{"s" => [["m", 20, 10, 0.5, -0.5, nil, nil, nil, nil, 7]]}] =
               frame |> IO.iodata_to_binary() |> Jason.decode!()
    end

    test "snapshot_cells returns who stands in the given cells, and forget clears a player's cell" do
      w = crowd_world()
      World.update_transform(w, "a", %{"p" => [10, 10], "t" => 5})
      World.update_transform(w, "b", %{"p" => [210, 10]})
      Process.sleep(120)
      assert World.snapshot_cells(w, [{0, 0}]) == %{"a" => %{"p" => [10, 10], "t" => 5}}
      assert Map.keys(World.snapshot_cells(w, [{0, 0}, {2, 0}])) |> Enum.sort() == ["a", "b"]

      World.forget(w, "a")
      assert World.snapshot_cells(w, [{0, 0}]) == %{}
      # an emptied cell isn't occupied any more: a mover beside it sends it nothing
      watch(w, {0, 0})
      World.update_transform(w, "b", %{"p" => [150, 10]})
      refute_receive %Phoenix.Socket.Broadcast{event: "states"}, 200
    end

    test "a player with no position has no cell and is sent nowhere" do
      w = crowd_world()
      World.update_transform(w, "watcher", %{"p" => [10, 10]})
      Process.sleep(120)
      watch(w, {0, 0})
      World.update_transform(w, "nopos", %{"c" => [10, 10]})
      refute_receive %Phoenix.Socket.Broadcast{event: "states"}, 200
      assert Map.has_key?(World.snapshot(w), "nopos")
    end

    test "a world without a crowd block keeps the world-wide bundle" do
      w = wid()
      World.ensure_started(w, [], %{"crowd" => %{}})
      Server.Endpoint.subscribe(World.channel_topic(w))
      World.update_transform(w, "u1", %{"p" => [10, 10]})
      assert_receive %Phoenix.Socket.Broadcast{event: "states"}, 500
    end
  end
end
