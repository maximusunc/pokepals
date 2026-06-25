defmodule Server.WorldChannelTest do
  @moduledoc """
  End-to-end tests of the transport through Phoenix Channels: token auth at connect, the welcome +
  canonical-save load on join, the save round-trip, and presence (join / leave / identity) reaching
  the right peers. async: false + a shared DB sandbox so the channel processes can hit Postgres.
  """
  use Server.ChannelCase, async: false
  alias Server.{Saves, UserSocket}

  # Connect (resolving the token → user_id) and join the single "world" channel.
  defp join_world(token) do
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    {:ok, _reply, socket} = subscribe_and_join(socket, "world", %{})
    socket
  end

  describe "connect/3 (token auth)" do
    test "an unknown token mints an account and assigns its user_id" do
      assert {:ok, socket} = connect(UserSocket, %{"token" => "conn-tok"})
      assert is_binary(socket.assigns.user_id)
    end

    test "the same token resolves to the same user_id across connections" do
      {:ok, a} = connect(UserSocket, %{"token" => "conn-same"})
      {:ok, b} = connect(UserSocket, %{"token" => "conn-same"})
      assert a.assigns.user_id == b.assigns.user_id
    end

    test "a missing or blank token is rejected" do
      assert connect(UserSocket, %{}) == :error
      assert connect(UserSocket, %{"token" => ""}) == :error
    end
  end

  describe "join: welcome + load" do
    test "a brand-new player gets a welcome (id == our user_id) and a null load" do
      socket = join_world("join-new")

      assert_push "welcome", %{id: id, peers: peers}
      # The wire id IS the player's user_id (the Presence roster key).
      assert id == socket.assigns.user_id
      # `peers` is the roster snapshot (a list); we don't assert it's empty — Presence cleanup from
      # other tests is asynchronous, and our own id is never in it regardless.
      assert is_list(peers)
      refute Enum.any?(peers, &(&1.id == id))
      assert_push "load", %{companion: nil, appearance: nil}
    end

    test "a returning player's load carries their stored companion + appearance" do
      {:ok, socket} = connect(UserSocket, %{"token" => "join-returning"})
      uid = socket.assigns.user_id
      {:ok, _} = Saves.store(uid, %{"bond" => 0.7}, %{"colors" => %{"skin" => "warm"}})

      {:ok, _reply, _socket} = subscribe_and_join(socket, "world", %{})

      assert_push "welcome", %{}
      assert_push "load", %{companion: %{"bond" => 0.7}, appearance: %{"colors" => %{"skin" => "warm"}}}
    end
  end

  describe "save (canonical write)" do
    test "a save frame persists the companion + appearance under our user_id" do
      {:ok, socket} = connect(UserSocket, %{"token" => "saver"})
      uid = socket.assigns.user_id
      {:ok, _reply, socket} = subscribe_and_join(socket, "world", %{})
      assert_push "load", %{}

      push(socket, "save", %{"companion" => %{"bond" => 0.3}, "appearance" => %{"hat" => "straw"}})
      # Force the channel to drain the queued save before we read it back.
      _ = :sys.get_state(socket.channel_pid)

      assert Saves.load(uid) == %{companion: %{"bond" => 0.3}, appearance: %{"hat" => "straw"}}
    end
  end

  describe "presence" do
    test "an existing peer is told when another joins and leaves" do
      _s1 = join_world("pres-1")
      assert_push "welcome", %{id: _id1}
      assert_push "load", %{}

      s2 = join_world("pres-2")
      assert_push "welcome", %{id: id2}
      assert_push "load", %{}

      # s1 (this test process is its transport) is told about s2's arrival...
      assert_push "join", %{id: ^id2}

      # ...and its departure.
      leave(s2)
      assert_push "leave", %{id: ^id2}
    end

    test "an identity update reaches the other peer, id-stamped" do
      _s1 = join_world("ident-1")
      assert_push "welcome", %{}
      assert_push "load", %{}

      s2 = join_world("ident-2")
      assert_push "welcome", %{id: id2}
      assert_push "load", %{}
      assert_push "join", %{id: ^id2}

      push(s2, "identity", %{"name" => "Brindle", "appearance" => %{}, "companion_look" => %{}})

      assert_push "identity", %{"name" => "Brindle", id: ^id2}
    end

    test "a state frame is relayed to other peers (via the world process), id-stamped, not echoed" do
      s1 = join_world("state-1")
      assert_push "welcome", %{id: id1}
      assert_push "load", %{}

      _s2 = join_world("state-2")
      assert_push "welcome", %{id: _id2}
      assert_push "load", %{}
      assert_push "join", %{id: _}

      push(s1, "state", %{"p" => [12, -3]})

      # s2 (same test process transport) receives it with s1's id stamped on. The state payload is
      # the client's passthrough (string keys), so the stamped id is the string "id".
      assert_push "state", %{"p" => [12, -3], "id" => ^id1}
    end

    test "a joiner is replayed the world snapshot, so a peer already moving appears at once" do
      s1 = join_world("snap-1")
      assert_push "welcome", %{id: id1}
      assert_push "load", %{}

      push(s1, "state", %{"p" => [5, 6]})
      # Make the move land in the world before s2 joins: first drain s1's channel (so its handle_in
      # has issued the cast), then sync the world process (so the cast is applied).
      _ = :sys.get_state(s1.channel_pid)
      _ = Server.World.snapshot()

      _s2 = join_world("snap-2")
      assert_push "welcome", %{id: _id2}
      assert_push "load", %{}

      # The snapshot replay positions s1's puppet for the newcomer immediately.
      assert_push "state", %{"p" => [5, 6], "id" => ^id1}
    end
  end
end
