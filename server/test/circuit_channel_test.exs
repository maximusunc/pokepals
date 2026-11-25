defmodule Server.CircuitChannelTest do
  @moduledoc "Ohmstead's ribbon boards over the channel: the join push, laying a ribbon together, what closing pays, and the secret."
  use Server.ChannelCase, async: false
  alias Server.{Accounts, Circuit, Discoveries, Economy, UserSocket, World, Worlds}
  alias Server.Circuit.Board

  @solution [10, 11, 6, 5, 0, 1, 2, 7, 12, 13, 8, 3, 4, 9, 14, 19, 18, 17]
  @core %{
    "circuits" => %{
      "boards" => [
        %{"id" => "sector", "kind" => "fixed", "cols" => 5, "rows" => 4, "holes" => [15, 16], "source" => 10, "sink" => 17},
        %{"id" => "table", "kind" => "dealt", "cols" => 4, "rows" => 3, "holes" => 0}
      ],
      "reward" => %{"table" => %{"coins" => 5, "sparks" => 1}}
    },
    "secret" => %{"id" => "steady_spark", "position" => [0.0, 0.0], "radius" => 120.0, "reveal" => %{"type" => "circuit", "board" => "sector"}}
  }

  setup do
    Circuit.seed_definitions()
    Circuit.reset()
    :ok
  end

  defp seed_world(core) do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "ck-#{System.unique_integer([:positive])}",
        name: "Circuit",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => core, "profiles" => %{"2d" => %{}}}
      })

    world_id
  end

  defp join_world(world_id) do
    token = "ckc-#{System.unique_integer([:positive])}"
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    {:ok, _, socket} = subscribe_and_join(socket, "world:" <> world_id, %{})
    {:ok, account} = Accounts.resolve_token(token)
    {socket, account.user_id}
  end

  defp stand_at(socket, world_id, user_id, pos) do
    push(socket, "state", %{"p" => pos})
    wait_until(fn -> Map.get(World.snapshot(world_id), user_id, %{})["p"] == pos end)
  end

  defp wait_until(f, tries \\ 50) do
    cond do
      f.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(10) && wait_until(f, tries - 1)
    end
  end

  test "joining tells us how every board stands; a world without boards says nothing" do
    w = seed_world(@core)
    {_socket, _uid} = join_world(w)
    assert_push("circuits", %{boards: [%{id: "sector", path: [], closed: false}, %{id: "table", kind: "dealt"}]})

    plain = seed_world(%{})
    {_socket, _uid} = join_world(plain)
    refute_push("circuits", _)
  end

  test "a run goes to everyone; a move the rules don't allow is refused to the one who made it" do
    w = seed_world(@core)
    {socket, uid} = join_world(w)
    push(socket, "circuit_run", %{"board" => "sector", "node" => 3})
    assert_push("circuit_refused", %{board: "sector", node: 3, reason: "no_run"})
    push(socket, "circuit_run", %{"board" => "sector", "node" => 10})
    assert_broadcast("circuit", %{id: "sector", path: [10], by: [^uid]})
    push(socket, "circuit_run", %{"board" => "sector", "node" => 14})
    assert_broadcast("circuit", %{id: "sector", path: [10, 11, 12, 13, 14]})
    push(socket, "circuit_wind", %{"board" => "sector", "node" => 11})
    assert_broadcast("circuit", %{id: "sector", path: [10, 11]})
    push(socket, "circuit_clear", %{"board" => "sector"})
    assert_broadcast("circuit", %{id: "sector", path: []})
  end

  test "the spark can only be claimed while the sector's board is closed" do
    w = seed_world(@core)
    {socket, uid} = join_world(w)
    stand_at(socket, w, uid, [10.0, 10.0])

    push(socket, "claim_secret", %{"id" => "steady_spark"})
    assert_push("secret_refused", %{id: "steady_spark"})

    for n <- @solution, do: push(socket, "circuit_run", %{"board" => "sector", "node" => n})
    assert_broadcast("circuit", %{id: "sector", closed: true})
    # the dark sector pays nothing: its prize is the secret
    refute_push("circuit_reward", _)

    push(socket, "claim_secret", %{"id" => "steady_spark"})
    assert_push("secret_found", %{id: "steady_spark", new: true})
    assert Discoveries.list(uid) == ["steady_spark"]
  end

  test "closing the Arcade's table pays everyone who laid part of it, coins and sparks" do
    w = seed_world(@core)
    {sa, ua} = join_world(w)
    {sb, ub} = join_world(w)
    [_, table] = Circuit.snapshot(w, @core["circuits"])
    board = Board.new(%{"cols" => 4, "rows" => 3, "holes" => table.holes, "source" => table.source, "sink" => table.sink})
    path = Server.CircuitTest.solve(board)
    {mine, theirs} = Enum.split(path, 5)
    before_a = Economy.balance(ua, "coins")
    before_b = Economy.balance(ub, "coins")

    for n <- mine, do: push(sa, "circuit_run", %{"board" => "table", "node" => n})
    # (wait for the first half to land: the two sockets are separate processes)
    assert_broadcast("circuit", %{id: "table", path: ^mine})
    for n <- theirs, do: push(sb, "circuit_run", %{"board" => "table", "node" => n})

    assert_broadcast("circuit", %{id: "table", closed: true, by: by})
    assert Enum.sort(by) == Enum.sort([ua, ub])
    assert_push("circuit_reward", %{board: "table", coins: 5, sparks: 1, time_ms: _, balance: _})
    assert_push("circuit_reward", %{board: "table", coins: 5, sparks: 1})
    assert Economy.balance(ua, "coins") == before_a + 5
    assert Economy.balance(ub, "coins") == before_b + 5
    assert Economy.owned_quantity(ua, Circuit.spark_id()) == 1
    assert Economy.owned_quantity(ub, Circuit.spark_id()) == 1
  end
end
