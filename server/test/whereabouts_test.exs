defmodule Server.WhereaboutsTest do
  @moduledoc """
  Where a player last stood (Server.Whereabouts) — remembered in Postgres, so it outlives the socket
  and the server — and how the world channel uses it: a cold boot's `resume: true` join resumes in
  the same world at that spot (`resume` push), or is refused with `relocate` toward the world the
  player was last in.
  """
  use Server.ChannelCase, async: false
  alias Server.{Accounts, UserSocket, Whereabouts, Worlds}

  defp user_id(token) do
    {:ok, account} = Accounts.resolve_token(token)
    account.user_id
  end

  defp token, do: "where#{System.unique_integer([:positive])}"

  defp seed_world do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "where-#{System.unique_integer([:positive])}",
        name: "W",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => %{}, "profiles" => %{"2d" => %{}}}
      })

    world_id
  end

  defp connect_as(token) do
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    socket
  end

  describe "remember / recall" do
    test "a player we've never seen move has nowhere to resume" do
      assert Whereabouts.recall(user_id(token())) == nil
    end

    test "round-trips, and the latest write wins" do
      uid = user_id(token())
      :ok = Whereabouts.remember(uid, "w1", [10, 20])
      :ok = Whereabouts.remember(uid, "w2", [30.5, 40])
      assert Whereabouts.recall(uid) == %{world_id: "w2", p: [30.5, 40.0]}
    end

    test "position/1 takes only a sane player position from a transform" do
      assert Whereabouts.position(%{"p" => [1, 2], "c" => [3, 4]}) == [1.0, 2.0]
      assert Whereabouts.position(%{"p" => [1, "x"]}) == nil
      assert Whereabouts.position(%{"p" => [1.0e9, 0]}) == nil
      assert Whereabouts.position(%{"c" => [3, 4]}) == nil
    end
  end

  describe "resume_target" do
    test "the same world resumes at the spot; another enterable world relocates; a gone one doesn't" do
      uid = user_id(token())
      here = seed_world()
      there = seed_world()

      assert Whereabouts.resume_target(uid, here) == :none

      Whereabouts.remember(uid, here, [100, 200])
      assert Whereabouts.resume_target(uid, here) == {:here, [100.0, 200.0]}

      Whereabouts.remember(uid, there, [5, 6])
      assert Whereabouts.resume_target(uid, here) == {:elsewhere, there}

      Whereabouts.remember(uid, Ecto.UUID.generate(), [5, 6])
      assert Whereabouts.resume_target(uid, here) == :none

      Whereabouts.remember(uid, "not-a-uuid", [5, 6])
      assert Whereabouts.resume_target(uid, here) == :none
    end

    test "your own home is resumable; a stranger's home isn't" do
      uid = user_id(token())
      stranger = user_id(token())
      vale = seed_world()

      Whereabouts.remember(uid, "home:" <> uid, [1, 2])
      assert Whereabouts.resume_target(uid, vale) == {:elsewhere, "home:" <> uid}

      Whereabouts.remember(uid, "home:" <> stranger, [1, 2])
      assert Whereabouts.resume_target(uid, vale) == :none
    end
  end

  describe "the world channel" do
    test "leaving saves where we stood, and a resuming join in that world is set down there" do
      t = token()
      w = seed_world()

      {:ok, _, socket} = subscribe_and_join(connect_as(t), "world:" <> w, %{})
      assert_push "welcome", %{}
      push(socket, "state", %{"p" => [321.4, 654.0], "c" => [300, 640]})
      # A synchronous round trip, so the state frame has been handled before we leave.
      push(socket, "list_worlds", %{"req" => 1})
      assert_push "world_list", %{req: 1}
      Process.unlink(socket.channel_pid)
      close(socket)

      assert Whereabouts.recall(user_id(t)) == %{world_id: w, p: [321.4, 654.0]}

      {:ok, _, _socket} = subscribe_and_join(connect_as(t), "world:" <> w, %{"resume" => true})
      assert_push "resume", %{world_id: ^w, p: [321.4, 654.0]}
    end

    test "a resuming join elsewhere is refused with relocate toward the world we were last in" do
      t = token()
      last = seed_world()
      vale = seed_world()
      Whereabouts.remember(user_id(t), last, [10, 10])

      assert {:error, %{reason: "relocate", world_id: ^last}} =
               subscribe_and_join(connect_as(t), "world:" <> vale, %{"resume" => true})

      # Without asking to resume (a world hop, a reconnect), the join is simply honoured.
      assert {:ok, _, _} = subscribe_and_join(connect_as(t), "world:" <> vale, %{})
      refute_push "resume", %{}
    end

    test "a brand-new player's resuming join just enters, with nothing to resume" do
      w = seed_world()
      assert {:ok, _, _} = subscribe_and_join(connect_as(token()), "world:" <> w, %{"resume" => true})
      assert_push "welcome", %{}
      refute_push "resume", %{}
    end
  end
end
