defmodule Server.AccountsTest do
  use Server.DataCase, async: true
  alias Server.Accounts

  test "an unknown token mints a fresh account and returns its user_id" do
    {:ok, account} = Accounts.resolve_token("tok-new")

    assert account.token == "tok-new"
    assert is_binary(account.user_id)
    assert account.status == "active"
    # Claim columns are empty until a player upgrades.
    assert account.email == nil
    assert account.username == nil
  end

  test "the same token always resolves to the same user_id" do
    {:ok, first} = Accounts.resolve_token("tok-stable")
    {:ok, again} = Accounts.resolve_token("tok-stable")

    assert first.user_id == again.user_id
  end

  test "different tokens get distinct user_ids" do
    {:ok, a} = Accounts.resolve_token("tok-a")
    {:ok, b} = Accounts.resolve_token("tok-b")

    refute a.user_id == b.user_id
  end
end
