defmodule Server.CraftingChannelTest do
  @moduledoc "Crafting at the tinker and inviting fireflies along, over the channel."
  use Server.ChannelCase, async: false
  alias Server.{Accounts, Crafting, Economy, Fishing, UserSocket, World, Worlds}

  setup do
    Fishing.seed_definitions()
    Crafting.seed_definitions()
    :ok
  end

  defp seed_world(core) do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{world_id: world_id, slug: "cr-#{System.unique_integer([:positive])}", name: "Craft",
        display_types: ["2d"], version: 1, spec: %{"core" => core, "profiles" => %{"2d" => %{}}}})

    world_id
  end

  defp join_world(world_id) do
    token = "crc-#{System.unique_integer([:positive])}"
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

  test "joining tells us the recipes" do
    w = seed_world(%{})
    {_socket, _uid} = join_world(w)
    assert_push "recipes", %{recipes: [%{id: "lantern"}]}
  end

  test "crafting a lantern at the tinker, and only there" do
    w = seed_world(%{"props" => [%{"id" => "tinker", "position" => [100.0, 100.0], "crafts" => true}]})
    {socket, uid} = join_world(w)
    for id <- [241, 250, 242], do: {:ok, _} = Economy.grant_stack(uid, id)

    stand_at(socket, w, uid, [600.0, 600.0])
    push(socket, "craft", %{"recipe" => "lantern"})
    assert_push "craft_failed", %{reason: "not_at_crafter"}

    stand_at(socket, w, uid, [110.0, 120.0])
    push(socket, "craft", %{"recipe" => "lantern"})
    assert_push "crafted", %{item_def_id: 4, name: "Lantern"}
    assert_push "hotbar", %{slots: [4 | _]}
    assert Economy.owned_quantity(uid, 4) == 1

    push(socket, "craft", %{"recipe" => "lantern"})
    assert_push "craft_failed", %{reason: "not_enough"}
  end

  test "a firefly comes into the jar, and only one at a time" do
    w = seed_world(%{"props" => [%{"id" => "jar", "position" => [200.0, 200.0], "firefly_jar" => true, "interactive" => true}]})
    {socket, uid} = join_world(w)

    stand_at(socket, w, uid, [700.0, 700.0])
    push(socket, "catch_firefly", %{})
    assert_push "firefly_refused", %{reason: "no_jar"}

    stand_at(socket, w, uid, [210.0, 220.0])
    push(socket, "catch_firefly", %{})
    assert_push "firefly_caught", %{count: 1}
    push(socket, "catch_firefly", %{})
    assert_push "firefly_refused", %{reason: "have_one"}
    assert Economy.owned_quantity(uid, Crafting.firefly_id()) == 1
  end
end
