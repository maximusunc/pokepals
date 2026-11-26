defmodule Server.WishesTest do
  @moduledoc "Lingerlong's wishing fountain: the rules (Server.Wishes) and the `wish` over the channel."
  use Server.ChannelCase, async: false
  alias Server.{Accounts, Economy, Repo, UserSocket, Wishes, WorldCounter, Worlds}

  @fountain %{"id" => "wishing_fountain", "center" => [0, 240], "radius" => 72}

  defp seed_world(core) do
    world_id = Ecto.UUID.generate()

    {:ok, _} =
      Worlds.upsert(%{world_id: world_id, slug: "wish-#{System.unique_integer([:positive])}", name: "Wish",
        display_types: ["2d"], version: 1, spec: %{"core" => core, "profiles" => %{"2d" => %{}}}})

    world_id
  end

  defp join_world(world_id) do
    token = "wish-#{System.unique_integer([:positive])}"
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    {:ok, _, socket} = subscribe_and_join(socket, "world:" <> world_id, %{})
    {:ok, account} = Accounts.resolve_token(token)
    {socket, account.user_id}
  end

  describe "the rules" do
    test "a fountain comes from the spec, and only when it has a centre" do
      assert %{center: {0, 240}, radius: 72} = Wishes.fountain(%{"fountain" => @fountain})
      assert Wishes.fountain(%{"fountain" => %{"radius" => 3}}) == nil
      assert Wishes.fountain(%{}) == nil
      assert Wishes.fountain(nil) == nil
    end

    test "near the fountain is its rim plus a little" do
      f = Wishes.fountain(%{"fountain" => @fountain})
      assert Wishes.near?(f, [0, 240 + 72 + 100])
      assert Wishes.near?(f, [150, 244])
      refute Wishes.near?(f, [0, 240 + 72 + 120])
      refute Wishes.near?(f, nil)
      refute Wishes.near?(nil, [0, 240])
    end

    test "one wish per gap" do
      assert Wishes.allow?(nil, 5)
      refute Wishes.allow?(1_000, 1_000 + Wishes.min_gap_ms() - 1)
      assert Wishes.allow?(1_000, 1_000 + Wishes.min_gap_ms())
    end

    test "the relay to everyone is capped per world per second" do
      w = "relay-#{System.unique_integer([:positive])}"
      t = 10_000_000
      sent = Enum.count(1..20, fn _ -> Wishes.relay?(w, t) end)
      assert sent == Wishes.relay_per_sec()
      assert Wishes.relay?(w, t + 1000)
      assert Wishes.relay?("other-" <> w, t)
    end

    test "the count is kept for good" do
      w = "count-#{System.unique_integer([:positive])}"
      assert Wishes.count(w) == 0
      assert Wishes.add(w) == 1
      assert Wishes.add(w) == 2
      Wishes.flush()
      assert Repo.get_by(WorldCounter, world_id: w, key: "wishes").value == 2
      # forget the cache: the next read comes back from Postgres, and adding goes on from there
      Wishes.forget_cache()
      assert Wishes.count(w) == 2
      assert Wishes.add(w) == 3
      Wishes.flush()
      assert Repo.get_by(WorldCounter, world_id: w, key: "wishes").value == 3
    end
  end

  describe "wishing over the channel" do
    test "joining a fountain world says how many wishes it holds; other worlds say nothing" do
      w = seed_world(%{"fountain" => @fountain})
      {_s, _uid} = join_world(w)
      assert_push "wishes", %{n: 0}

      plain = seed_world(%{})
      {_s2, _} = join_world(plain)
      refute_push "wishes", %{}
    end

    test "a wish costs a coin, counts, and reaches everyone else" do
      w = seed_world(%{"fountain" => @fountain})
      {s1, uid} = join_world(w)
      {_s2, _} = join_world(w)
      {:ok, _} = Economy.grant_currency(uid, "coins", 5)
      before = Economy.balance(uid, "coins")
      left = before - 1

      push(s1, "state", %{"p" => [0, 360]})
      push(s1, "wish", %{})
      assert_push "wish_ok", %{n: 1, paid: true, balance: ^left}
      assert_push "wished", %{by: ^uid, n: 1, paid: true}
      assert Economy.balance(uid, "coins") == left
      assert Economy.ledger_balance(uid, "coins") == left
    end

    test "with no coins the wish is free" do
      w = seed_world(%{"fountain" => @fountain})
      {s, uid} = join_world(w)
      case Economy.balance(uid, "coins") do
        0 -> :ok
        all -> {:ok, 0} = Economy.sink_currency(uid, "coins", all)
      end

      push(s, "state", %{"p" => [60, 330]})
      push(s, "wish", %{})
      assert_push "wish_ok", %{n: 1, paid: false, balance: 0}
      assert Economy.balance(uid, "coins") == 0
    end

    test "one wish per gap; the next is turned away" do
      w = seed_world(%{"fountain" => @fountain})
      {s, _uid} = join_world(w)
      push(s, "state", %{"p" => [0, 340]})
      push(s, "wish", %{})
      assert_push "wish_ok", %{n: 1}
      push(s, "wish", %{})
      assert_push "wish_refused", %{reason: "too_soon"}
      assert Wishes.count(w) == 1
    end

    test "refused away from the fountain, and in a world without one" do
      w = seed_world(%{"fountain" => @fountain})
      {s, _} = join_world(w)
      push(s, "state", %{"p" => [600, 900]})
      push(s, "wish", %{})
      assert_push "wish_refused", %{reason: "away"}

      plain = seed_world(%{})
      {s2, _} = join_world(plain)
      push(s2, "state", %{"p" => [0, 240]})
      push(s2, "wish", %{})
      assert_push "wish_refused", %{reason: "no_fountain"}
      assert Wishes.count(w) == 0
    end

    test "the count survives the cache being forgotten (a restart)" do
      w = seed_world(%{"fountain" => @fountain})
      {s, _} = join_world(w)
      push(s, "state", %{"p" => [0, 340]})
      push(s, "wish", %{})
      assert_push "wish_ok", %{n: 1}
      Wishes.flush()
      Wishes.forget_cache()

      {_s2, _} = join_world(w)
      assert_push "wishes", %{n: 1}
    end
  end
end
