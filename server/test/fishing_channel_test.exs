defmodule Server.FishingChannelTest do
  @moduledoc """
  Fishing over the channel: taking the starter rod at its post, casting, and reeling in. The server
  judges each step (Server.Fishing); these check it says yes and no in the right places.
  """
  use Server.ChannelCase, async: false
  alias Server.{Accounts, Economy, Fishing, UserSocket, World, Worlds}

  @post [100.0, 50.0]

  setup do
    Fishing.seed_definitions()
    :ok
  end

  defp seed_world(extra \\ %{}) do
    world_id = Ecto.UUID.generate()

    core =
      Map.merge(
        %{"props" => [%{"id" => "rod_post", "type" => "rod_post", "position" => @post, "gives" => "rod", "interactive" => true}]},
        extra
      )

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "pond-#{System.unique_integer([:positive])}",
        name: "Pond",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => core, "profiles" => %{"2d" => %{}}}
      })

    world_id
  end

  defp join_world(token, world_id) do
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

  defp token, do: "fishc-#{System.unique_integer([:positive])}"

  test "joining pushes our inventory and an empty hotbar" do
    w = seed_world()
    {_socket, _uid} = join_world(token(), w)
    assert_push "inventory", %{items: []}
    assert_push "hotbar", %{slots: [nil, nil, nil, nil, nil]}
  end

  test "the rod is taken at its post, once, and lands in the first hotbar slot" do
    w = seed_world()
    {socket, uid} = join_world(token(), w)
    rod = Fishing.rod_id()

    stand_at(socket, w, uid, [400.0, 400.0])
    push(socket, "take_rod", %{})
    assert_push "rod_taken", %{ok: false}
    assert Economy.owned_quantity(uid, rod) == 0

    stand_at(socket, w, uid, [110.0, 60.0])
    push(socket, "take_rod", %{})
    assert_push "rod_taken", %{ok: true, new: true}
    assert_push "inventory", %{items: [%{item_def_id: ^rod, key: "rod", quantity: 1}]}
    assert_push "hotbar", %{slots: [^rod, nil, nil, nil, nil]}

    push(socket, "take_rod", %{})
    assert_push "rod_taken", %{ok: true, new: false}
    assert Economy.owned_quantity(uid, rod) == 1
  end

  test "no rod, no cast" do
    w = seed_world()
    {socket, _uid} = join_world(token(), w)
    push(socket, "cast", %{})
    assert_push "fish_refused", %{reason: "no_rod"}
  end

  test "a world that opts out of fishing refuses the cast" do
    w = seed_world(%{"fishing" => false})
    {socket, uid} = join_world(token(), w)
    {:ok, _} = Economy.grant_item(uid, Fishing.rod_id())
    push(socket, "cast", %{})
    assert_push "fish_refused", %{reason: "no_fishing"}
  end

  test "cast, bite, a landed reel: the catch goes into the inventory" do
    w = seed_world()
    {socket, uid} = join_world(token(), w)
    {:ok, _} = Economy.grant_item(uid, Fishing.rod_id())

    push(socket, "cast", %{})
    assert_push "fish_hooked", %{wait_ms: 0, window: window, speed: speed}
    assert window > 0 and speed > 0

    push(socket, "reel", %{"landed" => true})
    assert_push "fish_caught", %{item_def_id: id, name: name, count: 1}
    assert is_binary(name)
    assert Economy.owned_quantity(uid, id) == 1
    assert_push "inventory", %{items: [_ | _] = items}
    assert Enum.any?(items, &(&1.item_def_id == id and &1.quantity == 1))
  end

  test "a missed reel lets it go, and a reel with nothing hooked catches nothing" do
    w = seed_world()
    {socket, uid} = join_world(token(), w)
    {:ok, _} = Economy.grant_item(uid, Fishing.rod_id())

    push(socket, "cast", %{})
    assert_push "fish_hooked", %{}
    push(socket, "reel", %{"landed" => false})
    assert_push "fish_escaped", %{}

    # The hook was used up: reeling again (even "landed") catches nothing.
    push(socket, "reel", %{"landed" => true})
    assert_push "fish_escaped", %{}
    assert Enum.all?(Fishing.catches(), &(Economy.owned_quantity(uid, &1.id) == 0))
  end

  test "casts too close together are refused" do
    w = seed_world()
    {socket, uid} = join_world(token(), w)
    {:ok, _} = Economy.grant_item(uid, Fishing.rod_id())
    push(socket, "cast", %{})
    assert_push "fish_hooked", %{}
    push(socket, "cast", %{})
    assert_push "fish_refused", %{reason: "too_soon"}
  end

  test "what we hold and our fishing are relayed with our identity, and junk is dropped" do
    w = seed_world()
    {socket, uid} = join_world(token(), w)

    push(socket, "identity", %{"held" => "rod", "fishing" => %{"b" => [12, 30], "ph" => "wait", "n" => 2}})
    wait_until(fn -> get_in(presence_identity(w, uid), ["held"]) == "rod" end)
    assert %{"b" => [12, 30], "ph" => "wait", "n" => 2} = presence_identity(w, uid)["fishing"]

    catch_info = %{"b" => [12, 30], "ph" => "caught", "n" => 3, "k" => "koi", "r" => "rare_fish", "c" => [1, 0.9, 0.8]}
    push(socket, "identity", %{"held" => "rod", "fishing" => catch_info})
    wait_until(fn -> get_in(presence_identity(w, uid), ["fishing", "n"]) == 3 end)
    assert presence_identity(w, uid)["fishing"] == catch_info

    push(socket, "identity", %{"held" => "rod", "fishing" => Map.merge(catch_info, %{"n" => 4, "r" => "dragon", "c" => "red"})})
    wait_until(fn -> get_in(presence_identity(w, uid), ["fishing", "n"]) == 4 end)
    refute Map.has_key?(presence_identity(w, uid)["fishing"], "r")
    refute Map.has_key?(presence_identity(w, uid)["fishing"], "c")

    push(socket, "identity", %{"held" => String.duplicate("x", 99), "fishing" => %{"b" => "nope", "ph" => "wait"}})
    wait_until(fn -> get_in(presence_identity(w, uid), ["held"]) == "" end)
    refute Map.has_key?(presence_identity(w, uid), "fishing")
    _ = socket
  end

  defp presence_identity(world_id, uid) do
    case Server.Presence.list("world:" <> world_id) do
      %{^uid => %{metas: [meta | _]}} -> meta[:identity] || %{}
      _ -> %{}
    end
  end
end
