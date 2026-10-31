defmodule Server.HomeAndSecretChannelTest do
  @moduledoc """
  World secrets over the channel (the server judges `claim_secret`) and the per-player home world
  (`"world:home:" <> owner`), which is built from those discoveries.
  """
  use Server.ChannelCase, async: false
  alias Server.{Accounts, Discoveries, UserSocket, World, Worlds}

  defp seed_secret_world do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "secret-#{System.unique_integer([:positive])}",
        name: "Maze",
        display_types: ["2d"],
        version: 1,
        spec: %{
          "core" => %{"secret" => %{"id" => "hedge_seed", "position" => [0.0, 0.0], "radius" => 120.0}},
          "profiles" => %{"2d" => %{}}
        }
      })

    world_id
  end

  defp connect_as(token) do
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    socket
  end

  defp user_id(token) do
    {:ok, account} = Accounts.resolve_token(token)
    account.user_id
  end

  # Report a position and wait until the world process has stored it (the cast is async).
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

  test "joining pushes the discoveries we've found" do
    t = "sec-list-#{System.unique_integer([:positive])}"
    {:ok, :new} = Discoveries.record(user_id(t), "hedge_seed")
    w = seed_secret_world()
    {:ok, _, _socket} = subscribe_and_join(connect_as(t), "world:" <> w, %{})
    assert_push "discoveries", %{ids: ["hedge_seed"]}
  end

  test "a claim at the secret is recorded once" do
    t = "sec-claim-#{System.unique_integer([:positive])}"
    uid = user_id(t)
    w = seed_secret_world()
    {:ok, _, socket} = subscribe_and_join(connect_as(t), "world:" <> w, %{})
    stand_at(socket, w, uid, [10.0, -20.0])

    push(socket, "claim_secret", %{"id" => "hedge_seed"})
    assert_push "secret_found", %{id: "hedge_seed", new: true}
    assert Discoveries.list(uid) == ["hedge_seed"]

    push(socket, "claim_secret", %{"id" => "hedge_seed"})
    assert_push "secret_found", %{id: "hedge_seed", new: false}
  end

  test "a claim from across the world is refused" do
    t = "sec-far-#{System.unique_integer([:positive])}"
    uid = user_id(t)
    w = seed_secret_world()
    {:ok, _, socket} = subscribe_and_join(connect_as(t), "world:" <> w, %{})
    stand_at(socket, w, uid, [900.0, 900.0])

    push(socket, "claim_secret", %{"id" => "hedge_seed"})
    assert_push "secret_refused", %{id: "hedge_seed"}
    assert Discoveries.list(uid) == []
  end

  test "the owner can enter their home, and it grows with their discoveries" do
    t = "home-own-#{System.unique_integer([:positive])}"
    uid = user_id(t)
    {:ok, _, _} = subscribe_and_join(connect_as(t), "world:home:" <> uid, %{})
    assert_push "world_spec", %{world_id: world_id, spec: %{"core" => empty}}
    assert world_id == "home:" <> uid
    refute Map.has_key?(empty, "hedges")

    {:ok, :new} = Discoveries.record(uid, "hedge_seed")
    {:ok, _, _} = subscribe_and_join(connect_as(t), "world:home:" <> uid, %{})
    assert_push "world_spec", %{spec: %{"core" => grown}}
    assert grown["hedges"] != []
  end

  test "nobody else can enter someone's home (yet: friends come later)" do
    owner = user_id("home-owner-#{System.unique_integer([:positive])}")
    assert {:error, %{reason: "not_allowed"}} =
             subscribe_and_join(connect_as("home-guest-#{System.unique_integer([:positive])}"), "world:home:" <> owner, %{})
  end

  test "browsing the directory from home doesn't trip over the home's non-catalog id" do
    t = "home-dir-#{System.unique_integer([:positive])}"
    uid = user_id(t)
    {:ok, _, socket} = subscribe_and_join(connect_as(t), "world:home:" <> uid, %{})
    push(socket, "list_worlds", %{"q" => "", "req" => 1})
    assert_push "world_list", %{req: 1}
  end
end
