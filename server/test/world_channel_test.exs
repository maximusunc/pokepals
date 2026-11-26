defmodule Server.WorldChannelTest do
  @moduledoc """
  The per-world channel (`"world:" <> world_id`): spec delivery on join (version-aware), welcome +
  load, save persistence, and — the multi-world point — that Presence and the state relay are scoped
  per world. async: false + shared sandbox so channel processes can hit Postgres. Each test seeds its
  own world(s) with unique ids, so the on-demand `Server.World` processes are fresh.
  """
  use Server.ChannelCase, async: false
  alias Server.{ItemDefinition, Repo, Saves, UserSocket, Worlds}

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

  # A world whose spec carries the salamander hunt, so reward claims in it are honoured.
  defp seed_hunt_world do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "hunt-#{System.unique_integer([:positive])}",
        name: "Riverbank",
        display_types: ["2d"],
        version: 1,
        spec: %{
          "core" => %{"goal" => %{"type" => "find_salamanders", "count" => 10}},
          "profiles" => %{"2d" => %{}}
        }
      })

    world_id
  end

  defp join_world(token, world_id, params \\ %{}) do
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    {:ok, _reply, socket} = subscribe_and_join(socket, "world:" <> world_id, params)
    socket
  end

  describe "list_worlds" do
    test "returns the directory with live player counts, excluding the world we ask from" do
      t = "dir#{System.unique_integer([:positive])}"
      here = seed_world()
      busy = Ecto.UUID.generate()

      {:ok, _} =
        Worlds.upsert(%{
          world_id: busy,
          name: "Busy #{t}",
          blurb: "lively",
          tags: [t],
          display_types: ["2d"],
          version: 1,
          spec: %{"core" => %{}, "profiles" => %{"2d" => %{}}}
        })

      # Someone is already in the busy world, so it reports one player.
      _friend = join_world("u-dir-friend", busy)
      socket = join_world("u-dir", here)

      push(socket, "list_worlds", %{"q" => t, "req" => 7})
      assert_push "world_list", %{req: 7, offset: 0, more: false, worlds: [card]}
      assert card.world_id == busy
      assert card.name == "Busy #{t}"
      assert card.players == 1
      refute Map.has_key?(card, :spec)

      # The world we're standing in never lists itself.
      push(socket, "list_worlds", %{"q" => "", "req" => 8, "limit" => 100})
      assert_push "world_list", %{req: 8, worlds: worlds}
      refute Enum.any?(worlds, &(&1.world_id == here))
    end
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

    test "a matching known etag skips the spec body" do
      w = seed_world(3)
      etag = Worlds.etag(Worlds.get(w))
      _socket = join_world("u-cached", w, %{"known_etag" => etag})

      assert_push "world_spec_unchanged", %{world_id: ^w, version: 3, etag: ^etag}
      refute_push "world_spec", %{}
    end

    test "a stale known etag re-ships the full spec" do
      w = seed_world(3)
      _socket = join_world("u-stale", w, %{"known_etag" => "deadbeef"})

      assert_push "world_spec", %{world_id: ^w, version: 3, etag: etag}
      assert etag == Worlds.etag(Worlds.get(w))
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

  defp insert_color(id, name, ramp, price) do
    %ItemDefinition{}
    |> ItemDefinition.changeset(%{
      item_def_id: id,
      name: name,
      category: "color",
      base_attributes: %{"ramp" => ramp, "price" => price, "currency" => "coins"}
    })
    |> Repo.insert!()
  end

  describe "shop economy" do
    setup do
      insert_color(100, "Rose Blush", "rose", 30)
      insert_color(101, "Dear Plum", "plum", 100_000)
      :ok
    end

    test "joining pushes the economy snapshot — wallet plus the color stock, flagged owned" do
      w = seed_world()
      _socket = join_world("u-shop", w)

      assert_push "economy", %{currency: "coins", balance: balance, colors: colors}
      # A brand-new account is gifted starting coins on creation.
      assert balance >= 120
      assert Enum.any?(colors, &(&1.item_def_id == 100 and &1.owned == false))
    end

    test "buying a color sinks coins and confirms with the new balance" do
      w = seed_world()
      socket = join_world("u-buyer", w)
      assert_push "economy", %{balance: start}

      push(socket, "buy", %{"item_def_id" => 100})
      assert_push "bought", %{item_def_id: 100, balance: balance}
      assert balance == start - 30
    end

    test "an unaffordable color fails cleanly, nothing spent" do
      w = seed_world()
      socket = join_world("u-broke", w)
      assert_push "economy", %{balance: start}

      push(socket, "buy", %{"item_def_id" => 101})
      assert_push "buy_failed", %{item_def_id: 101, reason: "insufficient_funds"}

      push(socket, "buy", %{"item_def_id" => 100})
      assert_push "bought", %{balance: balance}
      assert balance == start - 30
    end
  end

  describe "salamander hunt reward" do
    test "finishing the hunt mints coins by how many were found, crediting the wallet" do
      w = seed_hunt_world()
      socket = join_world("u-hunter", w)
      assert_push "economy", %{balance: start}

      push(socket, "hunt_complete", %{"found" => 10})
      assert_push "hunt_reward", %{found: 10, amount: 10, balance: balance, currency: "coins"}
      assert balance == start + 10
    end

    test "a partial hunt earns the lower tier; fewer than six earns nothing" do
      w = seed_hunt_world()
      socket = join_world("u-hunter-partial", w)
      assert_push "economy", %{balance: start}

      push(socket, "hunt_complete", %{"found" => 7})
      assert_push "hunt_reward", %{found: 7, amount: 2, balance: b7}
      assert b7 == start + 2

      push(socket, "hunt_complete", %{"found" => 5})
      assert_push "hunt_reward", %{found: 5, amount: 0, balance: b5}
      assert b5 == start + 2
    end

    test "the reward can't be claimed from a world without the hunt" do
      w = seed_world()
      socket = join_world("u-nohunt", w)
      assert_push "economy", %{balance: start}

      push(socket, "hunt_complete", %{"found" => 10})
      assert_push "hunt_reward", %{found: 10, amount: 0, balance: balance}
      assert balance == start
    end
  end

  # A world with one flare-able glow-plant and one ordinary prop (the night world's blooms).
  defp seed_flare_world do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "glow-#{System.unique_integer([:positive])}",
        name: "Glow",
        display_types: ["2d"],
        version: 1,
        spec: %{
          "core" => %{
            "props" => [
              %{"id" => "bloom_1", "type" => "lumen_bloom", "flare" => true},
              %{"id" => "stone_1", "type" => "moonstone"}
            ]
          },
          "profiles" => %{"2d" => %{}}
        }
      })

    world_id
  end

  describe "glow-plant flare relay" do
    test "touching a flare-able prop lights it for everyone else in the world" do
      w = seed_flare_world()
      s1 = join_world("fl-1", w)
      assert_push "welcome", %{id: _}
      _s2 = join_world("fl-2", w)
      assert_push "welcome", %{id: _}

      push(s1, "flare", %{"prop" => "bloom_1"})
      assert_push "flared", %{prop: "bloom_1"}
    end

    test "a prop the spec doesn't mark flare-able is not relayed" do
      w = seed_flare_world()
      s1 = join_world("fl-3", w)
      assert_push "welcome", %{id: _}
      _s2 = join_world("fl-4", w)
      assert_push "welcome", %{id: _}

      push(s1, "flare", %{"prop" => "stone_1"})
      push(s1, "flare", %{"prop" => "no_such_prop"})
      refute_push "flared", %{}
    end

    test "the toucher isn't echoed their own flare" do
      w = seed_flare_world()
      s1 = join_world("fl-5", w)
      assert_push "welcome", %{id: _}

      push(s1, "flare", %{"prop" => "bloom_1"})
      refute_push "flared", %{}
    end
  end

  # A world whose spec has an echo secret (Hollowsong), and one that doesn't.
  defp seed_echo_world(type) do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "echo-#{System.unique_integer([:positive])}",
        name: "Echo",
        display_types: ["2d"],
        version: 1,
        spec: %{
          "core" => %{"secret" => %{"id" => "stone", "position" => [0, 0], "reveal" => %{"type" => type}}},
          "profiles" => %{"2d" => %{}}
        }
      })

    world_id
  end

  describe "howl relay" do
    test "a howl reaches everyone else, stamped with the howler's own last position" do
      w = seed_echo_world("echo")
      s1 = join_world("hw-1", w)
      assert_push "welcome", %{id: _}
      _s2 = join_world("hw-2", w)
      assert_push "welcome", %{id: _}

      push(s1, "state", %{"p" => [120, -40]})
      push(s1, "howl", %{"x" => 9999, "y" => 9999})
      assert_push "howled", %{x: 120.0, y: -40.0}
    end

    test "a howl is limited to one per gap" do
      w = seed_echo_world("echo")
      s1 = join_world("hw-3", w)
      assert_push "welcome", %{id: _}
      _s2 = join_world("hw-4", w)
      assert_push "welcome", %{id: _}

      push(s1, "state", %{"p" => [1, 2]})
      push(s1, "howl", %{})
      assert_push "howled", %{x: 1.0, y: 2.0}
      push(s1, "howl", %{})
      refute_push "howled", %{}
    end

    test "a world without an echo secret does not relay howls" do
      w = seed_echo_world("listen")
      s1 = join_world("hw-5", w)
      assert_push "welcome", %{id: _}
      _s2 = join_world("hw-6", w)
      assert_push "welcome", %{id: _}

      push(s1, "state", %{"p" => [1, 2]})
      push(s1, "howl", %{})
      refute_push "howled", %{}
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
      assert_push "states", %{s: [[^id1, 1, 2 | _]]}, 500
    end

    test "a state frame does not cross into another world" do
      w1 = seed_world()
      w2 = seed_world()
      s1 = join_world("stx-1", w1)
      assert_push "welcome", %{id: _}
      _s2 = join_world("stx-2", w2)
      assert_push "welcome", %{id: _}

      push(s1, "state", %{"p" => [9, 9]})
      # (s1 hears its own entry, which a client skips; nothing reaches the other world's socket)
      topic2 = "world:" <> w2
      refute_receive %Phoenix.Socket.Message{topic: ^topic2, event: "states"}, 300
    end
  end

  describe "interest cells (SC-4, a world with a crowd block)" do
    # A crowd world: 100 px cells, spawn at the origin.
    defp seed_crowd_world(core \\ %{"player_spawn" => [0, 0]}) do
      world_id = Ecto.UUID.generate()

      {:ok, _} =
        Worlds.upsert(%{
          world_id: world_id,
          slug: "crowd-#{System.unique_integer([:positive])}",
          name: "Crowd",
          display_types: ["2d"],
          version: 1,
          listed: false,
          spec: %{"core" => Map.put(core, "crowd", %{"cell" => 100, "full" => 40, "lite" => 80}), "profiles" => %{"2d" => %{}}}
        })

      world_id
    end

    # Each player gets its own stand-in for the WebSocket process (the "transport"), so we can tell which
    # socket a frame reached: channel pushes AND fastlane frames go to the transport. It forwards them to
    # the test tagged with the player's name.
    defp crowd_player(name, world_id) do
      test = self()
      transport = spawn_link(fn -> forward(test, name) end)
      {:ok, socket} = connect(UserSocket, %{"token" => "crowd-#{name}-#{System.unique_integer([:positive])}"})
      {:ok, _reply, socket} = join(%{socket | transport_pid: transport}, "world:" <> world_id, %{})
      assert_receive {^name, %Phoenix.Socket.Message{event: "welcome", payload: %{id: id}}}, 1000
      {socket, id}
    end

    defp forward(test, name) do
      receive do
        msg ->
          send(test, {name, msg})
          forward(test, name)
      end
    end

    # The ids in the next "states" frame `name` receives within `ms`, or :none.
    defp next_states(name, ms \\ 500) do
      receive do
        {^name, %Phoenix.Socket.Message{event: "states", payload: %{s: entries}}} -> entries |> Jason.encode!() |> Jason.decode!()
      after
        ms -> :none
      end
    end

    defp entry_of(entries, id), do: Enum.find(entries, &(hd(&1) == id))

    # Drain every "states" frame `name` gets within `ms`; the entries for `id` among them.
    defp entries_for(name, id, ms \\ 300) do
      case next_states(name, ms) do
        :none -> []
        entries -> Enum.filter(entries, &(hd(&1) == id)) ++ entries_for(name, id, ms)
      end
    end

    test "a per-cell broadcast reaches a socket in that cell and not one elsewhere" do
      w = seed_crowd_world()
      {a, _} = crowd_player(:a, w)
      {b, _} = crowd_player(:b, w)
      push(a, "state", %{"p" => [10, 10]})
      push(b, "state", %{"p" => [1010, 10]})
      Process.sleep(150)
      _ = entries_for(:a, "x", 100)
      _ = entries_for(:b, "x", 100)

      Phoenix.PubSub.broadcast(Server.PubSub, Server.Interest.topic(w, {0, 0}), %Phoenix.Socket.Broadcast{
        topic: "world:" <> w,
        event: "states",
        payload: %{s: [["probe", 1, 1, nil, nil, nil, nil, nil, nil]]}
      })

      assert [["probe" | _]] = next_states(:a)
      assert next_states(:b, 200) == :none
    end

    test "two players far apart see nothing of each other" do
      w = seed_crowd_world()
      {a, id_a} = crowd_player(:a, w)
      {b, id_b} = crowd_player(:b, w)
      push(b, "state", %{"p" => [1000, 1000]})
      push(a, "state", %{"p" => [10, 10]})
      Process.sleep(100)

      for x <- [20, 30, 40] do
        push(a, "state", %{"p" => [x, 10]})
        push(b, "state", %{"p" => [1000 + x, 1000]})
        Process.sleep(60)
      end

      assert entries_for(:b, id_a) == []
      assert entries_for(:a, id_b) == []
    end

    test "walking up to someone starts delivery with a snapshot; walking away sends the leaving position, then nothing" do
      w = seed_crowd_world()
      {a, id_a} = crowd_player(:a, w)
      {b, id_b} = crowd_player(:b, w)
      push(a, "state", %{"p" => [10, 10], "t" => 1})
      push(b, "state", %{"p" => [1000, 10]})
      Process.sleep(150)
      _ = entries_for(:b, id_a, 100)

      # b steps into {1, 0}, next to a's cell: a snapshot of a (standing still; no stale stamp) ...
      push(b, "state", %{"p" => [150, 10]})
      assert entries_for(:b, id_a) == [[id_a, 10, 10, nil, nil, nil, nil, nil, nil]]
      # ... and a hears b arrive
      assert [[^id_b, 150, 10 | _]] = entries_for(:a, id_b)

      # a moves: b hears it now
      push(a, "state", %{"p" => [20, 10]})
      assert [[^id_a, 20, 10 | _]] = entries_for(:b, id_a)

      # b walks off to {3, 0}: a hears where b went, once ...
      push(b, "state", %{"p" => [350, 10]})
      assert [[^id_b, 350, 10 | _]] = entries_for(:a, id_b)
      # ... then nothing more, either way
      push(b, "state", %{"p" => [360, 10]})
      push(a, "state", %{"p" => [30, 10]})
      assert entries_for(:a, id_b) == []
      assert entries_for(:b, id_a) == []
    end

    test "the join snapshot is the spawn neighbourhood only" do
      w = seed_crowd_world()
      {near, id_near} = crowd_player(:near, w)
      {far, id_far} = crowd_player(:far, w)
      push(near, "state", %{"p" => [120, 0]})
      push(far, "state", %{"p" => [900, 900]})
      Process.sleep(150)

      {_c, _} = crowd_player(:c, w)
      snap = next_states(:c)
      assert entry_of(snap, id_near)
      refute entry_of(snap, id_far)
    end

    test "with no spawn, a player gets nothing until its first state, then its whole neighbourhood" do
      w = seed_crowd_world(%{})
      {a, id_a} = crowd_player(:a, w)
      push(a, "state", %{"p" => [500, 500]})
      Process.sleep(150)

      {c, _} = crowd_player(:c, w)
      assert next_states(:c, 200) == :none
      push(a, "state", %{"p" => [510, 500]})
      assert next_states(:c, 200) == :none

      push(c, "state", %{"p" => [420, 420]})
      snap = next_states(:c)
      assert [^id_a, 510, 500 | _] = entry_of(snap, id_a)
    end

    test "presence (join / leave) stays world-wide" do
      w = seed_crowd_world()
      {a, _} = crowd_player(:a, w)
      push(a, "state", %{"p" => [5000, 5000]})
      {_b, id_b} = crowd_player(:b, w)
      assert_receive {:a, %Phoenix.Socket.Message{event: "join", payload: %{id: ^id_b}}}, 1000
    end
  end
end
