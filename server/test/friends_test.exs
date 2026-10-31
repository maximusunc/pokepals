defmodule Server.FriendsTest do
  use Server.DataCase, async: false
  alias Server.{Accounts, Friends}

  defp user_id(token) do
    {:ok, a} = Accounts.resolve_token(token <> "-#{System.unique_integer([:positive])}")
    a.user_id
  end

  test "a request waits, and accepting makes friends both ways" do
    a = user_id("f-a")
    b = user_id("f-b")
    assert {:ok, :requested} = Friends.request(a, b)
    assert Friends.incoming(b) == [a]
    assert Friends.outgoing(a) == [b]
    refute Friends.friends?(a, b)
    assert {:ok, :friends} = Friends.accept(b, a)
    assert Friends.friends?(a, b) and Friends.friends?(b, a)
    assert Friends.incoming(b) == []
  end

  test "asking someone who already asked you makes you friends" do
    a = user_id("f-c")
    b = user_id("f-d")
    {:ok, :requested} = Friends.request(a, b)
    assert {:ok, :friends} = Friends.request(b, a)
    assert Friends.friends?(a, b)
  end

  test "you can't befriend yourself, twice, or across a block" do
    a = user_id("f-e")
    b = user_id("f-f")
    assert {:error, :self} = Friends.request(a, a)
    Friends.block(b, a)
    assert {:error, :blocked} = Friends.request(a, b)
    assert {:error, :blocked} = Friends.request(b, a)
  end

  test "accepting a request that was never made does nothing" do
    a = user_id("f-g")
    b = user_id("f-h")
    assert {:error, :no_request} = Friends.accept(b, a)
    refute Friends.friends?(a, b)
  end

  test "declining and removing are quiet and complete" do
    a = user_id("f-i")
    b = user_id("f-j")
    {:ok, :requested} = Friends.request(a, b)
    Friends.decline(b, a)
    assert Friends.outgoing(a) == []
    {:ok, :requested} = Friends.request(a, b)
    {:ok, :friends} = Friends.accept(b, a)
    Friends.remove(b, a)
    refute Friends.friends?(a, b) or Friends.friends?(b, a)
  end

  test "a block ends the friendship and pending requests" do
    a = user_id("f-k")
    b = user_id("f-l")
    {:ok, :requested} = Friends.request(a, b)
    {:ok, :friends} = Friends.accept(b, a)
    Friends.block(a, b)
    refute Friends.friends?(a, b)
    assert Friends.blocked(a) == [b]
    assert Friends.blocked_either_way?(b, a)
  end

  test "changes are announced on each player's own topic" do
    a = user_id("f-m")
    b = user_id("f-n")
    Phoenix.PubSub.subscribe(Server.PubSub, Friends.user_topic(b))
    Friends.request(a, b)
    assert_receive {:friends_changed}
  end
end
