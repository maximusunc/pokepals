defmodule Server.DiscoveriesTest do
  use Server.DataCase, async: true
  alias Server.{Accounts, Discoveries}

  defp user_id(token) do
    {:ok, account} = Accounts.resolve_token(token)
    account.user_id
  end

  @core %{"secret" => %{"id" => "hedge_seed", "position" => [-52.0, -44.0], "radius" => 120.0}}

  test "a new player has found nothing" do
    assert Discoveries.list(user_id("d-fresh")) == []
  end

  test "recording is new the first time and already after that" do
    uid = user_id("d-once")
    assert Discoveries.record(uid, "hedge_seed") == {:ok, :new}
    assert Discoveries.record(uid, "hedge_seed") == {:ok, :already}
    assert Discoveries.list(uid) == ["hedge_seed"]
  end

  test "discoveries are per player" do
    a = user_id("d-a")
    b = user_id("d-b")
    {:ok, :new} = Discoveries.record(a, "hedge_seed")
    assert Discoveries.list(b) == []
    assert Discoveries.record(b, "hedge_seed") == {:ok, :new}
  end

  describe "claimable?/3" do
    test "honours a claim for this world's secret, standing at it" do
      assert Discoveries.claimable?(@core, "hedge_seed", [-40.0, -30.0])
    end

    test "refuses a claim from too far away" do
      refute Discoveries.claimable?(@core, "hedge_seed", [400.0, 400.0])
    end

    test "refuses a secret this world doesn't carry" do
      refute Discoveries.claimable?(@core, "glow_pearl", [-52.0, -44.0])
      refute Discoveries.claimable?(%{}, "hedge_seed", [-52.0, -44.0])
    end

    test "refuses when we don't know where the player is" do
      refute Discoveries.claimable?(@core, "hedge_seed", nil)
    end
  end
end
