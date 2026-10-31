defmodule Server.HomesTest do
  use Server.DataCase, async: false
  alias Server.{Accounts, Discoveries, Friends, HomePasses, Homes}

  defp user_id(token) do
    {:ok, a} = Accounts.resolve_token(token <> "-#{System.unique_integer([:positive])}")
    a.user_id
  end

  defp befriend(a, b) do
    {:ok, :requested} = Friends.request(a, b)
    {:ok, :friends} = Friends.accept(b, a)
  end

  test "the owner can always visit; a stranger never can" do
    owner = user_id("h-owner")
    stranger = user_id("h-stranger")
    assert Homes.can_visit?(owner, owner)
    refute Homes.can_visit?(stranger, owner)
  end

  test "friends can visit, until the home is closed" do
    owner = user_id("h-o2")
    friend = user_id("h-f2")
    befriend(owner, friend)
    assert Homes.can_visit?(friend, owner)
    Homes.set_closed(owner, true)
    refute Homes.can_visit?(friend, owner)
    assert Homes.can_visit?(owner, owner)
    Homes.set_closed(owner, false)
    assert Homes.can_visit?(friend, owner)
  end

  test "a one-off pass admits a non-friend once" do
    owner = user_id("h-o3")
    guest = user_id("h-g3")
    refute HomePasses.take_offer(owner, guest)
    HomePasses.offer(owner, guest)
    assert HomePasses.take_offer(owner, guest)
    refute HomePasses.take_offer(owner, guest)
    HomePasses.grant(owner, guest)
    assert Homes.can_visit?(guest, owner)
    HomePasses.consume(owner, guest)
    refute Homes.can_visit?(guest, owner)
  end

  test "a block shuts the door even on a pass" do
    owner = user_id("h-o4")
    guest = user_id("h-g4")
    HomePasses.grant(owner, guest)
    Friends.block(owner, guest)
    refute Homes.can_visit?(guest, owner)
  end

  test "keepsake choices must be real finds, within the spots, and spots within 3..7" do
    owner = user_id("h-o5")
    {:ok, :new} = Discoveries.record(owner, "hedge_seed")
    assert {:ok, home} = Homes.set_keepsakes(owner, ["hedge_seed"], 4)
    assert home.keepsakes == ["hedge_seed"] and home.spots == 4
    assert {:error, :invalid} = Homes.set_keepsakes(owner, ["not_mine"], 4)
    assert {:error, :invalid} = Homes.set_keepsakes(owner, ["hedge_seed"], 9)
    assert {:error, :invalid} = Homes.set_keepsakes(owner, ["hedge_seed", "hedge_seed"], 4)
    assert Homes.get(owner).keepsakes == ["hedge_seed"]
  end

  test "the resident look is kept to the companion's presentation only" do
    owner = user_id("h-o6")
    Homes.set_resident(owner, %{"name" => "x", "appearance" => %{}, "companion_look" => %{"ear" => 1}, "companion_form" => %{"species" => "fox"}})
    assert Homes.get(owner).resident == %{"companion_look" => %{"ear" => 1}, "companion_form" => %{"species" => "fox"}}
  end
end
