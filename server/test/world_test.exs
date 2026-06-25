defmodule Server.WorldTest do
  @moduledoc """
  Unit tests for the world process: it stores each player's latest transform, fans updates out over
  PubSub, replays a snapshot, and forgets a player on leave. Each test starts its own isolated World
  instance (the app already runs the global `Server.World`, so we name ours uniquely) and asserts
  against the shared `world:state` topic.
  """
  use ExUnit.Case, async: false
  alias Server.World

  setup do
    name = :"world_test_#{System.unique_integer([:positive])}"
    world = start_supervised!({World, name: name})
    %{world: world}
  end

  test "update_transform stores the latest, snapshot returns it", %{world: world} do
    World.update_transform(world, "u1", %{"p" => [1, 2]})
    World.update_transform(world, "u2", %{"p" => [3, 4]})
    # Newest wins for a given player.
    World.update_transform(world, "u1", %{"p" => [5, 6]})

    assert World.snapshot(world) == %{"u1" => %{"p" => [5, 6]}, "u2" => %{"p" => [3, 4]}}
  end

  test "forget drops a player's transform", %{world: world} do
    World.update_transform(world, "u1", %{"p" => [1, 2]})
    World.forget(world, "u1")

    assert World.snapshot(world) == %{}
  end

  test "an update is broadcast on the state topic", %{world: world} do
    Phoenix.PubSub.subscribe(Server.PubSub, World.state_topic())

    World.update_transform(world, "u9", %{"p" => [7, 8]})

    assert_receive {:world_state, "u9", %{"p" => [7, 8]}}
  end
end
