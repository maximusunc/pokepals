defmodule Server.TankChannelTest do
  @moduledoc "The fish tank over the channel: only the owner, in their own home, changes it, and everyone there sees it."
  use Server.ChannelCase, async: false
  alias Server.{Accounts, Economy, Fishing, UserSocket}

  setup do
    Fishing.seed_definitions()
    :ok
  end

  defp join_home(token, owner_id) do
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    {:ok, _, socket} = subscribe_and_join(socket, "world:home:" <> owner_id, %{})
    socket
  end

  defp uid(token) do
    {:ok, account} = Accounts.resolve_token(token)
    account.user_id
  end

  test "the owner puts a rare fish in and takes it out; everyone in the home sees" do
    t = "tankc-#{System.unique_integer([:positive])}"
    owner = uid(t)
    {:ok, _} = Economy.grant_stack(owner, 221)
    socket = join_home(t, owner)

    push(socket, "tank_put", %{"item_def_id" => 221})
    assert_broadcast "tank", %{owner: ^owner, fish: [%{item_def_id: 221, key: "ember_trout"}]}
    # (the join pushed our inventory with the trout in it; after the put it's gone)
    assert_push "inventory", %{items: []}

    push(socket, "tank_take", %{"index" => 0})
    assert_broadcast "tank", %{fish: []}
    assert Economy.owned_quantity(owner, 221) == 1

    push(socket, "tank_put", %{"item_def_id" => 200})
    assert_push "tank_failed", %{reason: "not_rare"}
  end

  test "outside your own home, the tank can't be changed" do
    t = "tankc-#{System.unique_integer([:positive])}"
    me = uid(t)
    {:ok, _} = Economy.grant_stack(me, 220)
    {:ok, w} =
      Server.Worlds.upsert(%{world_id: Ecto.UUID.generate(), slug: "tk-#{System.unique_integer([:positive])}", name: "Elsewhere",
        display_types: ["2d"], version: 1, spec: %{"core" => %{}, "profiles" => %{"2d" => %{}}}})

    {:ok, socket} = connect(UserSocket, %{"token" => t})
    {:ok, _, socket} = subscribe_and_join(socket, "world:" <> w.world_id, %{})
    push(socket, "tank_put", %{"item_def_id" => 220})
    assert_push "tank_failed", %{reason: "not_home"}
    assert Economy.owned_quantity(me, 220) == 1
  end
end
