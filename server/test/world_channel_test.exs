defmodule Server.WorldChannelTest do
  @moduledoc """
  The per-world channel (`"world:" <> world_id`): spec delivery on join (version-aware), welcome +
  load, save persistence, and — the multi-world point — that Presence and the state relay are scoped
  per world. async: false + shared sandbox so channel processes can hit Postgres. Each test seeds its
  own world(s) with unique ids, so the on-demand `Server.World` processes are fresh.
  """
  use Server.ChannelCase, async: false
  alias Server.{Saves, UserSocket, Worlds}

  defp seed_world(version \\ 1) do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "w-#{System.unique_integer([:positive])}",
        name: "W",
        display_types: ["2d"],
        version: version,
        spec: %{"core" => %{"hello" => true}, "profiles" => %{"2d" => %{}}}
      })

    world_id
  end

  defp join_world(token, world_id, params \\ %{}) do
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    {:ok, _reply, socket} = subscribe_and_join(socket, "world:" <> world_id, params)
    socket
  end

  describe "join" do
    test "joining an unknown world is rejected" do
      {:ok, socket} = connect(UserSocket, %{"token" => "u-unknown"})
      assert {:error, %{reason: "unknown_world"}} =
               subscribe_and_join(socket, "world:" <> Ecto.UUID.generate(), %{})
    end

    test "joining a known world delivers the spec, welcome (id == user_id), and load" do
      w = seed_world(3)
      socket = join_world("u-join", w)

      assert_push "world_spec", %{world_id: ^w, version: 3, spec: spec}
      assert spec == %{"core" => %{"hello" => true}, "profiles" => %{"2d" => %{}}}
      assert_push "welcome", %{id: id}
      assert id == socket.assigns.user_id
      assert_push "load", %{companion: nil, appearance: nil}
    end

    test "a matching known_version skips the spec body" do
      w = seed_world(3)
      _socket = join_world("u-cached", w, %{"known_version" => 3})

      assert_push "world_spec_unchanged", %{world_id: ^w, version: 3}
      refute_push "world_spec", %{}
    end

    test "a returning player's load carries their stored save (per-user, any world)" do
      w = seed_world()
      {:ok, socket} = connect(UserSocket, %{"token" => "u-returning"})
      uid = socket.assigns.user_id
      {:ok, _} = Saves.store(uid, %{"bond" => 0.7}, %{"hat" => "straw"})

      {:ok, _reply, _socket} = subscribe_and_join(socket, "world:" <> w, %{})
      assert_push "load", %{companion: %{"bond" => 0.7}, appearance: %{"hat" => "straw"}}
    end
  end

  describe "save" do
    test "a save frame persists under our user_id" do
      w = seed_world()
      {:ok, socket} = connect(UserSocket, %{"token" => "u-saver"})
      uid = socket.assigns.user_id
      {:ok, _reply, socket} = subscribe_and_join(socket, "world:" <> w, %{})
      assert_push "load", %{}

      push(socket, "save", %{"companion" => %{"bond" => 0.3}, "appearance" => %{}})
      _ = :sys.get_state(socket.channel_pid)

      assert Saves.load(uid) == %{companion: %{"bond" => 0.3}, appearance: %{}}
    end

    test "a second save within the interval is rate-limited (first one stands)" do
      w = seed_world()
      {:ok, socket} = connect(UserSocket, %{"token" => "u-spammer"})
      uid = socket.assigns.user_id
      {:ok, _reply, socket} = subscribe_and_join(socket, "world:" <> w, %{})
      assert_push "load", %{}

      push(socket, "save", %{"companion" => %{"bond" => 0.1}, "appearance" => %{}})
      ref = push(socket, "save", %{"companion" => %{"bond" => 0.9}, "appearance" => %{}})
      assert_reply ref, :error, %{reason: "rate_limited"}

      # The rejected save did not overwrite the accepted one.
      assert Saves.load(uid) == %{companion: %{"bond" => 0.1}, appearance: %{}}
    end

    test "an over-sized save is rejected and not persisted" do
      w = seed_world()
      {:ok, socket} = connect(UserSocket, %{"token" => "u-bloat"})
      uid = socket.assigns.user_id
      {:ok, _reply, socket} = subscribe_and_join(socket, "world:" <> w, %{})
      assert_push "load", %{}

      huge = String.duplicate("x", 70 * 1024)
      ref = push(socket, "save", %{"companion" => %{"blob" => huge}, "appearance" => %{}})
      assert_reply ref, :error, %{reason: "too_large"}

      assert Saves.load(uid) == %{companion: nil, appearance: nil}
    end
  end

  describe "presence is per world" do
    test "two players in the SAME world see each other join" do
      w = seed_world()
      _s1 = join_world("same-1", w)
      assert_push "welcome", %{id: _}
      assert_push "load", %{}

      _s2 = join_world("same-2", w)
      assert_push "welcome", %{id: id2}
      assert_push "load", %{}

      assert_push "join", %{id: ^id2}
    end

    test "two players in DIFFERENT worlds never see each other" do
      w1 = seed_world()
      w2 = seed_world()

      _s1 = join_world("diff-1", w1)
      assert_push "welcome", %{id: _}
      _s2 = join_world("diff-2", w2)
      assert_push "welcome", %{id: _}

      # No cross-world join frame is ever delivered.
      refute_push "join", %{}
    end
  end

  describe "state relay is per world" do
    test "a state frame reaches a peer in the same world, id-stamped" do
      w = seed_world()
      s1 = join_world("st-1", w)
      assert_push "welcome", %{id: id1}
      _s2 = join_world("st-2", w)
      assert_push "welcome", %{id: _}
      assert_push "join", %{id: _}

      push(s1, "state", %{"p" => [1, 2]})
      assert_push "state", %{"p" => [1, 2], "id" => ^id1}
    end

    test "a state frame does not cross into another world" do
      w1 = seed_world()
      w2 = seed_world()
      s1 = join_world("stx-1", w1)
      assert_push "welcome", %{id: _}
      _s2 = join_world("stx-2", w2)
      assert_push "welcome", %{id: _}

      push(s1, "state", %{"p" => [9, 9]})
      refute_push "state", %{}
    end
  end
end
