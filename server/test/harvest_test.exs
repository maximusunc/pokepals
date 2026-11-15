defmodule Server.HarvestTest do
  @moduledoc """
  Harvesting (Server.Harvest): which trees can be chopped and where, what a pickup gives, the shared
  "felled until it grows back" state, and the axe recipe at the tinker. Channel side in harvest_channel_test.
  """
  use Server.DataCase, async: false

  alias Server.{Accounts, Crafting, Economy, Fishing, Harvest, Hotbar}

  @core %{
    "trees" => [[100, 100], [200, 100, "picket"], [300, 100, "oak"]],
    "pickups" => [
      %{"id" => "s1", "kind" => "stone", "position" => [50, 50]},
      %{"id" => "d1", "kind" => "driftwood", "position" => [80, 50]},
      %{"id" => "x1", "kind" => "gold", "position" => [90, 50]}
    ]
  }

  setup do
    Harvest.reset()
    :ok
  end

  test "a world allows chopping unless it says not to" do
    assert Harvest.chopping_allowed?(%{})
    refute Harvest.chopping_allowed?(%{"chopping" => false})
  end

  test "a tree is chopped only if it's wood, the world allows it, and you're within reach" do
    assert {:ok, {100, 100, "tree"}} = Harvest.check_tree(@core, 0, [120, 110])
    assert {:ok, {300, 100, "oak"}} = Harvest.check_tree(@core, 2, [300, 130])
    assert {:error, :not_wood} = Harvest.check_tree(@core, 1, [200, 110])
    assert {:error, :too_far} = Harvest.check_tree(@core, 0, [300, 300])
    assert {:error, :no_tree} = Harvest.check_tree(@core, 9, [100, 100])

    assert {:error, :no_chopping} =
             Harvest.check_tree(Map.put(@core, "chopping", false), 0, [100, 100])

    assert {:error, :too_far} = Harvest.check_tree(@core, 0, nil)
  end

  test "pickups: stones and driftwood, within reach" do
    assert {:ok, %{"kind" => "stone"}} = Harvest.check_pickup(@core, "s1", [60, 60])
    assert Harvest.pickup_item("stone") == Harvest.stone_id()
    assert Harvest.pickup_item("driftwood") == 242
    assert {:error, :too_far} = Harvest.check_pickup(@core, "d1", [400, 400])
    assert {:error, :no_pickup} = Harvest.check_pickup(@core, "x1", [90, 50])
    assert {:error, :no_pickup} = Harvest.check_pickup(@core, "nope", [90, 50])
  end

  test "a felled tree is down for everyone until it grows back" do
    refute Harvest.down?("w", "t0")
    assert :ok = Harvest.take("w", "t0", 60_000)
    assert Harvest.down?("w", "t0")
    assert {:error, :gone} = Harvest.take("w", "t0", 60_000)
    assert [%{id: "t0", left_ms: left}] = Harvest.down("w")
    assert left > 59_000 and left <= 60_000
    # other worlds, and other trees, are untouched
    assert Harvest.down("other") == []
    assert :ok = Harvest.take("w", "t1", 0)
    # a 0 ms regrow is back at once
    refute Harvest.down?("w", "t1")
    assert :ok = Harvest.take("w", "t1", 10)
  end

  test "it grows back: a node whose time has passed can be taken again" do
    assert :ok = Harvest.take("w2", "s1", 1)
    Process.sleep(5)
    refute Harvest.down?("w2", "s1")
    assert Harvest.down("w2") == []
    assert :ok = Harvest.take("w2", "s1", 1)
  end

  test "a timed chop is honoured only on the tree you started on, once its time has passed" do
    assert Harvest.chop_ripe?(nil, "t0", 0)
    Application.put_env(:server, Harvest, chop_ms: 2_000)

    try do
      refute Harvest.chop_ripe?(nil, "t0", 10_000)
      refute Harvest.chop_ripe?({"t1", 0}, "t0", 10_000)
      refute Harvest.chop_ripe?({"t0", 9_000}, "t0", 10_000)
      assert Harvest.chop_ripe?({"t0", 8_000}, "t0", 10_000)
    after
      Application.delete_env(:server, Harvest)
    end
  end

  describe "the axe" do
    setup do
      Fishing.seed_definitions()
      Crafting.seed_definitions()
      Harvest.seed_definitions()
      {:ok, account} = Accounts.resolve_token("axe-#{System.unique_integer([:positive])}")
      {:ok, uid: account.user_id}
    end

    test "the tinker makes an axe from three driftwood and two stones, onto the hotbar", %{
      uid: uid
    } do
      {:ok, _} = Economy.grant_stack(uid, 242, 3)
      {:ok, _} = Economy.grant_stack(uid, Harvest.stone_id(), 2)
      coins = Economy.balance(uid, "coins")
      assert {:ok, %{item_def_id: 11, name: "Axe", balance: ^coins}} = Crafting.craft(uid, "axe")
      assert Economy.owned_quantity(uid, Harvest.axe_id()) == 1

      assert Economy.owned_quantity(uid, 242) == 0 and
               Economy.owned_quantity(uid, Harvest.stone_id()) == 0

      assert Harvest.axe_id() in Hotbar.slots(uid)
    end

    test "one stone short makes nothing and takes nothing", %{uid: uid} do
      {:ok, _} = Economy.grant_stack(uid, 242, 3)
      {:ok, _} = Economy.grant_stack(uid, Harvest.stone_id(), 1)
      assert {:error, :not_enough} = Crafting.craft(uid, "axe")

      assert Economy.owned_quantity(uid, 242) == 3 and
               Economy.owned_quantity(uid, Harvest.stone_id()) == 1
    end

    test "the recipe as the client sees it names the axe and its makings" do
      axe = Enum.find(Crafting.recipes_view(), &(&1.id == "axe"))
      assert axe.makes.key == "axe" and axe.fee == 0
      assert [%{key: "driftwood", quantity: 3}, %{key: "stone", quantity: 2}] = axe.needs
    end
  end
end
