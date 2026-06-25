defmodule Server.SavesTest do
  use Server.DataCase, async: true
  alias Server.{Accounts, Saves}

  # Saves are keyed by user_id now, and user_id is a real FK into accounts, so each test resolves a
  # token to an account first (exactly as the socket does at connect).
  defp user_id(token) do
    {:ok, account} = Accounts.resolve_token(token)
    account.user_id
  end

  test "a brand-new player has no companion or appearance yet" do
    assert Saves.load(user_id("fresh")) == %{companion: nil, appearance: nil}
  end

  test "store then load round-trips the companion + appearance blobs" do
    uid = user_id("u1")
    {:ok, _} = Saves.store(uid, %{"bond" => 0.5}, %{"equipped" => %{"hat" => "base:hat"}})

    assert Saves.load(uid) == %{
             companion: %{"bond" => 0.5},
             appearance: %{"equipped" => %{"hat" => "base:hat"}}
           }
  end

  test "storing again upserts (last write wins) rather than erroring on the same user" do
    uid = user_id("u2")
    {:ok, _} = Saves.store(uid, %{"bond" => 0.1}, %{})
    {:ok, _} = Saves.store(uid, %{"bond" => 0.9}, %{"colors" => %{"skin" => "warm"}})

    assert Saves.load(uid) == %{
             companion: %{"bond" => 0.9},
             appearance: %{"colors" => %{"skin" => "warm"}}
           }
  end

  test "nil blobs are coerced to empty maps (NOT NULL jsonb columns)" do
    uid = user_id("u3")
    {:ok, _} = Saves.store(uid, nil, nil)

    assert Saves.load(uid) == %{companion: %{}, appearance: %{}}
  end

  test "two players' saves are independent" do
    a = user_id("p-a")
    b = user_id("p-b")
    {:ok, _} = Saves.store(a, %{"who" => "a"}, %{})
    {:ok, _} = Saves.store(b, %{"who" => "b"}, %{})

    assert Saves.load(a).companion == %{"who" => "a"}
    assert Saves.load(b).companion == %{"who" => "b"}
  end
end
