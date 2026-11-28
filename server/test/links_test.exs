defmodule Server.LinksTest do
  # Not async: the rate limiter's counters are shared by the whole node.
  use Server.DataCase, async: false
  alias Server.{Accounts, Devices, Friends, LinkCode, Links, LinkThrottle}

  setup do
    LinkThrottle.reset()
    on_exit(&LinkThrottle.reset/0)
    {:ok, account} = Accounts.resolve_token("owner-#{System.unique_integer([:positive])}")
    Phoenix.PubSub.subscribe(Server.PubSub, Friends.user_topic(account.user_id))
    %{uid: account.user_id}
  end

  defp fresh_token, do: "new-#{System.unique_integer([:positive])}"
  @ip {10, 0, 0, 1}

  test "a code is 8 unambiguous characters, shown with a dash", %{uid: uid} do
    code = Links.new_code(uid)
    assert code =~ ~r/^[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}$/
  end

  test "redeem -> the owner is asked -> allow -> linked", %{uid: uid} do
    code = Links.new_code(uid)
    token = fresh_token()

    assert Links.redeem(code, token, "  Kitchen tablet ", @ip) == :pending
    assert_receive {:link_request, "Kitchen tablet"}

    # Polling the same request keeps answering pending.
    assert Links.redeem(code, token, "Kitchen tablet", @ip) == :pending

    assert Links.answer(uid, true) == :ok
    assert_receive {:devices_changed}
    assert Links.redeem(code, token, "Kitchen tablet", @ip) == :linked

    {:ok, account, device} = Accounts.resolve_device(token)
    assert account.user_id == uid
    assert device.name == "Kitchen tablet"

    # Used up: a different device can't use it now.
    assert Links.redeem(code, fresh_token(), "x", @ip) == :invalid
  end

  test "the code is read case-insensitively, without the dash or spaces", %{uid: uid} do
    code = Links.new_code(uid)
    typed = code |> String.downcase() |> String.replace("-", " ")
    assert Links.redeem(" " <> typed, fresh_token(), "x", @ip) == :pending
  end

  test "deny -> denied, and the code is spent", %{uid: uid} do
    code = Links.new_code(uid)
    token = fresh_token()
    assert Links.redeem(code, token, "x", @ip) == :pending
    assert Links.answer(uid, false) == :ok
    assert Links.redeem(code, token, "x", @ip) == :denied
    assert Devices.by_token(token) == nil
    assert Links.answer(uid, true) == {:error, :expired}
  end

  test "a code already pending for one device is invalid for another", %{uid: uid} do
    code = Links.new_code(uid)
    assert Links.redeem(code, fresh_token(), "first", @ip) == :pending
    assert Links.redeem(code, fresh_token(), "second", @ip) == :invalid
  end

  test "an expired code is invalid, pending or not", %{uid: uid} do
    code = Links.new_code(uid)
    token = fresh_token()
    assert Links.redeem(code, token, "x", @ip) == :pending

    Repo.update_all(LinkCode, set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])
    assert Links.redeem(code, token, "x", @ip) == :invalid
    assert Links.answer(uid, true) == {:error, :expired}

    other = Links.new_code(uid)
    Repo.update_all(LinkCode, set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])
    assert Links.redeem(other, fresh_token(), "x", @ip) == :invalid
  end

  test "asking for a new code voids the last", %{uid: uid} do
    old = Links.new_code(uid)
    new = Links.new_code(uid)
    assert Links.redeem(old, fresh_token(), "x", @ip) == :invalid
    assert Links.redeem(new, fresh_token(), "x", @ip) == :pending
  end

  test "a token that already belongs to a device can't be linked", %{uid: uid} do
    {:ok, _} = Accounts.resolve_token("someone-elses")
    code = Links.new_code(uid)
    assert Links.redeem(code, "someone-elses", "x", @ip) == :invalid
    assert Links.redeem(code, "", "x", @ip) == :invalid
    assert Links.redeem(code, nil, "x", @ip) == :invalid
  end

  test "allowing over the device cap turns the new device away", %{uid: uid} do
    for _ <- 2..10, do: {:ok, _} = Devices.add(uid, Devices.hash_token(fresh_token()), "More")
    code = Links.new_code(uid)
    token = fresh_token()
    assert Links.redeem(code, token, "x", @ip) == :pending
    assert Links.answer(uid, true) == {:error, :too_many}
    assert Links.redeem(code, token, "x", @ip) == :denied
    assert Devices.by_token(token) == nil
  end

  test "about ten wrong codes from one IP, then slow_down; polling doesn't count", %{uid: uid} do
    code = Links.new_code(uid)
    token = fresh_token()
    assert Links.redeem(code, token, "x", @ip) == :pending

    for _ <- 1..10, do: assert(Links.redeem("ZZZZ-ZZZZ", fresh_token(), "x", @ip) == :invalid)
    assert Links.redeem("ZZZZ-ZZZZ", fresh_token(), "x", @ip) == :slow_down

    # The device already waiting keeps polling fine; another IP is unaffected.
    for _ <- 1..20, do: assert(Links.redeem(code, token, "x", @ip) == :pending)
    assert Links.redeem("ZZZZ-ZZZZ", fresh_token(), "x", {10, 0, 0, 2}) == :invalid
  end

  test "the global backstop limits everyone at once" do
    Application.put_env(:server, LinkThrottle, global: 3)
    on_exit(fn -> Application.delete_env(:server, LinkThrottle) end)

    for n <- 1..3, do: assert(Links.redeem("ZZZZ-ZZZZ", fresh_token(), "x", {10, 1, 0, n}) == :invalid)
    assert Links.redeem("ZZZZ-ZZZZ", fresh_token(), "x", {10, 1, 0, 9}) == :slow_down
  end
end
