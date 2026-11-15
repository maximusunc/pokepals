defmodule Server.HouseTest do
  @moduledoc """
  The house (Server.House): the carpenter takes 100 wood and 300 coins in one transaction and starts
  building; it's done `build_ms` later, worked out from when she started and the CURRENT build time.
  """
  use Server.DataCase, async: false

  alias Server.{Accounts, Economy, Harvest, Homes, House}

  setup do
    Harvest.seed_definitions()
    {:ok, account} = Accounts.resolve_token("house-#{System.unique_integer([:positive])}")
    {:ok, uid: account.user_id}
  end

  defp stock(uid, wood, coins) do
    if wood > 0, do: {:ok, _} = Economy.grant_stack(uid, Harvest.wood_id(), wood)
    have = Economy.balance(uid, "coins")

    cond do
      coins > have -> {:ok, _} = Economy.grant_currency(uid, "coins", coins - have)
      coins < have -> {:ok, _} = Economy.sink_currency(uid, "coins", have - coins)
      true -> :ok
    end
  end

  test "no house to begin with", %{uid: uid} do
    assert %{state: "none", left_ms: 0, wood: 100, coins: 300, build_ms: 600_000} =
             House.status(uid)
  end

  test "the carpenter takes the wood and the coins and starts building", %{uid: uid} do
    stock(uid, 104, 320)

    assert {:ok, %{status: %{state: "building", left_ms: left}, balance: 20}} =
             House.commission(uid)

    assert left > 590_000
    assert Economy.owned_quantity(uid, Harvest.wood_id()) == 4
    assert Economy.ledger_balance(uid, "coins") == Economy.balance(uid, "coins")
    assert %{"started_at" => started} = Homes.get(uid).house
    assert is_integer(started)
    assert {:error, :have_house} = House.commission(uid)
  end

  test "short of wood or of coins: nothing moves", %{uid: uid} do
    stock(uid, 99, 500)
    assert {:error, :not_enough} = House.commission(uid)
    assert Economy.owned_quantity(uid, Harvest.wood_id()) == 99
    assert Economy.balance(uid, "coins") == 500
    assert Homes.get(uid).house == nil

    stock(uid, 1, 299)
    assert {:error, :insufficient_funds} = House.commission(uid)
    assert Economy.owned_quantity(uid, Harvest.wood_id()) == 100
    assert Homes.get(uid).house == nil
  end

  test "it's built once the build time has passed, by the current build time" do
    started = 1_000_000
    assert House.state(nil, started) == "none"
    assert House.state(%{"started_at" => started}, started + 1) == "building"
    assert House.state(%{"started_at" => started}, started + 600_000) == "built"

    assert %{state: "building", left_ms: 400_000} =
             House.view(%{"started_at" => started}, started + 200_000)

    Application.put_env(:server, House, build_ms: 100_000)

    try do
      assert House.state(%{"started_at" => started}, started + 200_000) == "built"
    after
      Application.delete_env(:server, House)
    end
  end

  test "the carpenter is at a prop that builds houses" do
    core = %{"props" => [%{"id" => "c", "position" => [10, 10], "builds" => "house"}]}
    assert House.at_carpenter?(core, [40, 40])
    refute House.at_carpenter?(core, [400, 400])
    refute House.at_carpenter?(%{}, [10, 10])
  end
end
