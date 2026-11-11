defmodule Server.FishingTest do
  @moduledoc """
  Fishing's rules (Server.Fishing), the hotbar it fills (Server.Hotbar), and catches piling up in one
  inventory stack (Economy.grant_stack). The channel flow is in fishing_channel_test.exs.
  """
  use Server.DataCase, async: true

  alias Server.{Accounts, Economy, Fishing, Hotbar}

  defp new_user do
    {:ok, account} = Accounts.resolve_token("fish-#{System.unique_integer([:positive])}")
    account.user_id
  end

  setup do
    Fishing.seed_definitions()
    :ok
  end

  describe "rolling a catch" do
    test "every roll lands on a real catch, from the first to the last" do
      assert Fishing.roll(0.0).key == "minnow"
      assert %{} = Fishing.roll(0.5)
      assert Fishing.roll(0.999_999).key == "sea_glass"
      assert Fishing.roll(1.0).key == "sea_glass"
    end

    test "rare fish are rare and commons are common" do
      kinds =
        for i <- 0..999, do: Fishing.roll(i / 1000).kind

      freq = Enum.frequencies(kinds)
      assert freq["fish"] > 800
      assert freq["rare_fish"] in 30..70
      assert freq["material"] in 60..120
    end

    test "rarer catches ask more of you: a narrower window and a quicker ring" do
      minnow = Enum.find(Fishing.catches(), &(&1.key == "minnow"))
      whiskers = Enum.find(Fishing.catches(), &(&1.key == "old_whiskers"))
      assert whiskers.ring.window < minnow.ring.window
      assert whiskers.ring.speed > minnow.ring.speed
    end

    test "the hook tells the client only the wait and the ring, not the catch" do
      payload = Fishing.hook_payload(Fishing.roll(0.0), 2_000)
      assert Map.keys(payload) |> Enum.sort() == [:speed, :wait_ms, :window]
    end
  end

  describe "timing" do
    test "a reel counts from just before the bite until the ring could have run out" do
      assert Fishing.reel_in_time?(1_000, 2_000, 3_000)
      assert Fishing.reel_in_time?(1_000, 2_000, 2_700)
      refute Fishing.reel_in_time?(1_000, 2_000, 2_000)
      assert Fishing.reel_in_time?(1_000, 2_000, 9_900)
      refute Fishing.reel_in_time?(1_000, 2_000, 10_100)
    end
  end

  describe "where" do
    test "fishing is on by default, and a world can opt out" do
      assert Fishing.allowed?(%{})
      assert Fishing.allowed?(nil)
      assert Fishing.allowed?(%{"fishing" => true})
      refute Fishing.allowed?(%{"fishing" => false})
    end

    test "the rod can only be taken standing at its post" do
      core = %{"props" => [%{"id" => "rod_post", "position" => [100, 50], "gives" => "rod"}, %{"id" => "x"}]}
      assert Fishing.at_rod_post?(core, [120.0, 60.0])
      refute Fishing.at_rod_post?(core, [400.0, 60.0])
      refute Fishing.at_rod_post?(core, nil)
      refute Fishing.at_rod_post?(%{"props" => [%{"position" => [0, 0]}]}, [0.0, 0.0])
    end
  end

  describe "the item definitions" do
    test "the rod is a usable tool; catches stack; only common fish and materials sell" do
      defs = Map.new(Fishing.item_defs(), &{&1.item_def_id, &1})
      rod = defs[Fishing.rod_id()]
      assert rod.category == "tool"
      assert rod.base_attributes["use"] == "fish"

      for c <- Fishing.catches() do
        d = defs[c.id]
        assert d.stackable
        assert d.category == c.kind
        assert Map.has_key?(d.base_attributes, "sell") == (c.kind != "rare_fish")
      end
    end
  end

  describe "the hotbar" do
    test "starts empty, and a new item drops into the first free slot, once" do
      uid = new_user()
      assert Hotbar.slots(uid) == [nil, nil, nil, nil, nil]
      assert Hotbar.place(uid, Fishing.rod_id()) == [Fishing.rod_id(), nil, nil, nil, nil]
      assert Hotbar.place(uid, Fishing.rod_id()) == [Fishing.rod_id(), nil, nil, nil, nil]
      assert Hotbar.slots(uid) == [Fishing.rod_id(), nil, nil, nil, nil]
    end
  end

  describe "catches in the inventory" do
    test "pile up in one stack per kind, each grant ledgered" do
      uid = new_user()
      {:ok, a} = Economy.grant_stack(uid, 200)
      {:ok, b} = Economy.grant_stack(uid, 200, 2)
      assert a.item_instance_id == b.item_instance_id
      assert Economy.owned_quantity(uid, 200) == 3
      assert Economy.owned_quantity(uid, 201) == 0

      {:ok, _} = Economy.grant_stack(uid, 241)
      summary = Economy.inventory_summary(uid)
      assert [%{item_def_id: 200, quantity: 3, name: "Silver Minnow"}, %{item_def_id: 241, quantity: 1}] = summary

      assert Economy.ledger_balance(uid, "coins") == Economy.balance(uid, "coins")
    end
  end
end
