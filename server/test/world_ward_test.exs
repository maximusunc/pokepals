defmodule Server.WorldWardTest do
  @moduledoc """
  The SHARED Ruin ward state held by the per-world process: a player's companion uncovers and weights a
  plate (abstract intents), the linked slab opens, the state is queryable for a late joiner's snapshot,
  changes broadcast on the world's topic, a leaver releases their own weight, and the puzzle resets when
  the room empties. No DB — ward defs are passed straight to `ensure_started/2`.
  """
  use ExUnit.Case, async: true
  alias Server.World

  defp wid, do: "ruin-test-#{System.unique_integer([:positive])}"
  defp defs, do: [%{"id" => "gate", "latch" => true}]

  test "uncover + occupy opens the ward, and it's queryable for the join snapshot" do
    w = wid()
    World.ensure_started(w, defs())
    World.update_transform(w, "u1", %{})
    World.apply_ward(w, "u1", %{"kind" => "uncover", "ward" => "gate"})
    World.apply_ward(w, "u1", %{"kind" => "occupy", "ward" => "gate", "on" => true})

    assert [%{id: "gate", found: true, open: true}] = World.wards(w)
  end

  test "a latched ward stays open after the companion steps off" do
    w = wid()
    World.ensure_started(w, defs())
    World.update_transform(w, "u1", %{})
    World.apply_ward(w, "u1", %{"kind" => "uncover", "ward" => "gate"})
    World.apply_ward(w, "u1", %{"kind" => "occupy", "ward" => "gate", "on" => true})
    World.apply_ward(w, "u1", %{"kind" => "occupy", "ward" => "gate", "on" => false})

    assert [%{id: "gate", open: true}] = World.wards(w)
  end

  test "two players can each weight the ward; one leaving doesn't close a latched gate" do
    w = wid()
    World.ensure_started(w, defs())
    World.update_transform(w, "u1", %{})
    World.update_transform(w, "u2", %{})
    World.apply_ward(w, "u1", %{"kind" => "uncover", "ward" => "gate"})
    World.apply_ward(w, "u1", %{"kind" => "occupy", "ward" => "gate", "on" => true})
    World.apply_ward(w, "u2", %{"kind" => "occupy", "ward" => "gate", "on" => true})
    World.forget(w, "u1")

    assert [%{open: true}] = World.wards(w)
  end

  test "the puzzle resets when the room empties" do
    w = wid()
    World.ensure_started(w, defs())
    World.update_transform(w, "u1", %{})
    World.apply_ward(w, "u1", %{"kind" => "uncover", "ward" => "gate"})
    World.apply_ward(w, "u1", %{"kind" => "occupy", "ward" => "gate", "on" => true})
    assert [%{open: true}] = World.wards(w)

    World.forget(w, "u1")

    assert [%{id: "gate", found: false, open: false}] = World.wards(w)
  end

  test "ward changes broadcast on the world's state topic" do
    w = wid()
    World.ensure_started(w, defs())
    Phoenix.PubSub.subscribe(Server.PubSub, World.state_topic(w))

    World.apply_ward(w, "u1", %{"kind" => "uncover", "ward" => "gate"})

    assert_receive {:world_wards, [%{id: "gate", found: true, open: false}]}
  end
end
