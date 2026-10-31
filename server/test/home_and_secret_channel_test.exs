defmodule Server.HomeAndSecretChannelTest do
  @moduledoc """
  World secrets over the channel (the server judges `claim_secret`) and the per-player home world
  (`"world:home:" <> owner`), which is built from those discoveries.
  """
  use Server.ChannelCase, async: false
  alias Server.{Accounts, Discoveries, Friends, Homes, Presence, UserSocket, World, Worlds}

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

  test "the owner can enter their home, and their keepsakes show once chosen" do
    t = "home-own-#{System.unique_integer([:positive])}"
    uid = user_id(t)
    {:ok, _, _} = subscribe_and_join(connect_as(t), "world:home:" <> uid, %{})
    assert_push "world_spec", %{world_id: world_id, spec: %{"core" => empty}}
    assert world_id == "home:" <> uid
    assert empty["home"]["finds"] == []

    {:ok, :new} = Discoveries.record(uid, "hedge_seed")
    {:ok, _} = Homes.set_keepsakes(uid, ["hedge_seed"], 3)
    {:ok, _, _} = subscribe_and_join(connect_as(t), "world:home:" <> uid, %{})
    assert_push "world_spec", %{spec: %{"core" => grown}}
    # An old find with no stored card still gets its keepsake, from the template's legacy cards.
    assert Enum.any?(grown["props"], &(&1["type"] == "potted_hedge"))
  end

  test "a stranger can't enter someone's home" do
    owner = user_id("home-owner-#{System.unique_integer([:positive])}")
    assert {:error, %{reason: "not_allowed"}} =
             subscribe_and_join(connect_as("home-guest-#{System.unique_integer([:positive])}"), "world:home:" <> owner, %{})
  end

  test "a friend can visit, and sees the owner's companion napping at home" do
    o = "home-o-#{System.unique_integer([:positive])}"
    f = "home-f-#{System.unique_integer([:positive])}"
    owner = user_id(o)
    friend = user_id(f)
    {:ok, :requested} = Friends.request(owner, friend)
    {:ok, :friends} = Friends.accept(friend, owner)
    Homes.set_resident(owner, %{"companion_form" => %{"species" => "fox", "variant" => 1}})
    {:ok, _, _} = subscribe_and_join(connect_as(f), "world:home:" <> owner, %{})
    assert_push "world_spec", %{spec: %{"core" => core}}
    assert core["home"]["resident"]["companion_form"]["species"] == "fox"
  end

  test "closing a home sends visitors out and keeps friends out" do
    o = "close-o-#{System.unique_integer([:positive])}"
    f = "close-f-#{System.unique_integer([:positive])}"
    owner = user_id(o)
    friend = user_id(f)
    {:ok, :requested} = Friends.request(owner, friend)
    {:ok, :friends} = Friends.accept(friend, owner)
    {:ok, _, owner_socket} = subscribe_and_join(connect_as(o), "world:home:" <> owner, %{})
    {:ok, _, _} = subscribe_and_join(connect_as(f), "world:home:" <> owner, %{})
    wait_until(fn -> friend in Server.Social.visitors(owner) end)

    push(owner_socket, "set_home_closed", %{"closed" => true})
    assert_push "sent_home", %{}
    assert {:error, %{reason: "not_allowed"}} = subscribe_and_join(connect_as(f), "world:home:" <> owner, %{})
  end

  test "a one-off invite: offered, accepted, one visit" do
    o = "inv-o-#{System.unique_integer([:positive])}"
    g = "inv-g-#{System.unique_integer([:positive])}"
    owner = user_id(o)
    guest = user_id(g)
    w = seed_secret_world()
    {:ok, _, owner_socket} = subscribe_and_join(connect_as(o), "world:" <> w, %{})
    {:ok, _, guest_socket} = subscribe_and_join(connect_as(g), "world:" <> w, %{})
    wait_until(fn -> Map.has_key?(Presence.list("world:" <> w), guest) end)

    # Accepting an invite nobody sent does nothing.
    push(guest_socket, "invite_answer", %{"from" => owner, "accept" => true})
    assert_push "invite_result", %{ok: false}

    push(owner_socket, "invite_home", %{"to" => guest})
    assert_push "home_invite", %{from: ^owner}
    push(guest_socket, "invite_answer", %{"from" => owner, "accept" => true})
    assert_push "invite_result", %{ok: true, accepted: true}
    assert_push "invite_answer", %{guest: ^guest, accepted: true}

    {:ok, _, _} = subscribe_and_join(connect_as(g), "world:home:" <> owner, %{})
    # The pass was used up on the way in.
    assert {:error, %{reason: "not_allowed"}} = subscribe_and_join(connect_as(g), "world:home:" <> owner, %{})
  end

  test "joining pushes our generated name and friend code, and our identity carries that name" do
    t = "prof-#{System.unique_integer([:positive])}"
    uid = user_id(t)
    w = seed_secret_world()
    {:ok, _, socket} = subscribe_and_join(connect_as(t), "world:" <> w, %{})
    assert_push "profile", %{id: ^uid, name: name, friend_code: code}
    assert Server.Profiles.valid_name?(name) and String.length(code) == 6
    push(socket, "identity", %{"name" => "Someone Else", "appearance" => %{}})
    wait_until(fn -> get_in(Presence.list("world:" <> w), [uid, :metas]) |> hd() |> get_in([:identity, "name"]) == name end)
  end

  test "a friend code request reaches the other player, who can accept" do
    a = "code-a-#{System.unique_integer([:positive])}"
    b = "code-b-#{System.unique_integer([:positive])}"
    ua = user_id(a)
    ub = user_id(b)
    %{friend_code: code} = Server.Profiles.ensure(ub)
    w = seed_secret_world()
    {:ok, _, sa} = subscribe_and_join(connect_as(a), "world:" <> w, %{})
    {:ok, _, sb} = subscribe_and_join(connect_as(b), "world:" <> w, %{})
    push(sa, "friend_request", %{"code" => String.downcase(code)})
    assert_push "friend_result", %{ok: true, status: "requested"}
    assert_push "friend_request", %{from: ^ua}
    push(sb, "friend_accept", %{"from" => ua})
    wait_until(fn -> Friends.friends?(ua, ub) end)
    push(sa, "friend_request", %{"code" => "NOPE99"})
    assert_push "friend_result", %{ok: false, reason: "no_such_code"}
  end

  test "a find remembers the companion beside you and friends near you, and the journal shows it" do
    a = "find-a-#{System.unique_integer([:positive])}"
    b = "find-b-#{System.unique_integer([:positive])}"
    ua = user_id(a)
    ub = user_id(b)
    {:ok, :requested} = Friends.request(ua, ub)
    {:ok, :friends} = Friends.accept(ub, ua)
    w = seed_secret_world()
    {:ok, _, sa} = subscribe_and_join(connect_as(a), "world:" <> w, %{})
    {:ok, _, sb} = subscribe_and_join(connect_as(b), "world:" <> w, %{})
    push(sb, "state", %{"p" => [60.0, 20.0]})
    wait_until(fn -> Map.get(World.snapshot(w), ub, %{})["p"] == [60.0, 20.0] end)
    push(sa, "state", %{"p" => [0.0, 0.0], "c" => [30.0, 10.0]})
    wait_until(fn -> Map.get(World.snapshot(w), ua, %{})["c"] == [30.0, 10.0] end)

    push(sa, "claim_secret", %{"id" => "hedge_seed"})
    friend_name = Server.Profiles.name(ub)
    assert_push "secret_found", %{id: "hedge_seed", new: true, with: [^friend_name]}
    assert [{"hedge_seed", %{"together" => true, "world_name" => "Maze"}}] = Discoveries.cards(ua)

    push(sa, "journal", %{})
    assert_push "journal", %{owner: ^ua, entries: [%{id: "hedge_seed", world_name: "Maze", with: [^friend_name]}]}
  end

  test "keepsake choices are checked before they're kept" do
    t = "keep-#{System.unique_integer([:positive])}"
    uid = user_id(t)
    {:ok, :new} = Discoveries.record(uid, "hedge_seed")
    w = seed_secret_world()
    {:ok, _, socket} = subscribe_and_join(connect_as(t), "world:" <> w, %{})
    push(socket, "set_keepsakes", %{"ids" => ["hedge_seed"], "spots" => 3})
    assert_push "keepsakes_saved", %{ok: true}
    push(socket, "set_keepsakes", %{"ids" => ["someone_elses"], "spots" => 3})
    assert_push "keepsakes_saved", %{ok: false}
  end

  defp seed_world_with(core) do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{
        world_id: world_id,
        slug: "reveal-#{System.unique_integer([:positive])}",
        name: "Reveal",
        display_types: ["2d"],
        version: 1,
        spec: %{"core" => core, "profiles" => %{"2d" => %{}}}
      })

    world_id
  end

  test "the elder can only be claimed after a perfect hunt this visit" do
    t = "elder-#{System.unique_integer([:positive])}"
    uid = user_id(t)

    w =
      seed_world_with(%{
        "goal" => %{"type" => "find_salamanders", "count" => 10},
        "secret" => %{"id" => "elder_scale", "position" => [0.0, 0.0], "radius" => 120.0, "reveal" => %{"type" => "hunt_perfect"}}
      })

    {:ok, _, socket} = subscribe_and_join(connect_as(t), "world:" <> w, %{})
    stand_at(socket, w, uid, [5.0, 5.0])
    push(socket, "claim_secret", %{"id" => "elder_scale"})
    assert_push "secret_refused", %{id: "elder_scale"}

    push(socket, "hunt_complete", %{"found" => 9})
    assert_push "hunt_reward", %{found: 9}
    push(socket, "claim_secret", %{"id" => "elder_scale"})
    assert_push "secret_refused", %{id: "elder_scale"}

    push(socket, "hunt_complete", %{"found" => 10})
    assert_push "hunt_reward", %{found: 10}
    push(socket, "claim_secret", %{"id" => "elder_scale"})
    assert_push "secret_found", %{id: "elder_scale", new: true}
  end

  test "a lantern behind a shut door can't be claimed" do
    t = "lantern-#{System.unique_integer([:positive])}"
    uid = user_id(t)

    w =
      seed_world_with(%{
        "secret" => %{"id" => "warden_lantern", "position" => [0.0, 0.0], "radius" => 120.0,
                      "reveal" => %{"type" => "ward_open", "ward" => "paired_hall"}}
      })

    {:ok, _, socket} = subscribe_and_join(connect_as(t), "world:" <> w, %{})
    stand_at(socket, w, uid, [5.0, 5.0])
    push(socket, "claim_secret", %{"id" => "warden_lantern"})
    assert_push "secret_refused", %{id: "warden_lantern"}
  end

  test "browsing the directory from home doesn't trip over the home's non-catalog id" do
    t = "home-dir-#{System.unique_integer([:positive])}"
    uid = user_id(t)
    {:ok, _, socket} = subscribe_and_join(connect_as(t), "world:home:" <> uid, %{})
    push(socket, "list_worlds", %{"q" => "", "req" => 1})
    assert_push "world_list", %{req: 1}
  end
end
