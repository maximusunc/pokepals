defmodule Server.TankTest do
  @moduledoc """
  The fish tank at home (Server.Tank): rare fish move from the inventory into it and back, one place at a
  time, ledgered; it holds three; only rare fish go in. The channel side is in tank_channel_test.exs.
  """
  use Server.DataCase, async: true

  alias Server.{Accounts, Economy, Fishing, HomeWorld, Tank}

  setup do
    Fishing.seed_definitions()
    {:ok, account} = Accounts.resolve_token("tank-#{System.unique_integer([:positive])}")
    {:ok, uid: account.user_id}
  end

  test "a rare fish goes in and comes back out", %{uid: uid} do
    {:ok, _} = Economy.grant_stack(uid, 220, 2)
    assert Tank.contents(uid) == []
    assert {:ok, [220]} = Tank.put(uid, 220)
    assert Economy.owned_quantity(uid, 220) == 1
    assert [%{item_def_id: 220, key: "koi", name: "Moonscale Koi"}] = Tank.view(uid)

    assert {:ok, []} = Tank.take(uid, 0)
    assert Economy.owned_quantity(uid, 220) == 2
    assert Tank.contents(uid) == []
  end

  test "it holds three, and only rare fish you have", %{uid: uid} do
    {:ok, _} = Economy.grant_stack(uid, 220, 2)
    {:ok, _} = Economy.grant_stack(uid, 221, 1)
    {:ok, _} = Economy.grant_stack(uid, 222, 1)
    {:ok, _} = Economy.grant_stack(uid, 200, 1)

    assert {:error, :not_rare} = Tank.put(uid, 200)
    assert {:error, :not_rare} = Tank.put(uid, 999_999)
    assert {:ok, _} = Tank.put(uid, 220)
    assert {:ok, _} = Tank.put(uid, 220)
    assert {:error, :not_enough} = Tank.put(uid, 220)
    assert {:ok, [220, 220, 221]} = Tank.put(uid, 221)
    assert {:error, :full} = Tank.put(uid, 222)
    assert Economy.owned_quantity(uid, 222) == 1
    assert Economy.owned_quantity(uid, 200) == 1

    assert {:error, :no_fish} = Tank.take(uid, 3)
    assert {:ok, [220, 221]} = Tank.take(uid, 0)
  end

  test "the home's spec carries the tank", %{uid: uid} do
    {:ok, _} = Economy.grant_stack(uid, 222)
    {:ok, _} = Tank.put(uid, 222)
    home = HomeWorld.definition(uid, uid).spec["core"]["home"]
    assert [%{key: "old_whiskers"}] = home["tank"]
    assert home["tank_capacity"] == 3
    assert Enum.any?(HomeWorld.definition(uid, uid).spec["core"]["props"], &(&1["tank"] == true))
  end
end
