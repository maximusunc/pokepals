defmodule Server.DevicesTest do
  use Server.DataCase, async: true
  alias Server.{Accounts, Devices}

  defp account do
    {:ok, account, device} = Accounts.resolve_device("dev-#{System.unique_integer([:positive])}", "First")
    {account.user_id, device}
  end

  defp hash, do: Devices.hash_token("dev-extra-#{System.unique_integer([:positive])}")

  test "hash_token is lowercase hex SHA-256 (what the backfill writes)" do
    assert Devices.hash_token("abc") ==
             "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  end

  test "clean_name trims, caps and drops blanks" do
    assert Devices.clean_name("  Sam's phone  ") == "Sam's phone"
    assert Devices.clean_name(String.duplicate("x", 100)) |> String.length() == 40
    assert Devices.clean_name("   ") == nil
    assert Devices.clean_name(nil) == nil
    assert Devices.clean_name(42) == nil
  end

  test "the list puts this device first, then the most recently seen, and skips signed-out ones" do
    {uid, first} = account()
    {:ok, old} = Devices.add(uid, hash(), "Old")
    {:ok, gone} = Devices.add(uid, hash(), "Gone")
    {:ok, recent} = Devices.add(uid, hash(), "Recent")

    old |> Ecto.Changeset.change(last_seen_at: DateTime.add(DateTime.utc_now(), -3600)) |> Repo.update!()
    recent |> Ecto.Changeset.change(last_seen_at: DateTime.add(DateTime.utc_now(), 60)) |> Repo.update!()
    :ok = Devices.revoke(uid, first.device_id, gone.device_id)

    list = Devices.list_view(uid, old.device_id)
    assert Enum.map(list, & &1.name) == ["Old", "Recent", "First"]
    assert [%{current: true, id: id} | rest] = list
    assert id == old.device_id
    refute Enum.any?(rest, & &1.current)
    assert Enum.all?(list, &is_integer(&1.last_seen_ms))
  end

  test "an account holds at most 10 signed-in devices" do
    {uid, _first} = account()
    for _ <- 2..10, do: {:ok, _} = Devices.add(uid, hash(), "More")
    assert Devices.add(uid, hash(), "One too many") == {:error, :too_many}
  end

  test "a hash already on a device can't be added again" do
    {uid, _} = account()
    h = hash()
    {:ok, _} = Devices.add(uid, h, "A")
    assert Devices.add(uid, h, "B") == {:error, :taken}
  end

  test "revoke signs out another device of the same account, and tells the player" do
    {uid, first} = account()
    {:ok, other} = Devices.add(uid, hash(), "Other")
    Phoenix.PubSub.subscribe(Server.PubSub, Server.Friends.user_topic(uid))

    assert Devices.revoke(uid, first.device_id, other.device_id) == :ok
    assert_receive {:signed_out, id}
    assert id == other.device_id
    assert_receive {:devices_changed}
    assert Devices.get_active(other.device_id) == nil

    # Again: it's gone already.
    assert Devices.revoke(uid, first.device_id, other.device_id) == {:error, :not_found}
  end

  test "revoke refuses this device, someone else's, and nonsense" do
    {uid, first} = account()
    {stranger, theirs} = account()
    refute uid == stranger

    assert Devices.revoke(uid, first.device_id, first.device_id) == {:error, :current}
    assert Devices.revoke(uid, first.device_id, theirs.device_id) == {:error, :not_found}
    assert Devices.revoke(uid, first.device_id, "not-a-uuid") == {:error, :not_found}
    assert Devices.revoke(uid, first.device_id, nil) == {:error, :not_found}
    assert Devices.get_active(theirs.device_id)
  end
end
