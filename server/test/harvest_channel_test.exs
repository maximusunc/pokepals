defmodule Server.HarvestChannelTest do
  @moduledoc "Chopping trees, picking things up and asking the carpenter for a house, over the channel."
  use Server.ChannelCase, async: false
  alias Server.{Accounts, Economy, Fishing, Harvest, Homes, House, UserSocket, World, Worlds}

  setup do
    Fishing.seed_definitions()
    Harvest.seed_definitions()
    Harvest.reset()
    :ok
  end

  defp seed_world(core) do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "hv-#{System.unique_integer([:positive])}",
        name: "Harvest",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => core, "profiles" => %{"2d" => %{}}}
      })

    world_id
  end

  defp join_world(world_id) do
    token = "hvc-#{System.unique_integer([:positive])}"
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

  @core %{
    "trees" => [[100.0, 100.0], [300.0, 100.0, "picket"]],
    "pickups" => [%{"id" => "s1", "kind" => "stone", "position" => [500.0, 100.0]}]
  }

  test "joining tells us what's down here, how long a chop takes, and our house" do
    w = seed_world(@core)
    :ok = Harvest.take(w, "t0", 60_000)
    {_socket, _uid} = join_world(w)
    assert_push("harvest", %{down: [%{id: "t0"}], chop_ms: 0})
    assert_push("house", %{state: "none", wood: 100, coins: 300})
  end

  test "chopping a tree takes an axe, gives two wood, and fells it for everyone until it grows back" do
    w = seed_world(@core)
    {socket, uid} = join_world(w)
    stand_at(socket, w, uid, [110.0, 115.0])

    push(socket, "chop", %{"tree" => 0})
    assert_push("harvest_refused", %{id: "t0", reason: "no_axe"})

    {:ok, _} = Economy.grant_item(uid, Harvest.axe_id())
    push(socket, "chop", %{"tree" => 0})
    assert_broadcast("harvested", %{id: "t0", left_ms: 300_000})
    assert_push("harvest_got", %{id: "t0", key: "wood", count: 2, total: 2})
    assert_push("inventory", %{items: _})
    assert Economy.owned_quantity(uid, Harvest.wood_id()) == 2

    # felled: nothing more from it until it grows back
    push(socket, "chop", %{"tree" => 0})
    assert_push("harvest_refused", %{id: "t0", reason: "gone"})
    # a picket isn't wood, and a tree across the clearing is out of reach
    stand_at(socket, w, uid, [300.0, 110.0])
    push(socket, "chop", %{"tree" => 1})
    assert_push("harvest_refused", %{reason: "not_wood"})
    push(socket, "chop", %{"tree" => 0})
    assert_push("harvest_refused", %{reason: "too_far"})
  end

  test "no chopping in a world that doesn't allow it" do
    w = seed_world(Map.put(@core, "chopping", false))
    {socket, uid} = join_world(w)
    {:ok, _} = Economy.grant_item(uid, Harvest.axe_id())
    stand_at(socket, w, uid, [110.0, 115.0])
    push(socket, "chop", %{"tree" => 0})
    assert_push("harvest_refused", %{reason: "no_chopping"})
  end

  test "a timed chop needs its start first" do
    Application.put_env(:server, Harvest, chop_ms: 1)

    try do
      w = seed_world(@core)
      {socket, uid} = join_world(w)
      {:ok, _} = Economy.grant_item(uid, Harvest.axe_id())
      stand_at(socket, w, uid, [110.0, 115.0])
      push(socket, "chop", %{"tree" => 0})
      assert_push("harvest_refused", %{reason: "not_yet"})
      push(socket, "chop_start", %{"tree" => 0})
      push(socket, "chop", %{"tree" => 0})
      assert_push("harvest_got", %{id: "t0", count: 2})
    after
      Application.delete_env(:server, Harvest)
    end
  end

  test "picking up a stone: one each, gone for everyone for a while" do
    w = seed_world(@core)
    {socket, uid} = join_world(w)
    push(socket, "gather", %{"id" => "s1"})
    assert_push("harvest_refused", %{id: "s1", reason: "too_far"})
    stand_at(socket, w, uid, [490.0, 110.0])
    push(socket, "gather", %{"id" => "s1"})
    assert_broadcast("harvested", %{id: "s1", left_ms: 180_000})
    assert_push("harvest_got", %{id: "s1", key: "stone", count: 1, total: 1})
    push(socket, "gather", %{"id" => "s1"})
    assert_push("harvest_refused", %{reason: "gone"})
  end

  test "the carpenter builds a house only from her stall, for the wood and the coins" do
    w =
      seed_world(%{
        "props" => [%{"id" => "carpenter", "position" => [100.0, 100.0], "builds" => "house"}]
      })

    {socket, uid} = join_world(w)
    {:ok, _} = Economy.grant_stack(uid, Harvest.wood_id(), 100)
    {:ok, _} = Economy.grant_currency(uid, "coins", 400)
    balance = Economy.balance(uid, "coins")

    stand_at(socket, w, uid, [600.0, 600.0])
    push(socket, "commission_house", %{})
    assert_push("house_refused", %{reason: "not_at_carpenter"})

    stand_at(socket, w, uid, [110.0, 120.0])
    push(socket, "commission_house", %{})
    assert_push("house_commissioned", %{house: %{state: "building"}, balance: new_balance})
    assert new_balance == balance - 300
    assert Economy.owned_quantity(uid, Harvest.wood_id()) == 0
    assert %{"started_at" => _} = Homes.get(uid).house

    push(socket, "commission_house", %{})
    assert_push("house_refused", %{reason: "have_house"})
    assert House.status(uid).state == "building"
  end
end
