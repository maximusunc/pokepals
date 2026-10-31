defmodule Server.ProfilesTest do
  use Server.DataCase, async: true
  alias Server.{Accounts, Profiles}

  defp user_id(token) do
    {:ok, a} = Accounts.resolve_token(token)
    a.user_id
  end

  test "a player is given a generated name and a friend code on first ensure, and keeps them" do
    uid = user_id("p-first")
    %{name: name, friend_code: code} = Profiles.ensure(uid)
    assert Profiles.valid_name?(name)
    assert String.length(code) == 6
    assert Profiles.ensure(uid) == %{name: name, friend_code: code}
  end

  test "re-rolling gives a different valid name" do
    uid = user_id("p-reroll")
    %{name: before} = Profiles.ensure(uid)
    after_ = Profiles.reroll_name(uid)
    assert after_ != before
    assert Profiles.valid_name?(after_)
    assert Profiles.name(uid) == after_
  end

  test "a friend code finds its player, however it's typed" do
    uid = user_id("p-code")
    %{friend_code: code} = Profiles.ensure(uid)
    loose = code |> String.downcase() |> String.split_at(3) |> then(fn {a, b} -> a <> "-" <> b end)
    assert Profiles.user_for_code(loose) == uid
    assert Profiles.user_for_code("ZZZZZZ9") == nil
  end

  test "names are never free text" do
    refute Profiles.valid_name?("Robert'); DROP TABLE")
    refute Profiles.valid_name?("Mossy Mossy")
  end
end
