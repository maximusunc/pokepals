defmodule Server.AccountsTest do
  use Server.DataCase, async: true
  alias Server.{Accounts, Device, Devices, Economy}

  test "an unknown token mints a fresh account, with that token as its first device" do
    {:ok, account} = Accounts.resolve_token("tok-new")

    assert is_binary(account.user_id)
    assert account.status == "active"
    # Claim columns are empty until a player upgrades.
    assert account.email == nil
    assert account.username == nil

    # Only the token's hash is kept, on a device, never on the account.
    device = Repo.get_by!(Device, token_hash: Devices.hash_token("tok-new"))
    assert device.user_id == account.user_id
    assert device.revoked_at == nil
    assert Repo.one(from(a in "accounts", where: a.user_id == type(^account.user_id, :binary_id), select: a.token)) == nil

    # The welcome gift, once.
    assert Economy.balance(account.user_id, "coins") == 120
    {:ok, _} = Accounts.resolve_token("tok-new")
    assert Economy.balance(account.user_id, "coins") == 120
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

  test "resolve_device returns the device, named on first sight" do
    {:ok, account, device} = Accounts.resolve_device("tok-named", "Sam's phone")
    assert device.user_id == account.user_id
    assert device.name == "Sam's phone"

    {:ok, _, same} = Accounts.resolve_device("tok-named", "Other name")
    assert same.device_id == device.device_id
    assert same.name == "Sam's phone"
  end

  test "a signed-out device's token is refused and never mints a new account" do
    {:ok, account, device} = Accounts.resolve_device("tok-gone")
    {:ok, other, _} = Accounts.resolve_device("tok-keeper")
    assert other.user_id != account.user_id

    # Sign it out from a second device of the same account.
    {:ok, second} = Devices.add(account.user_id, Devices.hash_token("tok-gone-2"), "Second")
    :ok = Devices.revoke(account.user_id, second.device_id, device.device_id)

    count = Repo.aggregate(Server.Account, :count)
    assert Accounts.resolve_token("tok-gone") == {:error, :revoked}
    assert Repo.aggregate(Server.Account, :count) == count
  end
end
