defmodule Server.CraftingTest do
  @moduledoc """
  Crafting (Server.Crafting): the tinker makes a lantern from a sea-glass, a firefly and a driftwood plus a
  fee, all in one ledgered transaction, onto the hotbar; and the firefly glades. Channel side below.
  """
  use Server.DataCase, async: true

  alias Server.{Accounts, Crafting, Economy, Fishing, Hotbar}

  setup do
    Fishing.seed_definitions()
    Crafting.seed_definitions()
    {:ok, account} = Accounts.resolve_token("craft-#{System.unique_integer([:positive])}")
    {:ok, uid: account.user_id}
  end

  defp stock(uid) do
    for id <- [241, 250, 242], do: {:ok, _} = Economy.grant_stack(uid, id)
    :ok
  end

  test "a lantern from a sea-glass, a firefly and a driftwood, for 10 coins", %{uid: uid} do
    stock(uid)
    coins = Economy.balance(uid, "coins")
    assert {:ok, %{item_def_id: 4, name: "Lantern", balance: balance}} = Crafting.craft(uid, "lantern")
    assert balance == coins - 10
    assert Economy.owned_quantity(uid, 4) == 1
    for id <- [241, 250, 242], do: assert(Economy.owned_quantity(uid, id) == 0)
    assert 4 in Hotbar.slots(uid)
    assert Economy.ledger_balance(uid, "coins") == Economy.balance(uid, "coins")
  end

  test "missing a material, or the fee, makes nothing and takes nothing", %{uid: uid} do
    {:ok, _} = Economy.grant_stack(uid, 241)
    {:ok, _} = Economy.grant_stack(uid, 250)
    assert {:error, :not_enough} = Crafting.craft(uid, "lantern")
    assert Economy.owned_quantity(uid, 241) == 1 and Economy.owned_quantity(uid, 250) == 1

    {:ok, _} = Economy.grant_stack(uid, 242)
    {:ok, _} = Economy.sink_currency(uid, "coins", Economy.balance(uid, "coins"))
    assert {:error, :insufficient_funds} = Crafting.craft(uid, "lantern")
    for id <- [241, 250, 242], do: assert(Economy.owned_quantity(uid, id) == 1)
    assert Economy.owned_quantity(uid, 4) == 0

    assert {:error, :no_recipe} = Crafting.craft(uid, "dragon")
  end

  test "you can craft a spare", %{uid: uid} do
    stock(uid)
    stock(uid)
    assert {:ok, _} = Crafting.craft(uid, "lantern")
    assert {:ok, _} = Crafting.craft(uid, "lantern")
    assert Economy.owned_quantity(uid, 4) == 2
    assert Enum.count(Hotbar.slots(uid), &(&1 == 4)) == 1
  end

  test "the recipe the client shows" do
    assert [%{id: "lantern", fee: 10, makes: %{key: "lantern"}, needs: needs}] = Crafting.recipes_view()
    assert Enum.map(needs, & &1.key) == ["sea_glass", "firefly", "driftwood"]
  end

  test "the tinker and the firefly glades are only where they are" do
    core = %{
      "props" => [%{"id" => "tinker", "position" => [0, 0], "crafts" => true}],
      "firefly_glades" => [%{"position" => [500, 500], "radius" => 70}]
    }

    assert Crafting.at_crafter?(core, [20.0, 30.0])
    refute Crafting.at_crafter?(core, [300.0, 30.0])
    assert Crafting.at_firefly_glade?(core, [560.0, 540.0])
    refute Crafting.at_firefly_glade?(core, [700.0, 700.0])
    refute Crafting.at_firefly_glade?(%{}, [0.0, 0.0])
  end
end
